/**
 * サークルAI投稿機能
 * - generateCircleAIPosts: 定期実行（Cloud Scheduler）
 * - executeCircleAIPost: Cloud Tasksワーカー
 * - triggerCircleAIPosts: 手動トリガー（管理者用）
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as functionsV1 from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { CloudTasksClient } from "@google-cloud/tasks";
import { GoogleGenerativeAI } from "@google/generative-ai";
import { db, FieldValue } from "../helpers/firebase";
import { isAdmin } from "../helpers/admin";
import { PROJECT_ID, LOCATION, AI_MODELS } from "../config/constants";
import { geminiApiKey } from "../config/secrets";

// テスト用：本番は100
const MAX_CIRCLES_PER_RUN = 3;

/**
 * サークルAIの投稿を生成するシステムプロンプト
 */
function getCircleAIPostPrompt(
  aiName: string,
  circleName: string,
  circleDescription: string,
  category: string,
  circleRules: string,
  circleGoal: string,
  recentPosts: string[] = [] // 過去の投稿内容（重複回避用）
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

/**
 * サークルAI投稿を定期実行（Cloud Scheduler用）
 * 毎日朝9時と夜20時に実行を想定
 *
 * 最適化版（2025-12-26）:
 * - 全サークル走査ではなくランダムに最大100件選択
 * - 前日に投稿したサークルは除外
 * - コスト削減のため処理数を制限
 */
export const generateCircleAIPosts = functionsV1.region(LOCATION).runWith({
  secrets: ["GEMINI_API_KEY"],
  timeoutSeconds: 120,
  memory: "256MB",
}).pubsub.schedule("0 9,20 * * *").timeZone("Asia/Tokyo").onRun(async () => {
  console.log("=== generateCircleAIPosts START (Scheduler - Optimized) ===");

  try {
    const tasksClient = new CloudTasksClient();
    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    const queue = "generate-circle-ai-posts";
    const location = LOCATION;

    // 昨日の日付を取得（除外用）
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayStr = yesterday.toISOString().split("T")[0]; // "YYYY-MM-DD"

    // 昨日投稿したサークルIDリストを取得
    const historyDoc = await db.collection("circleAIPostHistory").doc(yesterdayStr).get();
    const excludedCircleIds: string[] = historyDoc.exists ? (historyDoc.data()?.circleIds || []) : [];
    console.log(`Excluding ${excludedCircleIds.length} circles from yesterday`);

    // 全サークルを取得（isDeletedフィールドがないサークルも含める）
    const circlesSnapshot = await db.collection("circles").get();

    // AIがいて、削除されていないサークルのみフィルタリング
    const eligibleCircles = circlesSnapshot.docs.filter(doc => {
      const data = doc.data();
      // isDeletedがtrue（明示的に削除済み）の場合は除外
      // isDeletedがfalseまたは未設定の場合は対象
      if (data.isDeleted === true) return false;
      const generatedAIs = data.generatedAIs as Array<{ id: string; name: string; avatarIndex: number }> || [];
      // AIがいない、または昨日投稿済みのサークルは除外
      return generatedAIs.length > 0 && !excludedCircleIds.includes(doc.id);
    });

    console.log(`Eligible circles: ${eligibleCircles.length} (after exclusion)`);

    // ランダムに最大100件選択
    const shuffled = eligibleCircles.sort(() => Math.random() - 0.5);
    const selectedCircles = shuffled.slice(0, MAX_CIRCLES_PER_RUN);

    console.log(`Selected ${selectedCircles.length} circles for processing`);

    let scheduledCount = 0;
    const postedCircleIds: string[] = [];

    // 今日の日付
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayTimestamp = admin.firestore.Timestamp.fromDate(today);
    const todayStr = new Date().toISOString().split("T")[0];

    for (const circleDoc of selectedCircles) {
      const circleData = circleDoc.data();
      const circleId = circleDoc.id;

      const generatedAIs = circleData.generatedAIs as Array<{
        id: string;
        name: string;
        avatarIndex: number;
      }>;

      // すでに今日投稿があるかチェック
      const todayPosts = await db.collection("posts")
        .where("circleId", "==", circleId)
        .where("createdAt", ">=", todayTimestamp)
        .get();

      // 今日すでに2件以上投稿があればスキップ
      if (todayPosts.size >= 2) {
        console.log(`Circle ${circleId} already has ${todayPosts.size} posts today, skipping`);
        continue;
      }

      // ランダムにAIを1体選択
      const randomAI = generatedAIs[Math.floor(Math.random() * generatedAIs.length)];

      // 0〜3時間後のランダムな時間にスケジュール（分単位で分散）
      const delayMinutes = Math.floor(Math.random() * 180); // 0〜180分（3時間）
      const scheduleTime = new Date(Date.now() + delayMinutes * 60 * 1000);

      // Cloud Tasksにタスクを登録
      const queuePath = tasksClient.queuePath(project, location, queue);
      const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeCircleAIPost`;
      // OIDCトークン生成用のサービスアカウント（cloud-tasks-saを使用）
      const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

      const payload = {
        circleId,
        circleName: circleData.name,
        circleDescription: circleData.description || "",
        circleCategory: circleData.category || "その他",
        circleRules: circleData.rules || "",
        circleGoal: circleData.goal || "",
        aiId: randomAI.id,
        aiName: randomAI.name,
        aiAvatarIndex: randomAI.avatarIndex,
      };

      const task = {
        httpRequest: {
          httpMethod: "POST" as const,
          url: targetUrl,
          body: Buffer.from(JSON.stringify(payload)).toString("base64"),
          headers: { "Content-Type": "application/json" },
          oidcToken: { serviceAccountEmail },
        },
        scheduleTime: { seconds: Math.floor(scheduleTime.getTime() / 1000) },
      };

      try {
        await tasksClient.createTask({ parent: queuePath, task });
        console.log(`Scheduled post for ${circleData.name} at ${scheduleTime.toISOString()} (delay: ${delayMinutes}min)`);
        scheduledCount++;
        postedCircleIds.push(circleId);
      } catch (error) {
        console.error(`Error scheduling task for circle ${circleId}:`, error);
      }
    }

    // 今日の投稿履歴を保存（明日の除外用）
    if (postedCircleIds.length > 0) {
      const historyRef = db.collection("circleAIPostHistory").doc(todayStr);
      const existingHistory = await historyRef.get();
      const existingIds: string[] = existingHistory.exists ? (existingHistory.data()?.circleIds || []) : [];
      const mergedIds = [...new Set([...existingIds, ...postedCircleIds])];

      await historyRef.set({
        date: todayStr,
        circleIds: mergedIds,
        updatedAt: FieldValue.serverTimestamp(),
      });
      console.log(`Saved ${mergedIds.length} circle IDs to history for ${todayStr}`);
    }

    console.log(`=== generateCircleAIPosts COMPLETE: Scheduled ${scheduledCount} posts ===`);

  } catch (error) {
    console.error("=== generateCircleAIPosts ERROR:", error);
  }
});


/**
 * サークルAI投稿を実行するワーカー（Cloud Tasksから呼び出し）
 */
export const executeCircleAIPost = functionsV1.region(LOCATION).runWith({
  secrets: ["GEMINI_API_KEY"],
  timeoutSeconds: 60,
}).https.onRequest(async (request, response) => {
  // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
  const { verifyCloudTasksRequest } = await import("../helpers/cloud-tasks-auth");
  if (!await verifyCloudTasksRequest(request, "executeCircleAIPost")) {
    response.status(403).send("Unauthorized");
    return;
  }

  try {
    const {
      circleId,
      circleName,
      circleDescription,
      circleCategory,
      circleRules,
      circleGoal,
      aiId,
      aiName,
      aiAvatarIndex,
    } = request.body;

    console.log(`Executing AI post for circle ${circleName} by ${aiName}`);

    // サークルが削除されていないか確認
    const circleDoc = await db.collection("circles").doc(circleId).get();
    if (!circleDoc.exists || circleDoc.data()?.isDeleted) {
      console.log(`Circle ${circleId} is deleted or not found, skipping AI post`);
      response.status(200).send("Circle deleted, skipping");
      return;
    }

    // 過去の投稿を取得（重複回避用）
    const recentPostsSnapshot = await db.collection("posts")
      .where("circleId", "==", circleId)
      .orderBy("createdAt", "desc")
      .limit(5)
      .get();

    const recentPostContents = recentPostsSnapshot.docs.map(doc => doc.data().content as string).filter(Boolean);
    console.log(`Found ${recentPostContents.length} recent posts for deduplication`);

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      throw new Error("GEMINI_API_KEY is not set");
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: AI_MODELS.GEMINI_DEFAULT });

    // Geminiで投稿内容を生成（過去投稿を渡して重複回避）
    const prompt = getCircleAIPostPrompt(aiName, circleName, circleDescription, circleCategory, circleRules, circleGoal, recentPostContents);
    const result = await model.generateContent(prompt);
    let postContent = result.response.text()?.trim();

    // ハッシュタグが含まれていたら削除
    if (postContent) {
      postContent = postContent.replace(/#[^\s#]+/g, "").trim();
    }

    if (!postContent) {
      console.log(`Empty post generated for circle ${circleId}`);
      response.status(200).send("Empty post, skipping");
      return;
    }

    // 投稿を作成
    const postRef = db.collection("posts").doc();
    await postRef.set({
      userId: aiId,
      userDisplayName: aiName,
      userAvatarIndex: aiAvatarIndex,
      content: postContent,
      postMode: "mix",
      circleId: circleId,
      isVisible: true,
      reactions: {},
      commentCount: 0,
      createdAt: FieldValue.serverTimestamp(),
    });

    // サークルの投稿数を更新
    await db.collection("circles").doc(circleId).update({
      postCount: admin.firestore.FieldValue.increment(1),
      recentActivity: FieldValue.serverTimestamp(),
    });

    console.log(`Created AI post in circle ${circleName}: ${postContent.substring(0, 50)}...`);
    response.status(200).send("Post created");

  } catch (error) {
    console.error("executeCircleAIPost ERROR:", error);
    response.status(500).send(`Error: ${error}`);
  }
});

/**
 * サークルAI投稿を手動トリガー（テスト用）
 * 最適化版：generateCircleAIPostsと同じロジックを使用
 */
export const triggerCircleAIPosts = onCall(
  { region: LOCATION, secrets: [geminiApiKey], timeoutSeconds: 300 },
  async (request) => {
    // セキュリティ: 管理者権限チェック
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const userIsAdmin = await isAdmin(request.auth.uid);
    if (!userIsAdmin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    console.log("=== triggerCircleAIPosts (manual - optimized) START ===");

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      return { success: false, message: "GEMINI_API_KEY is not set" };
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: AI_MODELS.GEMINI_DEFAULT });

    let totalPosts = 0;
    const postedCircleIds: string[] = [];

    try {
      // 昨日の日付を取得（除外用）
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      const yesterdayStr = yesterday.toISOString().split("T")[0];

      // 昨日投稿したサークルIDリストを取得
      const historyDoc = await db.collection("circleAIPostHistory").doc(yesterdayStr).get();
      const excludedCircleIds: string[] = historyDoc.exists ? (historyDoc.data()?.circleIds || []) : [];
      console.log(`Excluding ${excludedCircleIds.length} circles from yesterday`);

      // 全サークルを取得（isDeletedフィールドがないサークルも含める）
      const circlesSnapshot = await db.collection("circles").get();

      // AIがいて、削除されていないサークルのみフィルタリング
      const eligibleCircles = circlesSnapshot.docs.filter(doc => {
        const data = doc.data();
        // isDeletedがtrue（明示的に削除済み）の場合は除外
        if (data.isDeleted === true) return false;
        const generatedAIs = data.generatedAIs as Array<{ id: string; name: string; avatarIndex: number }> || [];
        return generatedAIs.length > 0 && !excludedCircleIds.includes(doc.id);
      });

      console.log(`Eligible circles: ${eligibleCircles.length} (after exclusion)`);

      // ランダムに最大MAX_CIRCLES_PER_RUN件選択
      const shuffled = eligibleCircles.sort(() => Math.random() - 0.5);
      const selectedCircles = shuffled.slice(0, MAX_CIRCLES_PER_RUN);

      console.log(`Selected ${selectedCircles.length} circles for processing`);

      // 今日の日付
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const todayTimestamp = admin.firestore.Timestamp.fromDate(today);
      const todayStr = new Date().toISOString().split("T")[0];

      for (const circleDoc of selectedCircles) {
        const circleData = circleDoc.data();
        const circleId = circleDoc.id;

        const generatedAIs = circleData.generatedAIs as Array<{
          id: string;
          name: string;
          avatarIndex: number;
        }>;

        // すでに今日投稿があるかチェック
        const todayPosts = await db.collection("posts")
          .where("circleId", "==", circleId)
          .where("createdAt", ">=", todayTimestamp)
          .get();

        if (todayPosts.size >= 2) {
          console.log(`Circle ${circleId} already has ${todayPosts.size} posts today, skipping`);
          continue;
        }

        const randomAI = generatedAIs[Math.floor(Math.random() * generatedAIs.length)];

        // 過去の投稿を取得（重複回避用）
        const recentPostsSnapshot = await db.collection("posts")
          .where("circleId", "==", circleId)
          .orderBy("createdAt", "desc")
          .limit(5)
          .get();
        const recentPostContents = recentPostsSnapshot.docs.map(doc => doc.data().content as string).filter(Boolean);

        const prompt = getCircleAIPostPrompt(
          randomAI.name,
          circleData.name,
          circleData.description || "",
          circleData.category || "その他",
          circleData.rules || "",
          circleData.goal || "",
          recentPostContents
        );

        try {
          const result = await model.generateContent(prompt);
          let postContent = result.response.text()?.trim();

          if (postContent) {
            postContent = postContent.replace(/#[^\s#]+/g, "").trim();
          }

          if (!postContent) continue;

          const postRef = db.collection("posts").doc();
          await postRef.set({
            userId: randomAI.id,
            userDisplayName: randomAI.name,
            userAvatarIndex: randomAI.avatarIndex,
            content: postContent,
            postMode: "mix",
            circleId: circleId,
            isVisible: true,
            reactions: {},
            commentCount: 0,
            createdAt: FieldValue.serverTimestamp(),
          });

          await db.collection("circles").doc(circleId).update({
            postCount: admin.firestore.FieldValue.increment(1),
            recentActivity: FieldValue.serverTimestamp(),
          });

          totalPosts++;
          postedCircleIds.push(circleId);
          await new Promise((resolve) => setTimeout(resolve, 500));

        } catch (error) {
          console.error(`Error generating post for circle ${circleId}:`, error);
        }
      }

      // 今日の投稿履歴を保存（明日の除外用）
      if (postedCircleIds.length > 0) {
        const historyRef = db.collection("circleAIPostHistory").doc(todayStr);
        const existingHistory = await historyRef.get();
        const existingIds: string[] = existingHistory.exists ? (existingHistory.data()?.circleIds || []) : [];
        const mergedIds = [...new Set([...existingIds, ...postedCircleIds])];

        await historyRef.set({
          date: todayStr,
          circleIds: mergedIds,
          updatedAt: FieldValue.serverTimestamp(),
        });
        console.log(`Saved ${mergedIds.length} circle IDs to history for ${todayStr}`);
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
