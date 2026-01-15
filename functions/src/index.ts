import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as functionsV1 from "firebase-functions/v1";
import { onCall, HttpsError } from "firebase-functions/v2/https";
// onSchedule は scheduled/*.ts に移動済み
import { setGlobalOptions } from "firebase-functions/v2"; // Global Options

import * as admin from "firebase-admin";
import { GoogleGenerativeAI, Part } from "@google/generative-ai";


import { CloudTasksClient } from "@google-cloud/tasks";
// google (googleapis) は helpers/spreadsheet.ts に移動済み

import { AIProviderFactory } from "./ai/provider";
import { PROJECT_ID, LOCATION, AI_MODELS } from "./config/constants";
import { geminiApiKey, openaiApiKey } from "./config/secrets";
// isAdmin は callable/admin.ts で使用
// deleteStorageFileFromUrl は scheduled/cleanup.ts で使用
// appendInquiryToSpreadsheet は callable/inquiries.ts で使用
import { VIRTUE_CONFIG } from "./helpers/virtue";
// sendPushOnly は triggers/*.ts で使用
import { ModerationResult, MediaModerationResult } from "./types";
import {
  Gender,
  AgeGroup,
  PERSONALITIES,
  PRAISE_STYLES,
  AI_PERSONAS,
  getSystemPrompt,
  getCircleSystemPrompt,
} from "./ai/personas";
import {
  getTextModerationPrompt,
  IMAGE_MODERATION_CALLABLE_PROMPT,
} from "./ai/prompts/moderation";
import { getPostGenerationPrompt } from "./ai/prompts/post-generation";


// 分離されたモジュールの再エクスポート
export { initializeNameParts, getNameParts, updateUserName } from "./callable/names";
export { reportContent } from "./callable/reports";
export { createTask, getTasks } from "./callable/tasks";
export {
  createInquiry,
  sendInquiryMessage,
  sendInquiryReply,
  updateInquiryStatus,
} from "./callable/inquiries";

// Phase 4: サークル関連
export {
  deleteCircle,
  cleanupDeletedCircle,
  approveJoinRequest,
  rejectJoinRequest,
  sendJoinRequest,
} from "./callable/circles";
export { onCircleCreated, onCircleUpdated } from "./triggers/circles";
export {
  generateCircleAIPosts,
  executeCircleAIPost,
  triggerCircleAIPosts,
} from "./circle-ai/posts";
export {
  checkGhostCircles,
  evolveCircleAIs,
  triggerEvolveCircleAIs,
} from "./scheduled/circles";

// Phase 5: 投稿コメントリアクション関連
export { onPostCreated } from "./triggers/posts";
export { createPostWithRateLimit, createPostWithModeration } from "./callable/posts";
export { initializeAIAccounts, generateAIPosts } from "./callable/ai";
export { scheduleAIPosts } from "./scheduled/ai-posts";

// Phase 6: ユーザー通知関連
export { followUser, unfollowUser, getFollowStatus, getVirtueHistory, getVirtueStatus } from "./callable/users";
export { onCommentCreatedNotify, onReactionAddedNotify } from "./triggers/notifications";
export { onTaskUpdated } from "./triggers/tasks";

// Phase 7: スケジュール・管理者
export { cleanupOrphanedMedia, cleanupResolvedInquiries, cleanupReports, cleanupBannedUsers } from "./scheduled/cleanup";
export { cleanUpUserFollows, deleteAllAIUsers, cleanupOrphanedCircleAIs, setAdminRole, removeAdminRole, banUser, permanentBanUser, unbanUser } from "./callable/admin";

admin.initializeApp();
const db = admin.firestore();

// Set global options for v2 functions
setGlobalOptions({ region: LOCATION });

// ===============================================
// ヘルパー関数
// ===============================================

/**
 * AIProviderFactoryを作成するヘルパー関数
 * 関数内でSecretにアクセスし、ファクトリーを返す
 */
function createAIProviderFactory(): AIProviderFactory {
  const geminiKey = geminiApiKey.value() || "";
  const openaiKey = openaiApiKey.value() || "";
  return new AIProviderFactory(geminiKey, openaiKey);
}

// VIRTUE_CONFIG, sendPushOnly は helpers/virtue.ts, helpers/notification.ts に移動済み


// Google Sheets ヘルパー: helpers/spreadsheet.ts に移動


// メディアモデレーション・投稿関連は Phase 5 モジュールに移動済み

// AIの投稿テンプレート（職業・性格に応じた内容を動的に生成するための基本パターン）
// executeAIPostGeneration で使用
const POST_TEMPLATES_BY_OCCUPATION: Record<string, string[]> = {
  college_student: [
    "今日のレポート、なんとか終わった！期限ギリギリだったけど頑張った",
    "サークルの活動楽しかった！いい仲間がいるって幸せだな",
    "テスト勉強中...集中力が切れてきたけどもうひと踏ん張り！",
    "新しいカフェ発見した！勉強する場所増えて嬉しい",
    "バイト終わり！今日も忙しかったけど達成感ある",
  ],
  sales: [
    "今月の目標達成！チームのみんなのおかげ！",
    "新しいお客様と良い関係を築けた気がする",
    "プレゼン資料作り終わった...明日の商談頑張る",
    "先輩からのアドバイスで気づきがあった",
    "今日は契約取れた！嬉しい！！",
  ],
  engineer: [
    "新機能リリースできた！ユーザーの反応楽しみ",
    "バグ直した...原因見つけるまで長かったけど達成感",
    "コードレビューで学びがあった",
    "新しい技術試してみた。面白い",
    "今日のタスク全部終わった！明日も頑張ろ",
  ],
  nurse: [
    "患者さんから「ありがとう」って言われた...元気もらえる",
    "夜勤明け！今日もみんな無事で何より",
    "新人さんのフォローしてたら自分も勉強になった",
    "忙しかったけど、チームワークで乗り越えた",
    "久しぶりの連休！ゆっくり休もう",
  ],
  designer: [
    "デザイン採用された！嬉しい！",
    "クライアントさんに喜んでもらえた",
    "新しいツール使ってみたら作業効率上がった",
    "今日のデザイン、いい感じにできた気がする",
    "展示会で刺激もらった！創作意欲湧いてきた",
  ],
  teacher: [
    "生徒たちの成長を感じた一日だった",
    "授業準備完了！明日も頑張ろう",
    "保護者さんとの面談、いい話ができた",
    "テストの採点終わった！みんな頑張ってた",
    "今日は生徒たちと楽しく過ごせた",
  ],
  freelancer: [
    "納品完了！クライアントさんに喜んでもらえた",
    "新しい案件の依頼きた！ありがたい",
    "確定申告の準備進めた。少しずつだけど進んでる",
    "オンラインミーティング上手くいった",
    "今日は作業捗った！この調子で頑張る",
  ],
  homemaker: [
    "今日の夕飯、家族に好評だった",
    "大掃除完了！スッキリ！",
    "子どもの成長を感じた一日",
    "新しいレシピに挑戦してみた",
    "午前中に用事を全部終わらせた！えらい！",
  ],
};

// フォロー徳関連は callable/users.ts に移動済み
// onTaskUpdated は triggers/tasks.ts に移動済み

// sendPushNotification, onCommentCreatedNotify, onReactionAddedNotify は helpers/notification.ts, triggers/notifications.ts に移動済み

/**
 * Cloud Tasks から呼び出される AI コメント生成関数 (v1)
 * v1を使用することでURLを固定化: https://asia-northeast1-positive-sns.cloudfunctions.net/generateAICommentV1
 */
// Imports removed as they are already in scope or invalid

export const generateAICommentV1 = functionsV1.region(LOCATION).runWith({
  secrets: ["GEMINI_API_KEY", "OPENAI_API_KEY"],
  timeoutSeconds: 60,
}).https.onRequest(async (request, response) => {
  // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
  const { verifyCloudTasksRequest } = await import("./helpers/cloud-tasks-auth");
  if (!await verifyCloudTasksRequest(request, "generateAICommentV1")) {
    response.status(403).send("Unauthorized");
    return;
  }

  try {
    const {
      postId,
      postContent,
      userDisplayName,
      personaId,
      personaName,
      personaGender,
      personaAgeGroup,
      personaOccupation,
      personaPersonality,
      personaPraiseStyle,
      personaAvatarIndex,
      mediaDescriptions,
      isCirclePost,
      circleName,
      circleDescription,
      circleGoal,
      circleRules,
    } = request.body;

    console.log(`Processing AI comment task for ${personaName} on post ${postId}`);

    // AIProviderFactory経由でテキスト生成
    const aiFactory = createAIProviderFactory();

    // ペルソナを再構築
    // まずAI_PERSONASから検索、見つからなければペイロードから構築
    let persona = AI_PERSONAS.find(p => p.id === personaId);

    if (!persona) {
      // サークルAIの場合、ペイロードからペルソナを構築
      console.log(`Persona ${personaId} not in AI_PERSONAS, using payload data`);

      // ペイロードに personality が含まれていればそれを使用
      // 含まれていなければデフォルトを使用
      const defaultPersonality = PERSONALITIES.female[0]; // 優しい系をデフォルトに

      persona = {
        id: personaId,
        name: personaName,
        namePrefixId: "",
        nameSuffixId: "",
        gender: personaGender || "female" as Gender,
        ageGroup: personaAgeGroup || "twenties" as AgeGroup,
        occupation: personaOccupation || { id: "student", name: "頑張り中", bio: "" },
        personality: personaPersonality || defaultPersonality,
        praiseStyle: personaPraiseStyle || PRAISE_STYLES[0],
        avatarIndex: personaAvatarIndex || 0,
        bio: "",
      };
    }

    // プロンプト構築
    const mediaContext = mediaDescriptions && mediaDescriptions.length > 0
      ? `\n\n【添付メディアの内容】\n${mediaDescriptions.join("\n")}`
      : "";

    // 既存のAIコメントを取得（重複回避のため）
    // 重要: コメントはトップレベルの comments コレクションに保存されている
    const postRef = db.collection("posts").doc(postId);
    let existingCommentsContext = "";
    try {
      console.log(`[DUPLICATE CHECK] Fetching existing AI comments for post: ${postId}`);

      // トップレベルのcommentsコレクションからpostIdでフィルタ
      const existingCommentsSnapshot = await db.collection("comments")
        .where("postId", "==", postId)
        .where("isAI", "==", true)
        .orderBy("createdAt", "asc")
        .limit(10)
        .get();

      console.log(`[DUPLICATE CHECK] Query returned ${existingCommentsSnapshot.size} documents`);

      if (!existingCommentsSnapshot.empty) {
        const existingComments = existingCommentsSnapshot.docs.map((doc, index) => {
          const data = doc.data();
          const commentText = `<comment_${index + 1}>${data.content}</comment_${index + 1}>`;
          console.log(`[DUPLICATE CHECK] Found: ${data.content?.substring(0, 50)}...`);
          return commentText;
        });
        existingCommentsContext = `
<existing_comments>
<instruction>以下は既に投稿されているコメントです。これらと同じフレーズ・表現は使用せず、異なる言い回しで返信してください。</instruction>
${existingComments.join("\n")}
</existing_comments>
`;
        console.log(`[DUPLICATE CHECK] Added ${existingComments.length} comments to context for diversity`);
      } else {
        console.log(`[DUPLICATE CHECK] No existing AI comments found for post ${postId}`);
      }
    } catch (error) {
      console.error("[DUPLICATE CHECK] Error fetching existing comments:", error);
      console.log("Proceeding without diversity check");
    }

    // サークル投稿かどうかでプロンプトを分岐
    let prompt: string;
    if (isCirclePost) {
      // サークル投稿: 専用プロンプトを使用
      prompt = getCircleSystemPrompt(
        persona,
        userDisplayName,
        circleName,
        circleDescription,
        postContent || "(テキストなし)",
        circleGoal,
        circleRules
      );
      // メディアコンテキストと既存コメントコンテキストを追加
      const additionalContext = existingCommentsContext + mediaContext;
      if (additionalContext) {
        // 新しいプロンプト構造では「---」の前に挿入
        prompt = prompt.replace(
          "---\n**上記の投稿に対し",
          additionalContext + "\n\n---\n**上記の投稿に対し"
        );
      }
    } else {
      // 一般投稿: 新しいプロンプト構造を使用
      const basePrompt = getSystemPrompt(persona, userDisplayName);
      const mediaNote = mediaDescriptions && mediaDescriptions.length > 0
        ? "\n\n# Additional Context (メディア情報)\n添付されたメディア（画像・動画）の内容も考慮して、具体的に褒めてください。"
        : "";

      prompt = `
${basePrompt}

# Input Data (今回の投稿)

<poster_name>${userDisplayName}</poster_name>
<post_content>
${postContent || "(テキストなし)"}
</post_content>
${mediaContext}
${existingCommentsContext}${mediaNote}

---
**上記の投稿に対し、思考プロセスや前置きを一切含めず、返信コメントのみを出力してください。**
`;
    }

    // プロンプト全文をログ出力（デバッグ用）
    console.log(`[AI PROMPT DEBUG] ===== PROMPT START =====`);
    console.log(prompt);
    console.log(`[AI PROMPT DEBUG] ===== PROMPT END =====`);

    const aiResult = await aiFactory.generateText(prompt);
    const commentText = aiResult.text?.trim();
    console.log(`AI comment generated by ${aiResult.provider}${aiResult.usedFallback ? " (fallback)" : ""}`);

    if (!commentText || commentText === "SKIP_COMMENT") {
      console.log(`Skipping comment: ${commentText || "Empty"}`);
      response.status(200).send("Comment skipped");
      return;
    }

    // リアクションもランダムで送信 (ポジティブなものから選択)
    const POSITIVE_REACTIONS = ["love", "praise", "cheer", "sparkles", "clap", "thumbsup", "smile"];
    const reactionType = POSITIVE_REACTIONS[Math.floor(Math.random() * POSITIVE_REACTIONS.length)];

    // 投稿が存在するか確認（Cloud Tasksの遅延実行中に削除された可能性）
    // postRefは既に上で宣言済み
    const postDoc = await postRef.get();
    if (!postDoc.exists) {
      console.warn(`Post ${postId} not found, skipping AI comment`);
      response.status(200).send("Post not found, skipping");
      return;
    }

    // バッチ書き込みで一括処理
    const batch = db.batch();

    // 1. コメント保存
    const commentRef = db.collection("comments").doc();
    batch.set(commentRef, {
      postId: postId,
      userId: persona.id,
      userDisplayName: persona.name,
      userAvatarIndex: persona.avatarIndex,
      isAI: true,
      content: commentText,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. リアクション保存 (通知トリガー用)
    const reactionRef = db.collection("reactions").doc();
    batch.set(reactionRef, {
      postId: postId,
      userId: persona.id,
      userDisplayName: persona.name,
      reactionType: reactionType,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 3. 投稿のリアクションカウント・コメント数を更新
    batch.update(postRef, {
      [`reactions.${reactionType}`]: admin.firestore.FieldValue.increment(1),
      commentCount: admin.firestore.FieldValue.increment(1),
    });

    await batch.commit();

    console.log(`AI comment and reaction posted: ${persona.name} (Reaction: ${reactionType})`);
    response.status(200).send("Comment and reaction posted successfully");

  } catch (error) {
    console.error("Error in generateAIComment:", error);
    response.status(500).send("Internal Server Error");
  }
}
);

// ===============================================
// モデレーション機能 (onCall)
// ===============================================

/**
 * テキストのモデレーション判定 (Gemini)
 */
async function moderateText(text: string, postContent: string = ""): Promise<ModerationResult> {
  // 短すぎる場合はスキップ
  if (!text || text.length < 2) {
    return { isNegative: false, category: "none", confidence: 0, reason: "", suggestion: "" };
  }

  const apiKey = geminiApiKey.value();
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: AI_MODELS.GEMINI_DEFAULT });

  const prompt = getTextModerationPrompt(text, postContent);

  try {
    const result = await model.generateContent(prompt);
    const responseText = result.response.text();
    // JSONブロックを取り出す
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      console.warn("Moderation JSON parse failed", responseText);
      return { isNegative: false, category: "none", confidence: 0, reason: "", suggestion: "" };
    }
    const data = JSON.parse(jsonMatch[0]) as ModerationResult;
    return data;
  } catch (e) {
    console.error("Moderation AI Error:", e);
    // エラー時は安全側に倒してスルー（または厳しくするか要検討）
    return { isNegative: false, category: "none", confidence: 0, reason: "", suggestion: "" };
  }
}

/**
 * 徳ポイントの更新（減少処理）
 */
async function penalizeUser(userId: string, penalty: number, reason: string) {
  const userRef = db.collection("users").doc(userId);

  await db.runTransaction(async (t) => {
    const doc = await t.get(userRef);
    if (!doc.exists) return;

    const currentVirtue = doc.data()?.virtue || 100;
    const newVirtue = Math.max(0, currentVirtue - penalty);

    t.update(userRef, { virtue: newVirtue });

    // 履歴追加
    const historyRef = db.collection("virtueHistory").doc();
    t.set(historyRef, {
      userId,
      change: -penalty,
      reason,
      newVirtue,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

/**
 * モデレーション付きコメント作成
 */
export const createCommentWithModeration = onCall(
  {
    region: LOCATION,
    secrets: [geminiApiKey],
  },
  async (request) => {
    // 認証チェック
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in");
    }

    const { postId, content, userDisplayName, userAvatarIndex } = request.data;
    const userId = request.auth.uid;

    if (!postId || !content) {
      throw new HttpsError("invalid-argument", "Missing postId or content");
    }

    // ユーザーがBANされているかチェック
    const userDoc = await db.collection("users").doc(userId).get();
    if (userDoc.exists && userDoc.data()?.isBanned) {
      throw new HttpsError(
        "permission-denied",
        "アカウントが制限されているため、現在この機能は使用できません。マイページ画面から運営へお問い合わせください。"
      );
    }

    // 投稿のコンテキストを取得
    let postContentText = "";
    try {
      const postDoc = await db.collection("posts").doc(postId).get();
      if (postDoc.exists) {
        postContentText = postDoc.data()?.content || "";
      }
    } catch (e) {
      console.warn(`Failed to fetch post context for moderation: ${postId}`, e);
    }

    // 1. モデレーション実行（コンテキスト付き）
    const moderation = await moderateText(content, postContentText);
    if (moderation.isNegative && moderation.confidence > 0.7) {
      // 徳ポイント減少
      await penalizeUser(userId, VIRTUE_CONFIG.lossPerNegative, `不適切な発言: ${moderation.category}`);

      throw new HttpsError(
        "invalid-argument",
        moderation.reason || "不適切な内容が含まれています",
        { suggestion: moderation.suggestion }
      );
    }

    // 2. コメント保存
    const commentRef = db.collection("comments").doc();
    await commentRef.set({
      postId,
      userId,
      userDisplayName: userDisplayName || "Unknown",
      userAvatarIndex: userAvatarIndex || 0,
      content,
      isAI: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isVisibleNow: true, // 即時表示
    });

    // 3. 投稿のコメント数を更新
    await db.collection("posts").doc(postId).update({
      commentCount: admin.firestore.FieldValue.increment(1)
    });

    return { commentId: commentRef.id };
  }
);

/**
 * ユーザーリアクション追加関数
 * 1人あたり1投稿に対して最大5回までの制限あり
 */
export const addUserReaction = onCall(
  { region: LOCATION, enforceAppCheck: false },
  async (request) => {
    const { postId, reactionType } = request.data;
    const userId = request.auth?.uid;

    if (!userId) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    if (!postId || !reactionType) {
      throw new HttpsError("invalid-argument", "postIdとreactionTypeが必要です");
    }

    const MAX_REACTIONS_PER_USER = 5;

    // 既存リアクション数をカウント
    const existingReactions = await db.collection("reactions")
      .where("postId", "==", postId)
      .where("userId", "==", userId)
      .get();

    if (existingReactions.size >= MAX_REACTIONS_PER_USER) {
      throw new HttpsError(
        "resource-exhausted",
        `1つの投稿に対するリアクションは${MAX_REACTIONS_PER_USER}回までです`
      );
    }

    // ユーザー情報を取得
    const userDoc = await db.collection("users").doc(userId).get();
    const displayName = userDoc.data()?.displayName || "ユーザー";

    const batch = db.batch();

    // 1. リアクション保存
    const reactionRef = db.collection("reactions").doc();
    batch.set(reactionRef, {
      postId: postId,
      userId: userId,
      userDisplayName: displayName,
      reactionType: reactionType,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. 投稿のリアクションカウント更新
    const postRef = db.collection("posts").doc(postId);
    batch.update(postRef, {
      [`reactions.${reactionType}`]: admin.firestore.FieldValue.increment(1),
    });

    await batch.commit();

    console.log(`User reaction added: ${displayName} -> ${reactionType} on ${postId}`);
    return {
      success: true,
      remainingReactions: MAX_REACTIONS_PER_USER - existingReactions.size - 1
    };
  }
);

/**
 * Cloud Tasks から呼び出される AI リアクション生成関数 (v1)
 * 単体リアクション用
 */
export const generateAIReactionV1 = functionsV1.region(LOCATION).https.onRequest(async (request, response) => {
  // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
  const { verifyCloudTasksRequest } = await import("./helpers/cloud-tasks-auth");
  if (!await verifyCloudTasksRequest(request, "generateAIReactionV1")) {
    response.status(403).send("Unauthorized");
    return;
  }

  try {
    const { postId, personaId, personaName, reactionType } = request.body;

    console.log(`Processing AI reaction task for ${personaName} on post ${postId} (Type: ${reactionType})`);

    const persona = AI_PERSONAS.find(p => p.id === personaId);
    if (!persona) {
      response.status(400).send("Persona not found");
      return;
    }

    // 重複チェック: この AI が既にこの投稿にリアクションしているか確認
    const existingReaction = await db.collection("reactions")
      .where("postId", "==", postId)
      .where("userId", "==", persona.id)
      .limit(1)
      .get();

    if (!existingReaction.empty) {
      console.log(`Skipping duplicate reaction: ${persona.name} already reacted to post ${postId}`);
      response.status(200).send("Reaction already exists, skipped");
      return;
    }

    const batch = db.batch();

    // 1. リアクション保存
    const reactionRef = db.collection("reactions").doc();
    batch.set(reactionRef, {
      postId: postId,
      userId: persona.id,
      userDisplayName: persona.name,
      reactionType: reactionType,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. 投稿のリアクションカウント更新
    const postRef = db.collection("posts").doc(postId);
    batch.update(postRef, {
      [`reactions.${reactionType}`]: admin.firestore.FieldValue.increment(1),
    });

    await batch.commit();

    console.log(`AI reaction posted: ${persona.name} -> ${reactionType}`);
    response.status(200).send("Reaction posted successfully");

  } catch (error) {
    console.error("Error in generateAIReaction:", error);
    response.status(500).send("Internal Server Error");
  }
});

// cleanUpUserFollows は callable/admin.ts に移動済み

// deleteAllAIUsers, cleanupOrphanedCircleAIs は callable/admin.ts に移動済み


/**
 * Cloud Tasks から呼び出される AI 投稿生成関数 (Worker)
 */
export const executeAIPostGeneration = functionsV1.region(LOCATION).runWith({
  secrets: ["GEMINI_API_KEY"],
  timeoutSeconds: 300,
  memory: "1GB",
}).https.onRequest(async (request, response) => {
  // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
  const { verifyCloudTasksRequest } = await import("./helpers/cloud-tasks-auth");
  if (!await verifyCloudTasksRequest(request, "executeAIPostGeneration")) {
    response.status(403).send("Unauthorized");
    return;
  }

  try {
    const { postId, personaId, postTimeIso } = request.body;
    console.log(`Executing AI post generation for ${personaId}`);

    const apiKey = geminiApiKey.value();
    if (!apiKey) throw new Error("GEMINI_API_KEY is not set");

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: AI_MODELS.GEMINI_DEFAULT });

    // ペルソナ取得
    const persona = AI_PERSONAS.find((p) => p.id === personaId);
    if (!persona) {
      console.error(`Persona not found: ${personaId}`);
      response.status(400).send("Persona not found");
      return;
    }

    // 職業に応じたテンプレートを取得（フォールバック用）
    const templates = POST_TEMPLATES_BY_OCCUPATION[persona.occupation.id] || [];

    // 現在時刻
    const now = new Date();
    const hours = now.getHours();

    // プロンプト生成 (努力・達成・日常の頑張りをテーマに)
    const prompt = getPostGenerationPrompt(persona, hours);

    const result = await model.generateContent(prompt);
    let content = result.response.text()?.trim();

    // 生成失敗時はテンプレートからランダム選択
    if (!content && templates.length > 0) {
      content = templates[Math.floor(Math.random() * templates.length)];
    }

    if (!content) {
      throw new Error("Failed to generate content");
    }

    // 投稿作成
    const postRef = db.collection("posts").doc(postId);
    const reactions = {
      love: Math.floor(Math.random() * 5),
      praise: Math.floor(Math.random() * 5),
      cheer: Math.floor(Math.random() * 5),
      empathy: Math.floor(Math.random() * 5),
    };

    // postTimeIsoがあればその時間、なければ現在時刻
    const createdAt = postTimeIso ? admin.firestore.Timestamp.fromDate(new Date(postTimeIso)) : admin.firestore.FieldValue.serverTimestamp();

    await postRef.set({
      userId: persona.id,
      userDisplayName: persona.name,
      userAvatarIndex: persona.avatarIndex,
      content: content,
      postMode: "mix", // 公開範囲
      circleId: null, // タイムラインのクエリ(where circleId isNull)にマッチさせるため明示的にnullを設定
      createdAt: createdAt,
      reactions: reactions,
      commentCount: 0,
      isVisible: true,
    });

    // ユーザーの統計更新
    const totalReactions = Object.values(reactions).reduce((a, b) => a + b, 0);
    await db.collection("users").doc(persona.id).update({
      totalPosts: admin.firestore.FieldValue.increment(1),
      totalPraises: admin.firestore.FieldValue.increment(totalReactions),
    });

    console.log(`Successfully created post for ${persona.name}: ${content}`);
    response.status(200).json({ success: true, postId: postRef.id });
  } catch (error) {
    console.error("Error in executeAIPostGeneration:", error);
    response.status(500).send("Internal Server Error");
  }
});

// ===============================================
// タスクリマインダー通知（イベント駆動方式）
// タスク作成/更新時にCloud Tasksにリマインダーを登録
// ===============================================

const TASK_REMINDER_QUEUE = "task-reminders";

/**
 * リマインダー時刻を計算
 */
function calculateReminderTime(
  scheduledAt: Date,
  reminder: { unit: string; value: number }
): Date {
  const ms = scheduledAt.getTime();
  if (reminder.unit === "minutes") {
    return new Date(ms - reminder.value * 60 * 1000);
  } else if (reminder.unit === "hours") {
    return new Date(ms - reminder.value * 60 * 60 * 1000);
  } else if (reminder.unit === "days") {
    return new Date(ms - reminder.value * 24 * 60 * 60 * 1000);
  }
  return new Date(ms);
}

/**
 * タスク作成/更新時にリマインダーをスケジュール
 */
export const scheduleTaskReminders = onDocumentUpdated(
  { document: "tasks/{taskId}", region: LOCATION },
  async (event) => {
    const taskId = event.params.taskId;
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();

    if (!afterData) return;

    // 完了したタスクは無視
    if (afterData.isCompleted) {
      console.log(`[Reminder] Task ${taskId} is completed, skipping`);
      return;
    }

    const scheduledAt = (afterData.scheduledAt as admin.firestore.Timestamp)?.toDate();
    if (!scheduledAt) {
      console.log(`[Reminder] Task ${taskId} has no scheduledAt`);
      return;
    }

    // スケジュールが変更されたか確認
    const beforeScheduledAt = (beforeData?.scheduledAt as admin.firestore.Timestamp)?.toDate();
    const beforeReminders = JSON.stringify(beforeData?.reminders || []);
    const afterReminders = JSON.stringify(afterData.reminders || []);

    if (
      beforeScheduledAt?.getTime() === scheduledAt.getTime() &&
      beforeReminders === afterReminders
    ) {
      console.log(`[Reminder] Task ${taskId} schedule unchanged`);
      return;
    }

    const userId = afterData.userId as string;
    const taskContent = (afterData.content as string) || "タスク";
    const reminders = afterData.reminders as Array<{ unit: string; value: number }> | undefined;

    console.log(`[Reminder] Scheduling reminders for task ${taskId}`);

    const tasksClient = new CloudTasksClient();
    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    const location = LOCATION;

    // 既存のリマインダータスクをキャンセル（sentRemindersを削除）
    const existingReminders = await db.collection("scheduledReminders")
      .where("taskId", "==", taskId)
      .get();

    const batch = db.batch();
    for (const doc of existingReminders.docs) {
      // Cloud Tasksのタスクをキャンセル
      const taskName = doc.data().cloudTaskName;
      if (taskName) {
        try {
          await tasksClient.deleteTask({ name: taskName });
          console.log(`[Reminder] Cancelled task: ${taskName}`);
        } catch (e) {
          // タスクが存在しない場合は無視
          console.log(`[Reminder] Task already gone: ${taskName}`);
        }
      }
      batch.delete(doc.ref);
    }
    await batch.commit();

    // 新しいリマインダーをスケジュール
    const queuePath = tasksClient.queuePath(project, location, TASK_REMINDER_QUEUE);
    const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeTaskReminder`;
    const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

    const now = new Date();

    // 1. 事前リマインダー
    if (reminders && reminders.length > 0) {
      for (const reminder of reminders) {
        const reminderTime = calculateReminderTime(scheduledAt, reminder);

        // 過去の時刻はスキップ
        if (reminderTime <= now) {
          console.log(`[Reminder] Skipping past reminder: ${reminderTime.toISOString()}`);
          continue;
        }

        const reminderKey = `${reminder.unit}_${reminder.value}`;
        const timeLabel = reminder.unit === "minutes"
          ? `${reminder.value}分前`
          : reminder.unit === "hours"
            ? `${reminder.value}時間前`
            : `${reminder.value}日前`;

        const payload = {
          taskId,
          userId,
          taskContent,
          timeLabel,
          reminderKey,
          type: "pre_reminder",
        };

        try {
          const [task] = await tasksClient.createTask({
            parent: queuePath,
            task: {
              httpRequest: {
                httpMethod: "POST",
                url: targetUrl,
                body: Buffer.from(JSON.stringify(payload)).toString("base64"),
                headers: { "Content-Type": "application/json" },
                oidcToken: { serviceAccountEmail },
              },
              scheduleTime: { seconds: Math.floor(reminderTime.getTime() / 1000) },
            },
          });

          // スケジュール済みとして記録
          await db.collection("scheduledReminders").add({
            taskId,
            reminderKey,
            cloudTaskName: task.name,
            scheduledFor: admin.firestore.Timestamp.fromDate(reminderTime),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          console.log(`[Reminder] Scheduled: ${taskId} - ${reminderKey} at ${reminderTime.toISOString()}`);
        } catch (error) {
          console.error(`[Reminder] Failed to schedule: ${reminderKey}`, error);
        }
      }
    }

    // 2. 予定時刻ちょうどの通知
    if (scheduledAt > now) {
      const payload = {
        taskId,
        userId,
        taskContent,
        timeLabel: "予定時刻",
        reminderKey: "on_time",
        type: "on_time",
      };

      try {
        const [task] = await tasksClient.createTask({
          parent: queuePath,
          task: {
            httpRequest: {
              httpMethod: "POST",
              url: targetUrl,
              body: Buffer.from(JSON.stringify(payload)).toString("base64"),
              headers: { "Content-Type": "application/json" },
              oidcToken: { serviceAccountEmail },
            },
            scheduleTime: { seconds: Math.floor(scheduledAt.getTime() / 1000) },
          },
        });

        await db.collection("scheduledReminders").add({
          taskId,
          reminderKey: "on_time",
          cloudTaskName: task.name,
          scheduledFor: admin.firestore.Timestamp.fromDate(scheduledAt),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`[Reminder] Scheduled on-time: ${taskId} at ${scheduledAt.toISOString()}`);
      } catch (error) {
        console.error(`[Reminder] Failed to schedule on-time`, error);
      }
    }
  }
);

/**
 * タスク作成時にリマインダーをスケジュール
 */
export const scheduleTaskRemindersOnCreate = onDocumentCreated(
  { document: "tasks/{taskId}", region: LOCATION },
  async (event) => {
    const taskId = event.params.taskId;
    const data = event.data?.data();

    if (!data) return;

    // 完了したタスクは無視
    if (data.isCompleted) return;

    const scheduledAt = (data.scheduledAt as admin.firestore.Timestamp)?.toDate();
    if (!scheduledAt) return;

    const userId = data.userId as string;
    const taskContent = (data.content as string) || "タスク";
    const reminders = data.reminders as Array<{ unit: string; value: number }> | undefined;

    console.log(`[Reminder] Scheduling reminders for new task ${taskId}`);

    const tasksClient = new CloudTasksClient();
    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    const location = LOCATION;

    const queuePath = tasksClient.queuePath(project, location, TASK_REMINDER_QUEUE);
    const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeTaskReminder`;
    const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

    const now = new Date();

    // 1. 事前リマインダー
    if (reminders && reminders.length > 0) {
      for (const reminder of reminders) {
        const reminderTime = calculateReminderTime(scheduledAt, reminder);

        if (reminderTime <= now) continue;

        const reminderKey = `${reminder.unit}_${reminder.value}`;
        const timeLabel = reminder.unit === "minutes"
          ? `${reminder.value}分前`
          : reminder.unit === "hours"
            ? `${reminder.value}時間前`
            : `${reminder.value}日前`;

        const payload = {
          taskId,
          userId,
          taskContent,
          timeLabel,
          reminderKey,
          type: "pre_reminder",
        };

        try {
          const [task] = await tasksClient.createTask({
            parent: queuePath,
            task: {
              httpRequest: {
                httpMethod: "POST",
                url: targetUrl,
                body: Buffer.from(JSON.stringify(payload)).toString("base64"),
                headers: { "Content-Type": "application/json" },
                oidcToken: { serviceAccountEmail },
              },
              scheduleTime: { seconds: Math.floor(reminderTime.getTime() / 1000) },
            },
          });

          await db.collection("scheduledReminders").add({
            taskId,
            reminderKey,
            cloudTaskName: task.name,
            scheduledFor: admin.firestore.Timestamp.fromDate(reminderTime),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          console.log(`[Reminder] Scheduled: ${taskId} - ${reminderKey}`);
        } catch (error) {
          console.error(`[Reminder] Failed to schedule: ${reminderKey}`, error);
        }
      }
    }

    // 2. 予定時刻ちょうどの通知
    if (scheduledAt > now) {
      const payload = {
        taskId,
        userId,
        taskContent,
        timeLabel: "予定時刻",
        reminderKey: "on_time",
        type: "on_time",
      };

      try {
        const [task] = await tasksClient.createTask({
          parent: queuePath,
          task: {
            httpRequest: {
              httpMethod: "POST",
              url: targetUrl,
              body: Buffer.from(JSON.stringify(payload)).toString("base64"),
              headers: { "Content-Type": "application/json" },
              oidcToken: { serviceAccountEmail },
            },
            scheduleTime: { seconds: Math.floor(scheduledAt.getTime() / 1000) },
          },
        });

        await db.collection("scheduledReminders").add({
          taskId,
          reminderKey: "on_time",
          cloudTaskName: task.name,
          scheduledFor: admin.firestore.Timestamp.fromDate(scheduledAt),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`[Reminder] Scheduled on-time: ${taskId}`);
      } catch (error) {
        console.error(`[Reminder] Failed to schedule on-time`, error);
      }
    }
  }
);

/**
 * リマインダー通知を実行するCloud Tasks用のHTTPエンドポイント
 */
export const executeTaskReminder = functionsV1.region(LOCATION).runWith({
  timeoutSeconds: 30,
}).https.onRequest(async (request, response) => {
  // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
  const { verifyCloudTasksRequest } = await import("./helpers/cloud-tasks-auth");
  if (!await verifyCloudTasksRequest(request, "executeTaskReminder")) {
    response.status(403).send("Unauthorized");
    return;
  }

  try {
    const { taskId, userId, taskContent, timeLabel, reminderKey, type } = request.body;

    console.log(`[Reminder] Executing reminder: ${taskId} - ${reminderKey}`);

    // タスクがまだ存在し、未完了か確認
    const taskDoc = await db.collection("tasks").doc(taskId).get();
    if (!taskDoc.exists) {
      console.log(`[Reminder] Task ${taskId} not found, skipping`);
      response.status(200).send("Task not found");
      return;
    }

    const taskData = taskDoc.data();
    if (taskData?.isCompleted) {
      console.log(`[Reminder] Task ${taskId} is completed, skipping`);
      response.status(200).send("Task completed");
      return;
    }

    // 送信済みかチェック
    const sentRef = db.collection("sentReminders").doc(`${taskId}_${reminderKey}`);
    const sentDoc = await sentRef.get();
    if (sentDoc.exists) {
      console.log(`[Reminder] Already sent: ${taskId} - ${reminderKey}`);
      response.status(200).send("Already sent");
      return;
    }

    // ユーザーのFCMトークンを取得
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      console.log(`[Reminder] User ${userId} not found`);
      response.status(200).send("User not found");
      return;
    }

    const fcmToken = userDoc.data()?.fcmToken;
    if (!fcmToken) {
      console.log(`[Reminder] No FCM token for user: ${userId}`);
      response.status(200).send("No FCM token");
      return;
    }

    // 通知を保存 (onNotificationCreatedにより自動でプッシュ通知も送信される)
    const title = type === "on_time" ? "📋 タスクの時間です" : "🔔 タスクリマインダー";
    const body = type === "on_time"
      ? `「${taskContent}」の予定時刻になりました`
      : `「${taskContent}」の${timeLabel}です`;

    await db.collection("users").doc(userId).collection("notifications").add({
      type: "task_reminder",
      title,
      body,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      taskId,
      reminderKey,
      clientType: type,
    });

    console.log(`[Reminder] Notification saved for ${taskId} - ${reminderKey}`);

    // 送信済みとして記録
    await sentRef.set({
      taskId,
      userId,
      reminderKey,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`[Reminder] Sent: ${taskId} - ${reminderKey}`);
    response.status(200).send("Notification sent");
  } catch (error) {
    console.error("[Reminder] Error:", error);
    response.status(500).send("Error");
  }
});


// ===============================================
// リアクション追加時のtotalPraises更新
// ===============================================

/**
 * リアクション追加時に投稿者のtotalPraisesをインクリメント
 */
export const onReactionCreated = onDocumentCreated(
  "reactions/{reactionId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No reaction data");
      return;
    }

    const reactionData = snapshot.data();
    const postId = reactionData.postId;
    const reactorId = reactionData.userId;

    console.log(`=== onReactionCreated: postId=${postId}, reactor=${reactorId} ===`);

    try {
      // 投稿を取得して投稿者IDを取得
      const postDoc = await db.collection("posts").doc(postId).get();
      if (!postDoc.exists) {
        console.log("Post not found:", postId);
        return;
      }

      const postData = postDoc.data()!;
      const postOwnerId = postData.userId;

      // 自分へのリアクションはカウントしない
      if (postOwnerId === reactorId) {
        console.log("Self-reaction, skipping totalPraises update");
        return;
      }

      // 投稿者のtotalPraisesをインクリメント
      await db.collection("users").doc(postOwnerId).update({
        totalPraises: admin.firestore.FieldValue.increment(1),
      });

      console.log(`Incremented totalPraises for user: ${postOwnerId}`);

    } catch (error) {
      console.error("onReactionCreated ERROR:", error);
    }
  }
);

// ===============================================
// 画像モデレーションCallable関数
// ===============================================

/**
 * アップロード前の画像をモデレーション
 * Base64エンコードされた画像データを受け取り、不適切かどうか判定
 */
export const moderateImageCallable = onCall(
  { secrets: [geminiApiKey], region: LOCATION },
  async (request) => {
    const { imageBase64, mimeType = "image/jpeg" } = request.data;

    if (!imageBase64) {
      throw new HttpsError("invalid-argument", "imageBase64 is required");
    }

    // 認証チェック
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    try {
      const apiKey = geminiApiKey.value();
      const genAI = new GoogleGenerativeAI(apiKey);
      const model = genAI.getGenerativeModel({ model: AI_MODELS.GEMINI_DEFAULT });

      const prompt = IMAGE_MODERATION_CALLABLE_PROMPT;

      const imagePart: Part = {
        inlineData: {
          mimeType: mimeType,
          data: imageBase64,
        },
      };

      const result = await model.generateContent([prompt, imagePart]);
      const responseText = result.response.text().trim();

      let jsonText = responseText;
      // JSONブロックを抽出
      const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
      if (jsonMatch) {
        jsonText = jsonMatch[1];
      }

      const moderationResult = JSON.parse(jsonText) as MediaModerationResult;

      console.log(`Image moderation result: ${JSON.stringify(moderationResult)}`);

      return moderationResult;

    } catch (error) {
      console.error("moderateImageCallable ERROR:", error);
      // エラー時は許可（サービス継続性を優先）
      return {
        isInappropriate: false,
        category: "none",
        confidence: 0,
        reason: "モデレーションエラー",
      };
    }
  }
);


// cleanupOrphanedMedia, cleanupResolvedInquiries, cleanupReports は scheduled/cleanup.ts に移動済み
// setAdminRole, removeAdminRole, banUser, permanentBanUser, unbanUser, cleanupBannedUsers は callable/admin.ts に移動済み

