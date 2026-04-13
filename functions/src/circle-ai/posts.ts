/**
 * サークルAI投稿機能
 * - generateCircleAIPosts: 定期実行（Cloud Scheduler）
 * - executeCircleAIPost: Cloud Tasks ワーカー
 * - triggerCircleAIPosts: 手動トリガー（管理者用）
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as functionsV1 from "firebase-functions/v1";
import { scheduleHttpTask } from "../helpers/cloud-tasks";
import { db, FieldValue, Timestamp } from "../helpers/firebase";
import { isAdmin } from "../helpers/admin";
import {
  computeCircleAIPostRetryAt,
  computeNextCircleAIPostAt,
} from "../helpers/circle-scheduling";
import { PROJECT_ID, LOCATION } from "../config/constants";
import { geminiApiKey, openaiApiKey } from "../config/secrets";
import { createAIProviderFactory } from "../ai/provider";
import { AUTH_ERRORS, SYSTEM_ERRORS } from "../config/messages";

// テスト用: 本番は 100
const MAX_CIRCLES_PER_RUN = 3;
const AI_POST_REQUEST_STALE_MS = 2 * 60 * 1000;

type GeneratedAI = {
  id: string;
  name: string;
  avatarIndex: number;
};

type CircleAITarget = {
  circleId: string;
  circleName: string;
  circleDescription: string;
  circleCategory: string;
  circleRules: string;
  circleGoal: string;
  generatedAIs: GeneratedAI[];
  nextCircleAIPostAt: Date | null;
};

type AIPostRequestBeginResult =
  | { kind: "continue"; ref: FirebaseFirestore.DocumentReference }
  | { kind: "succeeded"; postId: string };

function getCircleAIPostPrompt(
  aiName: string,
  circleName: string,
  circleDescription: string,
  category: string,
  circleRules: string,
  circleGoal: string,
  recentPosts: string[] = []
): string {
  const recentPostsSection = recentPosts.length > 0
    ? `
【避けるべき内容】
以下は最近の投稿です。これらと似た内容や同じ表現は絶対に使わないでください：
${recentPosts.map((p) => `- ${p}`).join("\n")}
`
    : "";

  return `
あなたは「ほめっぷ」というSNSのユーザー「${aiName}」です。
サークル「${circleName}」のメンバーとして投稿します。

【サークル機能について】
サークルは同じ趣味や興味を持つユーザーが集まるコミュニティです。
メンバーはサークルのテーマに関する日常の出来事、感想、発見などを自由に共有します。

【サークル情報】
- サークル名: ${circleName}
- カテゴリ: ${category}
- 説明: ${circleDescription}
- ルール: ${circleRules || "なし"}
- 目標: ${circleGoal || "なし"}

【投稿のルール】
1. サークルのテーマに沿った投稿をしてください
2. ルールがある場合は、そのルールを遵守してください
3. 目標がある場合は、その目標に向かって努力している姿勢で投稿してください
4. 自然な日本語で、SNSらしいカジュアルな投稿にしてください
5. 30〜80文字程度の短い投稿にしてください
6. ハッシュタグ（#○○）は絶対に使用しないでください
7. 毎回異なる内容・表現で投稿してください（同じ文章の使い回しNG）

【避けるべき表現】
- ハッシュタグ（#勉強 #資格 など）
- 前回と同じ内容
- 同じフレーズの繰り返し
${recentPostsSection}
【あなたの投稿】
`;
}

function normalizeGeneratedAIs(value: unknown): GeneratedAI[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is GeneratedAI =>
      !!item &&
      typeof item === "object" &&
      typeof (item as GeneratedAI).id === "string" &&
      typeof (item as GeneratedAI).name === "string" &&
      typeof (item as GeneratedAI).avatarIndex === "number"
    );
}

function toCircleAITarget(
  doc: FirebaseFirestore.QueryDocumentSnapshot
): CircleAITarget | null {
  const data = doc.data();
  if (data.isDeleted === true) return null;

  const generatedAIs = normalizeGeneratedAIs(data.generatedAIs);
  if (generatedAIs.length === 0) return null;

  return {
    circleId: doc.id,
    circleName: data.name || "サークル",
    circleDescription: data.description || "",
    circleCategory: data.category || "その他",
    circleRules: data.rules || "",
    circleGoal: data.goal || "",
    generatedAIs,
    nextCircleAIPostAt: data.nextCircleAIPostAt?.toDate?.() || null,
  };
}

function getAIPostRequestRef(
  circleId: string,
  requestId: string
): FirebaseFirestore.DocumentReference {
  return db.collection("circles").doc(circleId).collection("aiPostRequests").doc(requestId);
}

async function beginAIPostRequest(
  circleId: string,
  requestId: string
): Promise<AIPostRequestBeginResult> {
  const requestRef = getAIPostRequestRef(circleId, requestId);
  const postRef = db.collection("posts").doc(requestId);
  const now = Timestamp.now();

  return db.runTransaction(async (transaction): Promise<AIPostRequestBeginResult> => {
    const [requestSnap, postSnap] = await Promise.all([
      transaction.get(requestRef),
      transaction.get(postRef),
    ]);

    if (requestSnap.exists) {
      const requestData = requestSnap.data() || {};
      const status = typeof requestData.status === "string" ? requestData.status : "";
      const storedPostId = typeof requestData.postId === "string" ? requestData.postId : "";
      const updatedAt = requestData.updatedAt instanceof Timestamp ?
        requestData.updatedAt.toMillis() :
        0;

      if (status === "succeeded" && storedPostId) {
        return { kind: "succeeded", postId: storedPostId };
      }

      if (status === "processing" && now.toMillis() - updatedAt < AI_POST_REQUEST_STALE_MS && !postSnap.exists) {
        throw new Error(`AI post request is still processing: ${requestId}`);
      }
    }

    transaction.set(requestRef, {
      status: "processing",
      updatedAt: now,
      createdAt: requestSnap.exists ? requestSnap.data()?.createdAt ?? now : now,
      postId: FieldValue.delete(),
    }, { merge: true });

    if (postSnap.exists) {
      return { kind: "continue", ref: requestRef };
    }

    return { kind: "continue", ref: requestRef };
  });
}

async function finalizeAIPostRequest(params: {
  circleId: string;
  requestRef: FirebaseFirestore.DocumentReference;
  postId: string;
}): Promise<"finalized" | "already-finalized"> {
  const circleRef = db.collection("circles").doc(params.circleId);
  return db.runTransaction(async (transaction) => {
    const requestSnap = await transaction.get(params.requestRef);
    const requestData = requestSnap.data() || {};
    const status = typeof requestData.status === "string" ? requestData.status : "";

    if (status === "succeeded") {
      return "already-finalized";
    }

    transaction.update(circleRef, {
      postCount: FieldValue.increment(1),
      recentActivity: FieldValue.serverTimestamp(),
    });
    transaction.set(params.requestRef, {
      status: "succeeded",
      postId: params.postId,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return "finalized";
  });
}

function buildAIPostRequestId(params: {
  circleId: string;
  aiId: string;
  requestAt: Date;
}): string {
  return `circle-ai-${params.circleId}-${params.aiId}-${params.requestAt.getTime()}`;
}

async function loadCircleAIPostTargets(params: {
  limit: number;
  dueOnly: boolean;
}): Promise<CircleAITarget[]> {
  let query: FirebaseFirestore.Query = db.collection("circles")
    .where("isDeleted", "==", false)
    .where("aiPostingEnabled", "==", true);

  if (params.dueOnly) {
    query = query.where("nextCircleAIPostAt", "<=", Timestamp.fromDate(new Date()));
  }

  query = query
    .orderBy("nextCircleAIPostAt", "asc")
    .limit(params.limit);

  const snapshot = await query.get();
  const targets: CircleAITarget[] = [];

  for (const doc of snapshot.docs) {
    const target = toCircleAITarget(doc);
    if (target) {
      targets.push(target);
      continue;
    }

    await doc.ref.update({
      aiPostingEnabled: false,
      generatedAICount: 0,
      nextCircleAIPostAt: null,
    }).catch((error) => {
      console.warn(`Failed to disable invalid AI posting circle ${doc.id}:`, error);
    });
  }

  return targets;
}

async function rescheduleCircleAIPost(circleId: string, nextAt: Date): Promise<void> {
  await db.collection("circles").doc(circleId).update({
    nextCircleAIPostAt: Timestamp.fromDate(nextAt),
  });
}

async function hasAIPostCapacityToday(
  circleId: string,
  todayTimestamp: FirebaseFirestore.Timestamp
): Promise<boolean> {
  const todayPosts = await db.collection("posts")
    .where("circleId", "==", circleId)
    .where("createdAt", ">=", todayTimestamp)
    .limit(2)
    .get();
  return todayPosts.size < 2;
}

async function getRecentCirclePosts(circleId: string): Promise<string[]> {
  const recentPostsSnapshot = await db.collection("posts")
    .where("circleId", "==", circleId)
    .orderBy("createdAt", "desc")
    .limit(5)
    .get();

  return recentPostsSnapshot.docs
    .map((doc) => doc.data().content as string)
    .filter(Boolean);
}

function sanitizeGeneratedPost(text: string): string {
  const trimmed = text.trim();
  if (!trimmed) return "";
  return trimmed.replace(/#[^\s#]+/g, "").trim();
}

async function createCircleAIPost(params: {
  target: CircleAITarget;
  ai: GeneratedAI;
  aiFactory: ReturnType<typeof createAIProviderFactory>;
  requestId: string;
}): Promise<"posted" | "skipped-empty" | "already-posted"> {
  const beginResult = await beginAIPostRequest(params.target.circleId, params.requestId);
  if (beginResult.kind === "succeeded") {
    return "already-posted";
  }

  const postRef = db.collection("posts").doc(params.requestId);
  const existingPost = await postRef.get();
  if (existingPost.exists) {
    await finalizeAIPostRequest({
      circleId: params.target.circleId,
      requestRef: beginResult.ref,
      postId: postRef.id,
    });
    return "already-posted";
  }

  const recentPostContents = await getRecentCirclePosts(params.target.circleId);

  const prompt = getCircleAIPostPrompt(
    params.ai.name,
    params.target.circleName,
    params.target.circleDescription,
    params.target.circleCategory,
    params.target.circleRules,
    params.target.circleGoal,
    recentPostContents
  );
  const result = await params.aiFactory.generateText(prompt);
  const postContent = sanitizeGeneratedPost(result.text);

  if (!postContent) {
    await beginResult.ref.delete().catch(() => undefined);
    return "skipped-empty";
  }

  await postRef.set({
    userId: params.ai.id,
    userDisplayName: params.ai.name,
    userAvatarIndex: params.ai.avatarIndex,
    content: postContent,
    postMode: "mix",
    circleId: params.target.circleId,
    isVisible: true,
    reactions: {},
    commentCount: 0,
    aiRequestId: params.requestId,
    createdAt: FieldValue.serverTimestamp(),
  });

  await finalizeAIPostRequest({
    circleId: params.target.circleId,
    requestRef: beginResult.ref,
    postId: postRef.id,
  });

  return "posted";
}

function pickRandomAI(generatedAIs: GeneratedAI[]): GeneratedAI {
  return generatedAIs[Math.floor(Math.random() * generatedAIs.length)];
}

function buildTaskPayload(target: CircleAITarget, ai: GeneratedAI) {
  const requestId = buildAIPostRequestId({
    circleId: target.circleId,
    aiId: ai.id,
    requestAt: target.nextCircleAIPostAt || new Date(),
  });
  return {
    circleId: target.circleId,
    aiId: ai.id,
    aiName: ai.name,
    aiAvatarIndex: ai.avatarIndex,
    requestId,
  };
}

async function loadTargetCircleForExecution(circleId: string): Promise<CircleAITarget | null> {
  const circleDoc = await db.collection("circles").doc(circleId).get();
  if (!circleDoc.exists || circleDoc.data()?.isDeleted === true) {
    return null;
  }
  const data = circleDoc.data();
  const generatedAIs = normalizeGeneratedAIs(data?.generatedAIs);
  if (generatedAIs.length === 0) {
    return null;
  }

  return {
    circleId,
    circleName: data?.name || "サークル",
    circleDescription: data?.description || "",
    circleCategory: data?.category || "その他",
    circleRules: data?.rules || "",
    circleGoal: data?.goal || "",
    generatedAIs,
    nextCircleAIPostAt: data?.nextCircleAIPostAt?.toDate?.() || null,
  };
}

export const generateCircleAIPosts = functionsV1.region(LOCATION).runWith({
  secrets: ["GEMINI_API_KEY", "OPENAI_API_KEY"],
  timeoutSeconds: 120,
  memory: "256MB",
}).pubsub.schedule("0 9,20 * * *").timeZone("Asia/Tokyo").onRun(async () => {
  console.log("=== generateCircleAIPosts START ===");

  try {
    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    const queue = "generate-circle-ai-posts";
    const location = LOCATION;
    const now = new Date();
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayTimestamp = Timestamp.fromDate(today);

    const targets = await loadCircleAIPostTargets({
      limit: MAX_CIRCLES_PER_RUN * 4,
      dueOnly: true,
    });

    let scheduledCount = 0;
    let duplicateSkippedCount = 0;
    for (const target of targets) {
      if (scheduledCount >= MAX_CIRCLES_PER_RUN) break;

      if (!await hasAIPostCapacityToday(target.circleId, todayTimestamp)) {
        await rescheduleCircleAIPost(target.circleId, computeNextCircleAIPostAt(now));
        continue;
      }

      const randomAI = pickRandomAI(target.generatedAIs);
      const delayMinutes = Math.floor(Math.random() * 180);
      const scheduleTime = new Date(Date.now() + delayMinutes * 60 * 1000);
      const nextScheduledAt = computeNextCircleAIPostAt(scheduleTime);
      const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeCircleAIPost`;

      try {
        await rescheduleCircleAIPost(target.circleId, nextScheduledAt);
        const taskPayload = buildTaskPayload(target, randomAI);
        const enqueueResult = await scheduleHttpTask({
          queue,
          url: targetUrl,
          payload: taskPayload,
          scheduleTime,
          projectId: project,
          location,
          taskId: `circle-ai-post-${target.circleId}`,
        });

        if (enqueueResult.result === "duplicate_skipped") {
          duplicateSkippedCount++;
        }
        scheduledCount++;
      } catch (error) {
        await rescheduleCircleAIPost(
          target.circleId,
          computeCircleAIPostRetryAt(now)
        ).catch(() => undefined);
        console.error(`Error scheduling task for circle ${target.circleId}:`, error);
      }
    }

    console.log(
      `=== generateCircleAIPosts COMPLETE: scheduled=${scheduledCount}, ` +
      `duplicateSkipped=${duplicateSkippedCount} ===`
    );
  } catch (error) {
    console.error("=== generateCircleAIPosts ERROR:", error);
  }
});

export const executeCircleAIPost = functionsV1.region(LOCATION).runWith({
  secrets: ["GEMINI_API_KEY", "OPENAI_API_KEY"],
  timeoutSeconds: 60,
}).https.onRequest(async (request, response) => {
  const { verifyCloudTasksRequest } = await import("../helpers/cloud-tasks-auth");
  if (!await verifyCloudTasksRequest(request, "executeCircleAIPost")) {
    response.status(403).send("Unauthorized");
    return;
  }

  const retryCircleId = typeof request.body?.circleId === "string" ?
    request.body.circleId :
    null;

  try {
    const {
      circleId,
      aiId,
      aiName,
      aiAvatarIndex,
      requestId,
    } = request.body;

    const target = await loadTargetCircleForExecution(circleId);
    if (!target) {
      response.status(200).send("Circle deleted, skipping");
      return;
    }

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayTimestamp = Timestamp.fromDate(today);
    if (!await hasAIPostCapacityToday(circleId, todayTimestamp)) {
      response.status(200).send("Circle reached daily limit");
      return;
    }

    const aiFactory = createAIProviderFactory();
    const outcome = await createCircleAIPost({
      target,
      ai: { id: aiId, name: aiName, avatarIndex: aiAvatarIndex },
      aiFactory,
      requestId,
    });

    if (outcome === "skipped-empty") {
      response.status(200).send("Empty post, skipping");
      return;
    }

    if (outcome === "already-posted") {
      response.status(200).send("Post already created");
      return;
    }

    response.status(200).send("Post created");
  } catch (error) {
    if (retryCircleId) {
      await rescheduleCircleAIPost(
        retryCircleId,
        computeCircleAIPostRetryAt(new Date())
      ).catch((rescheduleError) => {
        console.error(`Failed to reschedule AI post retry for ${retryCircleId}:`, rescheduleError);
      });
    }
    console.error("executeCircleAIPost ERROR:", error);
    response.status(500).send(`Error: ${error}`);
  }
});

export const triggerCircleAIPosts = onCall(
  { region: LOCATION, secrets: [geminiApiKey, openaiApiKey], timeoutSeconds: 300, enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", AUTH_ERRORS.UNAUTHENTICATED);
    }
    const userIsAdmin = await isAdmin(request.auth.uid);
    if (!userIsAdmin) {
      throw new HttpsError("permission-denied", AUTH_ERRORS.ADMIN_REQUIRED);
    }

    const geminiKey = geminiApiKey.value() || "";
    const openaiKey = openaiApiKey.value() || "";
    if (!geminiKey && !openaiKey) {
      console.error("ERROR: No AI API key available (both GEMINI and OPENAI are empty)");
      throw new HttpsError("internal", SYSTEM_ERRORS.INTERNAL);
    }

    const aiFactory = createAIProviderFactory();
    const now = new Date();
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayTimestamp = Timestamp.fromDate(today);

    try {
      const targets = await loadCircleAIPostTargets({
        limit: MAX_CIRCLES_PER_RUN * 4,
        dueOnly: false,
      });

      let totalPosts = 0;
      for (const target of targets) {
        if (totalPosts >= MAX_CIRCLES_PER_RUN) break;

        if (!await hasAIPostCapacityToday(target.circleId, todayTimestamp)) {
          await rescheduleCircleAIPost(target.circleId, computeNextCircleAIPostAt(now));
          continue;
        }

        const randomAI = pickRandomAI(target.generatedAIs);
        const nextScheduledAt = computeNextCircleAIPostAt(now);
        const requestId = buildAIPostRequestId({
          circleId: target.circleId,
          aiId: randomAI.id,
          requestAt: nextScheduledAt,
        });

        try {
          await rescheduleCircleAIPost(target.circleId, nextScheduledAt);
          const outcome = await createCircleAIPost({
            target,
            ai: randomAI,
            aiFactory,
            requestId,
          });

          if (outcome === "posted" || outcome === "already-posted") {
            totalPosts++;
          }

          await new Promise((resolve) => setTimeout(resolve, 500));
        } catch (error) {
          await rescheduleCircleAIPost(target.circleId, computeCircleAIPostRetryAt(now))
            .catch(() => undefined);
          console.error(`Error generating post for circle ${target.circleId}:`, error);
        }
      }

      return {
        success: true,
        message: `サークルAI投稿を${totalPosts}件作成しました（最大${MAX_CIRCLES_PER_RUN}件処理）`,
        totalPosts,
      };
    } catch (error) {
      console.error("triggerCircleAIPosts ERROR:", error);
      return { success: false, message: `エラー: ${error}` };
    }
  }
);
