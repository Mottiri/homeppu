import { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } from "firebase-functions/v2/firestore";
import * as functionsV1 from "firebase-functions/v1";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions } from "firebase-functions/v2"; // Global Options

import * as admin from "firebase-admin";
import { GoogleGenerativeAI, Part, GenerativeModel } from "@google/generative-ai";
import { GoogleAIFileManager } from "@google/generative-ai/server";
import * as https from "https";
import { CloudTasksClient } from "@google-cloud/tasks";
import { google } from "googleapis";

import { AIProviderFactory } from "./ai/provider";
import { PROJECT_ID, LOCATION, QUEUE_NAME, SPREADSHEET_ID } from "./config/constants";
import { geminiApiKey, openaiApiKey, sheetsServiceAccountKey } from "./config/secrets";
import { isAdmin, getAdminUids } from "./helpers/admin";
import { deleteStorageFileFromUrl } from "./helpers/storage";
import { appendInquiryToSpreadsheet } from "./helpers/spreadsheet";
import { NegativeCategory, ModerationResult, MediaModerationResult, MediaItem } from "./types";
import {
  Gender,
  AgeGroup,
  OCCUPATIONS,
  PERSONALITIES,
  PRAISE_STYLES,
  AGE_GROUPS,
  NamePart,
  PREFIX_PARTS,
  SUFFIX_PARTS,
  AIPersona,
  BIO_TEMPLATES,
  AI_USABLE_PREFIXES,
  AI_USABLE_SUFFIXES,
  generateAIPersona,
  AI_PERSONAS,
  getSystemPrompt,
  getCircleSystemPrompt,
} from "./ai/personas";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

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

admin.initializeApp();
const db = admin.firestore();

// Set global options for v2 functions
setGlobalOptions({ region: "asia-northeast1" });

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

// ===============================================
// 徳システム設定
// ===============================================
const VIRTUE_CONFIG = {
  initial: 100,           // 初期徳ポイント
  maxDaily: 50,           // 1日の最大獲得量
  banThreshold: 0,        // BAN閾値
  lossPerNegative: 15,    // ネガティブ発言1回あたりの減少
  lossPerReport: 20,      // 通報1回あたりの減少
  gainPerPraise: 5,       // 称賛1回あたりの増加
  warningThreshold: 30,   // 警告表示閾値
};

// ===============================================
// プッシュ通知送信ヘルパー（サポート通知用）
// ===============================================

/**
 * 指定ユーザーにプッシュ通知のみを送信（Firestore保存なし）
 */
async function sendPushOnly(
  userId: string,
  title: string,
  body: string,
  data?: Record<string, unknown>
): Promise<void> {
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;

    if (!fcmToken) {
      console.log(`No FCM token for user ${userId}, skipping push notification`);
      return;
    }

    // チャンネルIDの決定
    let channelId = "default_channel";
    if (data?.type === "task_reminder" || data?.type === "task_due") {
      channelId = "task_reminders";
    }

    // FCM dataペイロードは全て文字列である必要があるため変換
    const stringifiedData: { [key: string]: string } = {};
    if (data) {
      for (const [key, value] of Object.entries(data)) {
        if (value !== undefined && value !== null) {
          // Timestamp オブジェクトの場合は toDate().toISOString() を使用
          if (typeof value === "object" && "toDate" in value && typeof value.toDate === "function") {
            stringifiedData[key] = value.toDate().toISOString();
          } else {
            stringifiedData[key] = String(value);
          }
        }
      }
    }

    const message: admin.messaging.Message = {
      token: fcmToken,
      notification: {
        title,
        body,
      },
      data: stringifiedData,
      android: {
        priority: "high",
        notification: {
          channelId,
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    await admin.messaging().send(message);
    console.log(`Push notification sent to user ${userId}: ${title} (channel: ${channelId})`);
  } catch (error: unknown) {
    // トークンが無効な場合はトークンを削除
    if (error && typeof error === "object" && "code" in error) {
      const firebaseError = error as { code: string };
      if (
        firebaseError.code === "messaging/invalid-registration-token" ||
        firebaseError.code === "messaging/registration-token-not-registered"
      ) {
        console.log(`Removing invalid FCM token for user ${userId}`);
        await db.collection("users").doc(userId).update({
          fcmToken: admin.firestore.FieldValue.delete(),
        });
      }
    }
    console.error(`Error sending push notification to ${userId}:`, error);
  }
}

// Google Sheets ヘルパー: helpers/spreadsheet.ts に移動

// ===============================================
// メディアモデレーション
// ===============================================

/**
 * URLからファイルをダウンロード
 */
async function downloadFile(url: string): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    https.get(url, (response) => {
      // リダイレクト対応
      if (response.statusCode === 301 || response.statusCode === 302) {
        const redirectUrl = response.headers.location;
        if (redirectUrl) {
          downloadFile(redirectUrl).then(resolve).catch(reject);
          return;
        }
      }

      if (response.statusCode !== 200) {
        reject(new Error(`Failed to download: ${response.statusCode} `));
        return;
      }

      const chunks: Buffer[] = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => resolve(Buffer.concat(chunks)));
      response.on("error", reject);
    }).on("error", reject);
  });
}

/**
 * 画像をモデレーション
 */
async function moderateImage(
  model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
  imageUrl: string,
  mimeType: string = "image/jpeg"
): Promise<MediaModerationResult> {
  try {
    console.log(`moderateImage: Starting moderation for ${imageUrl.substring(0, 100)}...`);
    const imageBuffer = await downloadFile(imageUrl);
    const base64Image = imageBuffer.toString("base64");
    console.log(`moderateImage: Downloaded image, size=${imageBuffer.length} bytes`);

    const prompt = `
この画像がSNSへの投稿として適切かどうか判定してください。

【ブロック対象（isInappropriate: true）】
- adult: 成人向けコンテンツ、露出の多い画像、性的な内容
- violence: 暴力的な画像、血液、怪我、残虐な内容、血まみれ
- hate: ヘイトシンボル、差別的な画像
- dangerous: 危険な行為、違法行為、武器

上記に該当しない場合は isInappropriate: false としてください。

【回答形式】
JSON形式のみで回答:
{"isInappropriate": true/false, "category": "adult"|"violence"|"hate"|"dangerous"|"none", "confidence": 0-1, "reason": "理由"}
`;

    const imagePart: Part = {
      inlineData: {
        mimeType: mimeType,
        data: base64Image,
      },
    };

    const result = await model.generateContent([prompt, imagePart]);
    const responseText = result.response.text().trim();
    console.log(`moderateImage: Raw response: ${responseText.substring(0, 200)}`);

    let jsonText = responseText;
    // JSON部分を抽出
    const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
    if (jsonMatch) {
      jsonText = jsonMatch[1];
    } else {
      // ブレースで囲まれた部分を抽出
      const braceMatch = responseText.match(/\{[\s\S]*\}/);
      if (braceMatch) {
        jsonText = braceMatch[0];
      }
    }

    const parsed = JSON.parse(jsonText) as MediaModerationResult;
    console.log(`moderateImage: Parsed result: isInappropriate=${parsed.isInappropriate}, category=${parsed.category}, confidence=${parsed.confidence}`);
    return parsed;
  } catch (error) {
    console.error("moderateImage error:", error);
    // Fail Closed: エラー時は不適切として扱う（安全第一）
    return {
      isInappropriate: true,
      category: "dangerous",
      confidence: 1.0,
      reason: "モデレーション処理エラー - 安全のためブロック",
    };
  }
}

/**
 * 動画をモデレーション
 */
async function moderateVideo(
  apiKey: string,
  model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
  videoUrl: string,
  mimeType: string = "video/mp4"
): Promise<MediaModerationResult> {
  const tempFilePath = path.join(os.tmpdir(), `video_${Date.now()}.mp4`);

  try {
    // 動画をダウンロード
    const videoBuffer = await downloadFile(videoUrl);
    fs.writeFileSync(tempFilePath, videoBuffer);

    // Gemini File APIにアップロード
    const fileManager = new GoogleAIFileManager(apiKey);
    const uploadResult = await fileManager.uploadFile(tempFilePath, {
      mimeType: mimeType,
      displayName: `moderation_video_${Date.now()} `,
    });

    // アップロード完了を待つ
    let file = uploadResult.file;
    while (file.state === "PROCESSING") {
      await new Promise((resolve) => setTimeout(resolve, 2000));
      const result = await fileManager.getFile(file.name);
      file = result;
    }

    if (file.state === "FAILED") {
      throw new Error("Video processing failed");
    }

    const prompt = `
この動画がSNSへの投稿として適切かどうか判定してください。

【ブロック対象（isInappropriate: true）】
- adult: 成人向けコンテンツ、露出の多い映像、性的な内容
- violence: 暴力的な映像、血液、怪我、残虐な内容
- hate: ヘイトシンボル、差別的な内容
- dangerous: 危険な行為、違法行為、武器

上記に該当しない場合は isInappropriate: false としてください。

【回答形式】
必ず以下のJSON形式のみで回答してください：
{"isInappropriate": true/false, "category": "adult"|"violence"|"hate"|"dangerous"|"none", "confidence": 0-1, "reason": "判定理由"}
`;

    const videoPart: Part = {
      fileData: {
        mimeType: file.mimeType,
        fileUri: file.uri,
      },
    };

    const result = await model.generateContent([prompt, videoPart]);
    const responseText = result.response.text().trim();

    let jsonText = responseText;
    const jsonMatch = responseText.match(/```(?: json) ?\s * ([\s\S] *?) \s * ```/);
    if (jsonMatch) {
      jsonText = jsonMatch[1];
    }

    // アップロードしたファイルを削除
    try {
      await fileManager.deleteFile(file.name);
    } catch (e) {
      console.log("Failed to delete uploaded file:", e);
    }

    return JSON.parse(jsonText) as MediaModerationResult;
  } catch (error) {
    console.error("Video moderation error:", error);
    // エラー時は許可
    return {
      isInappropriate: false,
      category: "none",
      confidence: 0,
      reason: "モデレーションエラー",
    };
  } finally {
    // 一時ファイルを削除
    if (fs.existsSync(tempFilePath)) {
      fs.unlinkSync(tempFilePath);
    }
  }
}

/**
 * メディアアイテムをモデレーション
 */
async function moderateMedia(
  apiKey: string,
  model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
  mediaItems: MediaItem[]
): Promise<{ passed: boolean; failedItem?: MediaItem; result?: MediaModerationResult }> {
  for (const item of mediaItems) {
    if (item.type === "image") {
      const result = await moderateImage(model, item.url, item.mimeType || "image/jpeg");
      if (result.isInappropriate && result.confidence >= 0.7) {
        return { passed: false, failedItem: item, result };
      }
    } else if (item.type === "video") {
      const result = await moderateVideo(apiKey, model, item.url, item.mimeType || "video/mp4");
      if (result.isInappropriate && result.confidence >= 0.7) {
        return { passed: false, failedItem: item, result };
      }
    }
    // fileタイプはスキップ（PDFなどのモデレーションは複雑なため）
  }

  return { passed: true };
}

// ===============================================
// AIコメント用メディア分析
// ===============================================

/**
 * 画像の内容を分析して説明を生成
 */
async function analyzeImageForComment(
  model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
  imageUrl: string,
  mimeType: string = "image/jpeg"
): Promise<string | null> {
  try {
    const imageBuffer = await downloadFile(imageUrl);
    const base64Image = imageBuffer.toString("base64");

    const prompt = `
この画像の内容を分析して、SNS投稿者を褒めるための情報を提供してください。

【重要なルール】
1. 専門的な内容（資格試験、プログラミング、専門書、学習アプリ、技術文書、問題集など）の場合：
- 画像内のテキストを断片的に解釈しないでください
  - 「何の勉強・学習をしているか」だけを簡潔に説明してください（例：「資格試験の勉強」「プログラミング学習」）
- 詳細な内容には触れず「専門的で難しそう」「すごい挑戦」という観点で説明してください
  - 例: 「資格試験の学習アプリで勉強している画像です。専門的な内容に取り組んでいて頑張っています。」
- 悪い例: 「心理療法士の問題を解いている」← 画像内テキストの断片的解釈はNG

2. 一般的な内容（料理、運動、風景、作品、ペットなど）の場合：
- 具体的に何が写っているか説明してください
  - 褒めポイントを含めてください
  - 例: 「手作りのケーキの写真です。デコレーションがとても丁寧です。」

3. 画像内にテキストが含まれる場合でも、そのテキストの一部だけを切り取って解釈しないでください。
文脈を誤解する原因になります。

【回答形式】
2〜3文で簡潔に説明してください。
`;

    const imagePart: Part = {
      inlineData: {
        mimeType: mimeType,
        data: base64Image,
      },
    };

    const result = await model.generateContent([prompt, imagePart]);
    const description = result.response.text()?.trim();

    console.log("Image analysis result:", description);
    return description || null;
  } catch (error) {
    console.error("Image analysis error:", error);
    return null;
  }
}

/**
 * 動画の内容を分析して説明を生成
 */
async function analyzeVideoForComment(
  apiKey: string,
  model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
  videoUrl: string,
  mimeType: string = "video/mp4"
): Promise<string | null> {
  const tempFilePath = path.join(os.tmpdir(), `video_analysis_${Date.now()}.mp4`);

  try {
    // 動画をダウンロード
    const videoBuffer = await downloadFile(videoUrl);
    fs.writeFileSync(tempFilePath, videoBuffer);

    // Gemini File APIにアップロード
    const fileManager = new GoogleAIFileManager(apiKey);
    const uploadResult = await fileManager.uploadFile(tempFilePath, {
      mimeType: mimeType,
      displayName: `analysis_video_${Date.now()} `,
    });

    // アップロード完了を待つ
    let file = uploadResult.file;
    while (file.state === "PROCESSING") {
      await new Promise((resolve) => setTimeout(resolve, 2000));
      const result = await fileManager.getFile(file.name);
      file = result;
    }

    if (file.state === "FAILED") {
      throw new Error("Video processing failed");
    }

    const prompt = `
この動画の内容を分析して、SNS投稿者を褒めるための情報を提供してください。

【重要なルール】
1. 専門的な内容（勉強、プログラミング、技術作業、資格試験など）の場合：
- 画面内のテキストを断片的に解釈しないでください
  - 「何の勉強・作業をしているか」だけを簡潔に説明してください
    - 詳細な内容には触れず「専門的で難しそう」「すごい挑戦」という観点で説明してください
      - 例: 「資格試験の勉強をしている動画です。専門的な内容に取り組んでいて頑張っています。」

2. 一般的な内容（運動、料理、ゲーム、趣味など）の場合：
- 具体的に何をしている動画か説明してください
  - 褒めポイントを含めてください
  - 例: 「ランニングの動画です。良いペースで走っていて、フォームも綺麗です。」

3. 動画内にテキストが含まれる場合でも、そのテキストの一部だけを切り取って解釈しないでください。

【回答形式】
2〜3文で簡潔に説明してください。
`;

    const videoPart: Part = {
      fileData: {
        mimeType: file.mimeType,
        fileUri: file.uri,
      },
    };

    const result = await model.generateContent([prompt, videoPart]);
    const description = result.response.text()?.trim();

    // アップロードしたファイルを削除
    try {
      await fileManager.deleteFile(file.name);
    } catch (e) {
      console.log("Failed to delete uploaded file:", e);
    }

    console.log("Video analysis result:", description);
    return description || null;
  } catch (error) {
    console.error("Video analysis error:", error);
    return null;
  } finally {
    // 一時ファイルを削除
    if (fs.existsSync(tempFilePath)) {
      fs.unlinkSync(tempFilePath);
    }
  }
}

/**
 * メディアアイテムを分析して説明を生成
 */
async function analyzeMediaForComment(
  apiKey: string,
  model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
  mediaItems: MediaItem[]
): Promise<string[]> {
  const descriptions: string[] = [];

  for (const item of mediaItems) {
    try {
      if (item.type === "image") {
        const desc = await analyzeImageForComment(model, item.url, item.mimeType || "image/jpeg");
        if (desc) {
          descriptions.push(`【画像】${desc} `);
        }
      } else if (item.type === "video") {
        const desc = await analyzeVideoForComment(apiKey, model, item.url, item.mimeType || "video/mp4");
        if (desc) {
          descriptions.push(`【動画】${desc} `);
        }
      }
    } catch (error) {
      console.error(`Failed to analyze media item: `, error);
    }
  }

  return descriptions;
}

// AIペルソナ定義は ai/personas.ts に移動済み
/**
 * 新規投稿時にAIコメントを生成するトリガー
 * メディア（画像・動画）がある場合は内容を分析してコメントに反映
 */
export const onPostCreated = onDocumentCreated(
  {
    document: "posts/{postId}",
    region: "asia-northeast1",
    secrets: [geminiApiKey],
    timeoutSeconds: 120, // メディア分析のため長めに設定
    memory: "1GiB", // 動画処理のためメモリを増加
    serviceAccount: "cloud-tasks-sa@positive-sns.iam.gserviceaccount.com", // Cloud Tasks作成権限を持つSAを指定
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      console.log("No data associated with the event");
      return;
    }

    const postData = snap.data();
    const postId = event.params.postId;

    console.log(`=== onPostCreated: postId=${postId}, circleId=${postData.circleId}, postMode=${postData.postMode} ===`);

    // サークル投稿かどうかを判定
    const isCirclePost = postData.circleId && postData.circleId !== "" && postData.circleId !== null;

    // 人間モードの投稿にはAIコメントを付けない
    if (postData.postMode === "human") {
      console.log("Human mode post, skipping AI comments");
      return;
    }

    // APIキーを取得
    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      console.error("GEMINI_API_KEY is not set");
      return;
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

    // メディアがある場合は内容を分析
    let mediaDescriptions: string[] = [];
    const mediaItems = postData.mediaItems as MediaItem[] | undefined;

    if (mediaItems && mediaItems.length > 0) {
      console.log(`Analyzing ${mediaItems.length} media items for AI comment...`);
      try {
        mediaDescriptions = await analyzeMediaForComment(apiKey, model, mediaItems);
        console.log(`Media analysis complete: ${mediaDescriptions.length} descriptions`);
      } catch (error) {
        console.error("Media analysis failed:", error);
        // エラーでもコメント生成は続行
      }
    }

    // サークル投稿の場合はサークルAIを使用、それ以外は一般AIを使用
    let selectedPersonas: AIPersona[];
    let circleName = "";
    let circleDescription = "";
    let circleGoal = "";
    let circleRules = "";

    if (isCirclePost) {
      // サークル情報を取得
      const circleDoc = await db.collection("circles").doc(postData.circleId).get();
      if (!circleDoc.exists) {
        console.log(`Circle ${postData.circleId} not found, skipping AI comments`);
        return;
      }

      const circleData = circleDoc.data()!;

      // humanOnlyモードの場合はAIコメントをスキップ
      if (circleData.aiMode === "humanOnly") {
        console.log(`Circle ${postData.circleId} is humanOnly mode, skipping AI comments`);
        return;
      }

      const generatedAIs = circleData.generatedAIs as Array<{
        id: string;
        name: string;
        gender: Gender;
        ageGroup: AgeGroup;
        occupation: { id: string; name: string; bio: string };
        personality: { id: string; name: string; trait: string; style: string; examples?: string[] };
        avatarIndex: number;
        circleContext?: string;
      }> || [];

      if (generatedAIs.length === 0) {
        console.log(`No generated AIs for circle ${postData.circleId}, skipping AI comments`);
        return;
      }

      // サークルのgoal, rules, descriptionを取得
      circleName = circleData.name || "";
      circleDescription = circleData.description || "";
      circleGoal = circleData.goal || "";
      circleRules = circleData.rules || "";

      // サークルAIをAIPersona形式に変換
      // PERSONALITIESから対応するexamplesを取得
      selectedPersonas = generatedAIs.map((ai) => {
        // personalityに対応するexamplesをPERSONALITIESから取得
        const gender = ai.gender || "female";
        const personalityList = PERSONALITIES[gender];
        const matchedPersonality = personalityList.find(p => p.id === ai.personality?.id) || personalityList[0];

        return {
          id: ai.id,
          name: ai.name,
          namePrefixId: "",
          nameSuffixId: "",
          gender: gender,
          ageGroup: ai.ageGroup,
          occupation: ai.occupation,
          personality: {
            ...ai.personality,
            examples: matchedPersonality.examples,
            reactionType: matchedPersonality.reactionType,
            reactionGuide: matchedPersonality.reactionGuide,
          },
          praiseStyle: PRAISE_STYLES[Math.floor(Math.random() * PRAISE_STYLES.length)],
          avatarIndex: ai.avatarIndex,
          bio: "",
        };
      });

      console.log(`Using ${selectedPersonas.length} circle AIs for comments`);
    } else {
      // 一般投稿：ランダムに1〜5人のAIを選択（平均3件）
      const commentCount = Math.floor(Math.random() * 5) + 1;
      selectedPersonas = [...AI_PERSONAS]
        .sort(() => Math.random() - 0.5)
        .slice(0, commentCount);

      console.log(`Using ${selectedPersonas.length} general AIs for comments`);
    }

    let totalComments = 0;

    // 投稿者の名前を取得
    const posterName = postData.userDisplayName || "投稿者";



    // ランダムな遅延時間を生成し、昇順にソート（順番にコメントが来るようにする）
    // 最低2分間隔で実行（前のコメントが確実に保存されてからクエリするため）
    const delays = Array.from({ length: selectedPersonas.length }, (_, i) => (i + 1) * 2 + Math.floor(Math.random() * 2))
      .sort((a, b) => a - b);

    // Cloud Tasks クライアント
    const tasksClient = new CloudTasksClient();
    const queuePath = tasksClient.queuePath(process.env.GCLOUD_PROJECT || PROJECT_ID, LOCATION, QUEUE_NAME);

    for (let i = 0; i < selectedPersonas.length; i++) {
      const persona = selectedPersonas[i];
      const delayMinutes = delays[i];

      // タスクの実行時間を計算
      const scheduleTime = new Date(Date.now() + delayMinutes * 60 * 1000);

      try {
        // ペイロード作成（画像分析結果も含めることで、個別の再分析を回避）
        const payload = {
          postId: postId,
          postContent: postData.content || "",
          userDisplayName: posterName,
          personaId: persona.id,
          personaName: persona.name,
          personaGender: persona.gender,
          personaAgeGroup: persona.ageGroup,
          personaOccupation: persona.occupation,
          personaPersonality: persona.personality,
          personaPraiseStyle: persona.praiseStyle,
          personaAvatarIndex: persona.avatarIndex,
          mediaDescriptions: mediaDescriptions, // 分析済みデータを渡す
          isCirclePost: isCirclePost,
          circleName: isCirclePost ? circleName : "",
          circleDescription: isCirclePost ? circleDescription : "",
          circleGoal: isCirclePost ? circleGoal : "",
          circleRules: isCirclePost ? circleRules : "",
        };

        // v1関数のURL形式 (asia-northeast1-PROJECT_ID.cloudfunctions.net/FUNCTION_NAME)
        const targetUrl = `https://${LOCATION}-${process.env.GCLOUD_PROJECT}.cloudfunctions.net/generateAICommentV1`;

        // ユーザーに作成してもらうサービスアカウント
        const serviceAccountEmail = `cloud-tasks-sa@${process.env.GCLOUD_PROJECT}.iam.gserviceaccount.com`;

        console.log(`Enqueuing task for ${persona.name} to ${targetUrl} with SA ${serviceAccountEmail}`);

        const task = {
          httpRequest: {
            httpMethod: "POST" as const,
            url: targetUrl,
            body: Buffer.from(JSON.stringify(payload)).toString("base64"),
            headers: {
              "Content-Type": "application/json",
            },
            oidcToken: {
              serviceAccountEmail: serviceAccountEmail,
            },
          },
          scheduleTime: {
            seconds: Math.floor(scheduleTime.getTime() / 1000),
          },
        };

        await tasksClient.createTask({ parent: queuePath, task });

        console.log(`Task enqueued for ${persona.name}: delay=${delayMinutes}m, time=${scheduleTime.toISOString()}`);
        totalComments++; // 見込み数としてカウント
      } catch (error) {
        console.error(`Error enqueuing task for ${persona.name}:`, error);
      }
    }

    // コメント数はAIコメント生成時（generateAICommentV1）でインクリメントする
    // 先行インクリメントは削除（実際のコメント数のみ表示するため）

    // ===========================================
    // 2. AIリアクションの大量投下 (5〜10件、最大10件)
    // ===========================================
    const reactionCount = Math.floor(Math.random() * 6) + 5; // 5〜10
    console.log(`Scheduling ${reactionCount} reactions (burst)...`);

    const POSITIVE_REACTIONS = ["love", "praise", "cheer", "sparkles", "clap", "thumbsup", "smile", "flower", "fire", "nice"];

    // コメントするAIも含めて、全AIからランダムに選ぶ
    for (let i = 0; i < reactionCount; i++) {
      const persona = AI_PERSONAS[Math.floor(Math.random() * AI_PERSONAS.length)];

      const reactionType = POSITIVE_REACTIONS[Math.floor(Math.random() * POSITIVE_REACTIONS.length)];

      // 10秒〜60分後のランダムな時間
      const delaySeconds = Math.floor(Math.random() * 3600) + 10;
      const scheduleTime = new Date(Date.now() + delaySeconds * 1000);

      const payload = {
        postId,
        personaId: persona.id,
        personaName: persona.name,
        reactionType,
      };

      const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
      const url = `https://${LOCATION}-${project}.cloudfunctions.net/generateAIReactionV1`;
      const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

      const task = {
        httpRequest: {
          httpMethod: "POST" as const,
          url,
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer secret-token",
          },
          body: Buffer.from(JSON.stringify(payload)).toString("base64"),
          oidcToken: {
            serviceAccountEmail: serviceAccountEmail,
          },
        },
        scheduleTime: {
          seconds: Math.floor(scheduleTime.getTime() / 1000),
        },
      };

      try {
        await tasksClient.createTask({ parent: queuePath, task });
      } catch (error) {
        console.error(`Error enqueuing reaction for ${persona.name}:`, error);
      }
    }

    console.log(`Scheduled ${reactionCount} reaction tasks`);
  }
);

// AIの投稿テンプレート（職業・性格に応じた内容を動的に生成するための基本パターン）
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
    "新規のお客様と良い商談ができた！手応えあり！",
    "プレゼン資料作成中。伝わる資料を目指して頑張る",
    "後輩の成長が嬉しい！俺も負けてられないな",
    "朝活で自己啓発の本読んでる。インプット大事！",
  ],
  engineer: [
    "やっとバグ解決できた...！原因分かった時の快感最高",
    "新しい技術のドキュメント読んでる。学ぶことが多くて楽しい",
    "今日のコードレビューで良いフィードバックもらえた",
    "リモートワークの日。集中して作業できた！",
    "個人開発のプロジェクト、少しずつ形になってきた",
  ],
  streamer: [
    "今日の配信見てくれた人ありがとう！楽しかった",
    "新しいゲーム始めた！ハマりそう",
    "サムネ作成中...センスが試される",
    "フォロワー増えてきて嬉しい！もっと頑張る",
    "機材のセッティング終わった！今日も配信するよ",
  ],
  freeter: [
    "バイト終わった！今日も忙しかったけど充実してた",
    "空き時間で自分の夢の準備。少しずつでも前に進んでる",
    "今日は休み！自分の時間を大切にする日",
    "新しいバイト先、いい人ばかりで働きやすい",
    "将来のためにスキルアップ中。コツコツ頑張る",
  ],
  ol: [
    "今日の仕事終わり！明日のためにゆっくり休もう",
    "お昼休みにカフェでリフレッシュ☕",
    "会議で自分の意見が採用された！嬉しい",
    "仕事帰りにジム。運動すると気分スッキリ",
    "週末の予定を考えるのが今の楽しみ",
  ],
  nursery_teacher: [
    "子どもたちと一緒に過ごす時間が幸せ",
    "園児さんの成長を感じられて嬉しい日だった",
    "今日作った製作物、みんな喜んでくれた！",
    "保護者さんに感謝の言葉をもらえた。この仕事やっててよかった",
    "明日の準備OK！早く子どもたちに会いたいな",
  ],
  designer: [
    "新しいデザイン完成！納得のいく仕上がりになった",
    "クライアントさんに喜んでもらえた✨",
    "インプットの日。いろんな作品を見て刺激を受けた",
    "デザインツールのアップデートで新機能が使える！",
    "ポートフォリオ更新中。自分の成長が見えて嬉しい",
  ],
  nurse: [
    "今日も患者さんの笑顔が見られてよかった",
    "夜勤明け！ゆっくり休んで回復しよう",
    "新しい知識を学ぶ研修、とても勉強になった",
    "チームのみんなと協力して乗り越えた一日",
    "医療の仕事は大変だけど、やりがいがある",
  ],
};

/**
 * Gemini APIを使ってキャラクターに合ったbioを生成
 */
async function generateBioWithGemini(
  model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
  persona: AIPersona
): Promise<string> {
  const genderStr = persona.gender === "male" ? "男性" : "女性";
  const ageStr = AGE_GROUPS[persona.ageGroup].name;

  const prompt = `
あなたはSNSのプロフィール文（bio）を作成するアシスタントです。
以下のキャラクター設定に基づいて、そのキャラクターが自分で書いたような自然なbioを作成してください。

【キャラクター設定】
- 性別: ${genderStr}
- 年齢層: ${ageStr}
- 職業: ${persona.occupation.name}（${persona.occupation.bio}）
- 性格: ${persona.personality.name}（${persona.personality.trait}）

【重要なルール】
1. 40〜80文字程度で書く
2. そのキャラクターが自分で書いたような自然な文章
3. 説明文ではなく、自己紹介文として書く
4. 「〜な性格です」のような説明的な文は避ける
5. 職業と趣味や日常を自然に織り交ぜる
6. 名前は含めないでください
7. 「すごい」「えらい」「わかるよ〜」「いいんじゃない？」など、他者への反応・コメントのような言葉は入れない（bioは自己紹介であり、他者への反応の場ではない）

【良い例】
- 「Webデザイナーしてます🎨 休日は美術館巡り」
- 「営業マン3年目！休日は筋トレに励んでます💪」
- 「保育士やってます〜 子どもたちに癒される日々🌸」
- 「エンジニアやってるww 深夜コーディングが日課」

【悪い例】
- 「26歳 / 大学生🫐 学業やサークル活動に励む。トレンドに敏感な性格です。」← 説明的すぎる
  - 「私は優しい性格の看護師です」← 説明文になっている

【出力】
bioのテキストのみを出力してください。他の説明は不要です。
`;

  try {
    const result = await model.generateContent(prompt);
    const bio = result.response.text()?.trim();

    if (bio && bio.length > 0 && bio.length <= 100) {
      return bio;
    }

    // 長すぎる場合は切り詰め
    if (bio && bio.length > 100) {
      return bio.substring(0, 100);
    }

    // 生成失敗時のフォールバック
    return `${persona.occupation.name} してます！よろしくね✨`;
  } catch (error) {
    console.error(`Bio generation error for ${persona.name}: `, error);
    return `${persona.occupation.name} してます！よろしくね✨`;
  }
}

/**
 * AIアカウントを初期化する関数（管理者用）
 * 既存のアカウントも更新します
 * ランダム組み合わせ方式で20体のAIアカウントを生成
 * Gemini APIでキャラクターに合ったbioを動的生成
 */
export const initializeAIAccounts = onCall(
  { region: "asia-northeast1", secrets: [geminiApiKey], timeoutSeconds: 300 },
  async (request) => {
    // セキュリティ: 管理者権限チェック
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const userIsAdmin = await isAdmin(request.auth.uid);
    if (!userIsAdmin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      return { success: false, message: "GEMINI_API_KEY is not set" };
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

    let createdCount = 0;
    let updatedCount = 0;
    const generatedBios: { name: string; bio: string }[] = [];

    console.log(`Initializing ${AI_PERSONAS.length} AI accounts with Gemini - generated bios...`);

    for (const persona of AI_PERSONAS) {
      const docRef = db.collection("users").doc(persona.id);
      const doc = await docRef.get();

      // Gemini APIでbioを生成
      console.log(`Generating bio for ${persona.name}...`);
      const generatedBio = await generateBioWithGemini(model, persona);
      console.log(`  Generated: "${generatedBio}"`);
      generatedBios.push({ name: persona.name, bio: generatedBio });

      // AIキャラ設定を保存（コメント生成時に使用）
      const aiCharacterSettings = {
        gender: persona.gender,
        ageGroup: persona.ageGroup,
        occupationId: persona.occupation.id,
        personalityId: persona.personality.id,
        praiseStyleId: persona.praiseStyle.id,
      };

      const userData = {
        email: `${persona.id} @ai.homeppu.local`,
        displayName: persona.name,
        namePrefix: persona.namePrefixId,
        nameSuffix: persona.nameSuffixId,
        bio: generatedBio,
        avatarIndex: persona.avatarIndex,
        postMode: "ai",
        virtue: 100,
        isAI: true,
        aiCharacterSettings: aiCharacterSettings,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        isBanned: false,
      };

      if (!doc.exists) {
        await docRef.set({
          ...userData,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          totalPosts: 0,
          totalPraises: 0,
          following: [],
          followers: [],
          followingCount: 0,
          followersCount: 0,
        });
        createdCount++;
        console.log(`Created AI account: ${persona.name} (${persona.id})`);
      } else {
        // 既存アカウントのキャラ設定とbioを更新
        await docRef.update({
          displayName: persona.name,
          namePrefix: persona.namePrefixId,
          nameSuffix: persona.nameSuffixId,
          bio: generatedBio,
          avatarIndex: persona.avatarIndex,
          aiCharacterSettings: aiCharacterSettings,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        updatedCount++;
        console.log(`Updated AI account: ${persona.name} (${persona.id})`);
      }

      // API呼び出しの間隔を空ける（レート制限対策）
      await new Promise((resolve) => setTimeout(resolve, 500));
    }

    // AIアカウントの一覧をログ出力
    console.log("AI Account Summary:");
    AI_PERSONAS.forEach((p, i) => {
      console.log(`  ${i + 1}. ${p.name} - ${p.gender === "male" ? "男" : "女"} /${AGE_GROUPS[p.ageGroup].name}/${p.occupation.name} /${p.personality.name}/${p.praiseStyle.name} `);
    });

    return {
      success: true,
      message: `AIアカウントを作成 / 更新しました（Gemini APIでbio生成: ${AI_PERSONAS.length} 体）`,
      created: createdCount,
      updated: updatedCount,
      totalAccounts: AI_PERSONAS.length,
      accounts: AI_PERSONAS.map((p, i) => ({
        id: p.id,
        name: p.name,
        gender: p.gender,
        ageGroup: AGE_GROUPS[p.ageGroup].name,
        occupation: p.occupation.name,
        personality: p.personality.name,
        praiseStyle: p.praiseStyle.name,
        bio: generatedBios[i]?.bio || "",
      })),
    };
  }
);

/**
 * AIアカウントの過去投稿を生成する関数（管理者用）
 * 各AIの職業に応じたテンプレートを使用して投稿を生成
 */
/**
 * AI投稿生成のディスパッチャー（手動トリガー用）
 * ボタンを押すと、20人分の投稿タスクを「1分〜10分後」にバラけてスケジュールします。
 */
export const generateAIPosts = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    // セキュリティ: 管理者権限チェック
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const userIsAdmin = await isAdmin(request.auth.uid);
    if (!userIsAdmin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    const tasksClient = new CloudTasksClient();
    const project = process.env.GCLOUD_PROJECT;
    const queue = "generate-ai-posts";
    const location = "asia-northeast1";
    const parent = tasksClient.queuePath(project!, location, queue);

    // ファンクションのURL
    const url = `https://${location}-${project}.cloudfunctions.net/executeAIPostGeneration`;

    let taskCount = 0;

    for (const persona of AI_PERSONAS) {
      // 1分(60秒) 〜 10分(600秒) 後のランダムな時間
      const delaySeconds = Math.floor(Math.random() * (600 - 60 + 1)) + 60;
      const scheduleTime = new Date(Date.now() + delaySeconds * 1000);

      const postId = db.collection("posts").doc().id;
      const payload = {
        postId,
        personaId: persona.id,
        postTimeIso: scheduleTime.toISOString(),
      };

      const task = {
        httpRequest: {
          httpMethod: "POST" as const,
          url: url,
          body: Buffer.from(JSON.stringify(payload)).toString("base64"),
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer internal-token",
          },
        },
        scheduleTime: {
          seconds: Math.floor(scheduleTime.getTime() / 1000),
        },
      };

      await tasksClient.createTask({ parent, task });
      taskCount++;
    }

    return {
      success: true,
      message: `AI投稿タスクを${taskCount}件スケジュールしました。\nすべて完了するまでに1分〜10分ほどかかります。`,
    };
  }
);

// ===============================================
// AI投稿自動スケジューラー（2025-12-26追加）
// ===============================================
const MAX_AI_POSTS_PER_DAY = 5; // 1日あたりの投稿AI数

/**
 * AI投稿の自動スケジューラー（Cloud Scheduler用）
 * 毎日朝10時に実行、5人のAIをランダムに選んで投稿
 */
export const scheduleAIPosts = functionsV1.region("asia-northeast1").runWith({
  timeoutSeconds: 60,
}).pubsub.schedule("0 10 * * *").timeZone("Asia/Tokyo").onRun(async () => {
  console.log("=== scheduleAIPosts START ===");

  // ============================================
  // 一時的にAI自動投稿を無効化 (2026-01-05)
  // 有効にする場合はこのブロックをコメントアウトしてください
  // ============================================
  console.log("=== scheduleAIPosts DISABLED (temporary) ===");
  return;
  // ============================================

  try {
    const tasksClient = new CloudTasksClient();
    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    const queue = "generate-ai-posts";
    const location = "asia-northeast1";

    // 昨日の日付を取得（除外用）
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayStr = yesterday.toISOString().split("T")[0];

    // 昨日投稿したAI IDリストを取得
    const historyDoc = await db.collection("aiPostHistory").doc(yesterdayStr).get();
    const excludedAIIds: string[] = historyDoc.exists ? (historyDoc.data()?.aiIds || []) : [];
    console.log(`Excluding ${excludedAIIds.length} AIs from yesterday`);

    // 除外されていないAIをフィルタリング
    const eligibleAIs = AI_PERSONAS.filter(p => !excludedAIIds.includes(p.id));
    console.log(`Eligible AIs: ${eligibleAIs.length}`);

    // ランダムに最大MAX_AI_POSTS_PER_DAY人選択
    const shuffled = eligibleAIs.sort(() => Math.random() - 0.5);
    const selectedAIs = shuffled.slice(0, MAX_AI_POSTS_PER_DAY);
    console.log(`Selected ${selectedAIs.length} AIs for posting`);

    const todayStr = new Date().toISOString().split("T")[0];
    const postedAIIds: string[] = [];

    const url = `https://${location}-${project}.cloudfunctions.net/executeAIPostGeneration`;
    const parent = tasksClient.queuePath(project, location, queue);

    for (const persona of selectedAIs) {
      // 0〜6時間後のランダムな時間にスケジュール
      const delayMinutes = Math.floor(Math.random() * 360); // 0〜360分（6時間）
      const scheduleTime = new Date(Date.now() + delayMinutes * 60 * 1000);

      const postId = db.collection("posts").doc().id;
      const payload = {
        postId,
        personaId: persona.id,
        postTimeIso: scheduleTime.toISOString(),
      };

      const task = {
        httpRequest: {
          httpMethod: "POST" as const,
          url: url,
          body: Buffer.from(JSON.stringify(payload)).toString("base64"),
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer internal-token",
          },
        },
        scheduleTime: {
          seconds: Math.floor(scheduleTime.getTime() / 1000),
        },
      };

      try {
        await tasksClient.createTask({ parent, task });
        console.log(`Scheduled post for ${persona.name} at ${scheduleTime.toISOString()}`);
        postedAIIds.push(persona.id);
      } catch (error) {
        console.error(`Error scheduling task for ${persona.name}:`, error);
      }
    }

    // 今日の投稿履歴を保存（明日の除外用）
    if (postedAIIds.length > 0) {
      const historyRef = db.collection("aiPostHistory").doc(todayStr);
      const existingHistory = await historyRef.get();
      const existingIds: string[] = existingHistory.exists ? (existingHistory.data()?.aiIds || []) : [];
      const mergedIds = [...new Set([...existingIds, ...postedAIIds])];

      await historyRef.set({
        date: todayStr,
        aiIds: mergedIds,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`Saved ${mergedIds.length} AI IDs to history for ${todayStr}`);
    }

    console.log(`=== scheduleAIPosts COMPLETE: Scheduled ${postedAIIds.length} posts ===`);

  } catch (error) {
    console.error("=== scheduleAIPosts ERROR:", error);
  }
});


/**
 * レート制限付きの投稿作成（スパム対策）
 */
export const createPostWithRateLimit = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "ログインが必要です"
      );
    }

    const userId = request.auth.uid;
    const data = request.data;

    // レート制限チェック（1分間に5投稿まで）
    const oneMinuteAgo = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 60000)
    );
    const recentPosts = await db
      .collection("posts")
      .where("userId", "==", userId)
      .where("createdAt", ">", oneMinuteAgo)
      .get();

    if (recentPosts.size >= 5) {
      throw new HttpsError(
        "resource-exhausted",
        "投稿が多すぎるよ！少し待ってからまた投稿してね"
      );
    }

    // 投稿を作成
    const postRef = db.collection("posts").doc();
    await postRef.set({
      ...data,
      userId: userId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      reactions: { love: 0, praise: 0, cheer: 0, empathy: 0 },
      commentCount: 0,
      isVisible: true,
    });

    // ユーザーの投稿数を更新
    await db.collection("users").doc(userId).update({
      totalPosts: admin.firestore.FieldValue.increment(1),
    });

    return { success: true, postId: postRef.id };
  }
);

// ===============================================
// NGワード設定 (静的フィルタ)
// ===============================================
const NG_WORDS = ["殺す", "殺し", "死ね", "死にたい", "消えたい", "暴力", "レイプ", "自殺"];

/**
 * 徳ポイントを減少させる（ネガティブ発言検出時）
 */
async function decreaseVirtue(
  userId: string,
  reason: string,
  amount: number = VIRTUE_CONFIG.lossPerNegative
): Promise<{ newVirtue: number; isBanned: boolean }> {
  const userRef = db.collection("users").doc(userId);
  const userDoc = await userRef.get();

  if (!userDoc.exists) {
    throw new Error("User not found");
  }

  const userData = userDoc.data()!;
  const currentVirtue = userData.virtue || VIRTUE_CONFIG.initial;
  const newVirtue = Math.max(0, currentVirtue - amount);
  const isBanned = newVirtue <= VIRTUE_CONFIG.banThreshold;

  // 徳ポイントを更新
  await userRef.update({
    virtue: newVirtue,
    isBanned: isBanned,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // 徳ポイント変動履歴を記録
  await db.collection("virtueHistory").add({
    userId: userId,
    change: -amount,
    reason: reason,
    newVirtue: newVirtue,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`Virtue decreased for ${userId}: ${currentVirtue} -> ${newVirtue}, banned: ${isBanned} `);

  return { newVirtue, isBanned };
}

/**
 * モデレーション付き投稿作成
 * ネガティブな内容は投稿を拒否し、徳を減少
 */
export const createPostWithModeration = onCall(
  {
    region: "asia-northeast1",
    secrets: [geminiApiKey],
    timeoutSeconds: 120, // メディアモデレーションのため長めに設定
    memory: "1GiB", // 動画処理のためメモリを増加
  },
  async (request) => {
    console.log("=== createPostWithModeration START ===");

    if (!request.auth) {
      console.log("ERROR: Not authenticated");
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const { content, userDisplayName, userAvatarIndex, postMode, circleId, mediaItems } = request.data;
    console.log(`User: ${userId}, Content: ${content?.substring(0, 30)}...`);

    // ユーザーがBANされているかチェック
    const userDoc = await db.collection("users").doc(userId).get();
    if (userDoc.exists && userDoc.data()?.isBanned) {
      console.log("ERROR: User is banned");
      throw new HttpsError(
        "permission-denied",
        "アカウントが制限されているため、現在この機能は使用できません。マイページ画面から運営へお問い合わせください。"
      );
    }
    console.log("STEP 1: User check passed");

    const apiKey = geminiApiKey.value();

    // Fail Closed: APIキーがない場合はエラー
    if (!apiKey) {
      console.error("ERROR: GEMINI_API_KEY is not set");
      throw new HttpsError("internal", "システムエラーが発生しました。しばらくしてから再度お試しください。");
    }
    console.log("STEP 2: API key loaded");

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });
    console.log("STEP 3: Model initialized");

    // 曖昧コンテンツフラグ用変数
    let needsReview = false;
    let needsReviewReason = "";

    // ===============================================
    // テスト用: 管理者の添付付き投稿は常にフラグを付ける
    // ===============================================
    const userIsAdmin = await isAdmin(userId);
    if (userIsAdmin && mediaItems && Array.isArray(mediaItems) && mediaItems.length > 0) {
      needsReview = true;
      needsReviewReason = "【テスト】管理者の添付付き投稿";
      console.log(`TEST FLAG: Admin post with media flagged for review`);
    }

    // ===============================================
    // 0. 静的NGワードチェック (Internal Logic)
    // ===============================================
    if (content) {
      const hasNgWord = NG_WORDS.some(word => content.includes(word));
      if (hasNgWord) {
        // 徳ポイントを減少
        const virtueResult = await decreaseVirtue(
          userId,
          "NGワード使用",
          VIRTUE_CONFIG.lossPerNegative * 2 // NGワードは厳しめに
        );

        throw new HttpsError(
          "invalid-argument",
          `不適切な表現が含まれています。\n「ほめっぷ」はポジティブなSNSです。\n\n(徳ポイント: ${virtueResult.newVirtue})`
        );
      }
    }

    // ===============================================
    // 1. テキストモデレーション (AI)
    // ===============================================
    console.log("STEP 4: Starting text moderation");
    if (model && content) {
      const textPrompt = `
あなたはSNS「ほめっぷ」のコンテンツモデレーターです。
「ほめっぷ」は「世界一優しいSNS」を目指しています。

以下の投稿内容を分析して、「他者への攻撃」や「暴力的な表現」があるかどうか厳格に判定してください。

【ブロック対象（isNegative: true）】
- harassment: 他者への誹謗中傷、人格攻撃、悪口
- hate_speech: 差別、ヘイトスピーチ
- profanity: 暴言、罵倒、汚い言葉（「死ね」「殺す」などは対象なしでもNG）
- violence: 暴力的な表現、脅迫
- self_harm: 自傷行為の助長
- spam: スパム、宣伝

上記に該当しない場合は isNegative: false としてください。

【重要な判定基準】
⚠️ 暴力的な言葉（殺す、死ね、殴るなど）は、対象が特定されていなくても「profanity」または「violence」としてブロックしてください。
⚠️ 「他者を攻撃しているか」は厳しく見てください。

【投稿内容】
${content}

【回答形式】
必ず以下のJSON形式で回答してください。他の文字は含めないでください。
{"isNegative": true/false, "category": "harassment"|"hate_speech"|"profanity"|"violence"|"self_harm"|"spam"|"none", "confidence": 0-1, "reason": "判定理由", "suggestion": "より良い表現の提案"}
`;

      let rawResponseText = "";
      try {
        const result = await model.generateContent(textPrompt);
        const responseText = result.response.text().trim();
        rawResponseText = responseText; // エラー時の記録用
        console.log("STEP 5: Got Gemini response, length:", responseText.length);
        console.log("STEP 5a: Raw response preview:", responseText.substring(0, 300));

        // JSONを抽出（複数の方法で試行）
        let jsonText = responseText;

        // 方法1: ```json ... ``` または ``` ... ``` を抽出
        const codeBlockMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
        if (codeBlockMatch && codeBlockMatch[1]) {
          jsonText = codeBlockMatch[1].trim();
          console.log("STEP 5b: Extracted from code block");
        }
        // 方法2: 最初の { から最後の } までを抽出
        else {
          const firstBrace = responseText.indexOf("{");
          const lastBrace = responseText.lastIndexOf("}");
          if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
            jsonText = responseText.substring(firstBrace, lastBrace + 1);
            console.log("STEP 5b: Extracted by brace matching");
          }
        }

        console.log("STEP 5c: JSON to parse:", jsonText.substring(0, 200));
        const modResult = JSON.parse(jsonText) as ModerationResult;
        console.log("STEP 5d: Parsed successfully, isNegative:", modResult.isNegative);

        // 曖昧コンテンツ判定 (0.5-0.7) → フラグ付き投稿
        if (modResult.isNegative && modResult.confidence >= 0.5 && modResult.confidence < 0.7) {
          needsReview = true;
          needsReviewReason = `テキスト: ${modResult.category} (confidence: ${modResult.confidence})`;
          console.log(`FLAGGED for review: ${needsReviewReason}`);
        }

        if (modResult.isNegative && modResult.confidence >= 0.7) {
          // 徳ポイントを減少
          const virtueResult = await decreaseVirtue(
            userId,
            `ネガティブ投稿検出: ${modResult.category} `,
            VIRTUE_CONFIG.lossPerNegative
          );

          // 投稿を記録（非表示として）
          await db.collection("moderatedContent").add({
            userId: userId,
            content: content,
            type: "post",
            category: modResult.category,
            confidence: modResult.confidence,
            reason: modResult.reason,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          throw new HttpsError(
            "invalid-argument",
            `${modResult.reason} \n\n💡 提案: ${modResult.suggestion} \n\n(徳ポイント: ${virtueResult.newVirtue})`
          );
        }
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }
        console.error("Text moderation error:", error);

        // エラーをFirestoreに記録（デバッグ用）- エラーが発生しても無視
        try {
          await db.collection("moderationErrors").add({
            userId: userId,
            content: content?.substring(0, 100) || "",
            error: String(error),
            rawResponse: rawResponseText ? rawResponseText.substring(0, 500) : "empty",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (firestoreError) {
          console.error("Failed to save moderation error:", firestoreError);
        }

        // Fail Open: AIエラー時は投稿を許可する（UX優先）
        console.log("Moderation failed, allowing post (fail-open)");
      }
    }

    // ===============================================
    // 2. メディアモデレーション（画像・動画）
    // ===============================================
    if (apiKey && model && mediaItems && Array.isArray(mediaItems) && mediaItems.length > 0) {
      console.log(`Moderating ${mediaItems.length} media items...`);

      try {
        const mediaResult = await moderateMedia(apiKey, model, mediaItems as MediaItem[]);

        if (!mediaResult.passed && mediaResult.result) {
          // 曖昧コンテンツ判定 (0.5-0.7) → フラグ付き投稿
          if (mediaResult.result.confidence >= 0.5 && mediaResult.result.confidence < 0.7) {
            needsReview = true;
            needsReviewReason = `メディア: ${mediaResult.result.category} (confidence: ${mediaResult.result.confidence})`;
            console.log(`FLAGGED for review: ${needsReviewReason}`);
          } else if (mediaResult.result.confidence >= 0.7) {
            // 徳ポイントを減少
            const virtueResult = await decreaseVirtue(
              userId,
              `不適切なメディア検出: ${mediaResult.result.category} `,
              VIRTUE_CONFIG.lossPerNegative
            );

            // 記録
            await db.collection("moderatedContent").add({
              userId: userId,
              content: `[メディア] ${mediaResult.failedItem?.fileName || "media"} `,
              type: "media",
              category: mediaResult.result.category,
              confidence: mediaResult.result.confidence,
              reason: mediaResult.result.reason,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // 不適切なメディアの場合はエラーを返す
            const categoryLabels: Record<string, string> = {
              adult: "成人向けコンテンツ",
              violence: "暴力的なコンテンツ",
              hate: "差別的なコンテンツ",
              dangerous: "危険なコンテンツ",
            };

            const categoryLabel = categoryLabels[mediaResult.result.category] || "不適切なコンテンツ";

            // アップロード済みメディアをStorageから削除
            console.log(`Deleting ${mediaItems.length} uploaded media files due to moderation failure...`);
            for (const item of mediaItems as MediaItem[]) {
              try {
                // URLからStorageパスを抽出して削除
                const url = new URL(item.url);
                const pathMatch = url.pathname.match(/\/o\/(.+?)(\?|$)/);
                if (pathMatch) {
                  const storagePath = decodeURIComponent(pathMatch[1]);
                  await admin.storage().bucket().file(storagePath).delete();
                  console.log(`Deleted: ${storagePath}`);
                }
              } catch (deleteError) {
                console.error(`Failed to delete media: ${item.url}`, deleteError);
              }
            }

            throw new HttpsError(
              "invalid-argument",
              `添付された${mediaResult.failedItem?.type === "video" ? "動画" : "画像"}に${categoryLabel} が含まれている可能性があります。\n\n別のメディアを選択してください。\n\n(徳ポイント: ${virtueResult.newVirtue})`
            );
          }
        }

        console.log("Media moderation passed");
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }
        console.error("Media moderation error:", error);
        // Fail Closed for Media as well
        throw new HttpsError("internal", "メディアの確認中にエラーが発生しました。");
      }
    }

    // ===============================================
    // 3. レート制限チェック
    // ===============================================
    const oneMinuteAgo = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 60000)
    );
    const recentPosts = await db
      .collection("posts")
      .where("userId", "==", userId)
      .where("createdAt", ">", oneMinuteAgo)
      .get();

    if (recentPosts.size >= 5) {
      throw new HttpsError(
        "resource-exhausted",
        "投稿が多すぎるよ！少し待ってからまた投稿してね"
      );
    }

    // ===============================================
    // 4. 投稿を作成
    // ===============================================
    const postRef = db.collection("posts").doc();
    await postRef.set({
      userId: userId,
      userDisplayName: userDisplayName,
      userAvatarIndex: userAvatarIndex,
      content: content,
      mediaItems: mediaItems || [],
      postMode: postMode,
      circleId: circleId || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      reactions: { love: 0, praise: 0, cheer: 0, empathy: 0 },
      commentCount: 0,
      isVisible: true,
      needsReview: needsReview,
      needsReviewReason: needsReviewReason,
    });

    // ADMIN_UIDは上部で定義済み
    if (needsReview) {
      console.log(`Notifying admin about flagged post: ${postRef.id}`);
      try {
        // pendingReviewsコレクションに記録
        await db.collection("pendingReviews").doc(postRef.id).set({
          postId: postRef.id,
          userId: userId,
          reason: needsReviewReason,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          reviewed: false,
        });

        // 全管理者にアプリ内通知を作成
        const adminUids = await getAdminUids();
        const notifyBody = `フラグ付き投稿があります: ${needsReviewReason}`;

        for (const adminUid of adminUids) {
          await db.collection("users").doc(adminUid).collection("notifications").add({
            type: "review_needed",
            title: "要審査投稿",
            body: notifyBody,
            postId: postRef.id,
            fromUserId: userId,
            fromUserName: userDisplayName,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            read: false,
          });
          // プッシュ通知はonNotificationCreatedトリガーで自動送信される
        }
        console.log("Admin notifications created");
      } catch (notifyError) {
        console.error("Failed to notify admin:", notifyError);
        // 通知失敗しても投稿は提出
      }
    }

    // ===============================================
    // 5. Storageメディアのメタデータを更新（postId: PENDING → 実際のpostId）
    // ===============================================
    if (mediaItems && Array.isArray(mediaItems) && mediaItems.length > 0) {
      console.log(`Updating metadata for ${mediaItems.length} media files...`);
      const bucket = admin.storage().bucket();

      for (const item of mediaItems as MediaItem[]) {
        try {
          // URLからStorageパスを抽出
          const url = new URL(item.url);
          const pathMatch = url.pathname.match(/\/o\/(.+?)(\?|$)/);
          if (pathMatch) {
            const storagePath = decodeURIComponent(pathMatch[1]);
            const file = bucket.file(storagePath);

            // メタデータを更新
            await file.setMetadata({
              metadata: {
                postId: postRef.id,
              },
            });
            console.log(`Updated metadata: ${storagePath} → postId=${postRef.id}`);
          }
        } catch (metadataError) {
          console.error(`Failed to update metadata for ${item.url}:`, metadataError);
          // メタデータ更新失敗しても投稿自体は成功扱い
        }
      }
    }

    // ユーザーの投稿数を更新
    await db.collection("users").doc(userId).update({
      totalPosts: admin.firestore.FieldValue.increment(1),
    });

    console.log(`=== createPostWithModeration SUCCESS: postId=${postRef.id} ===`);
    return { success: true, postId: postRef.id };
  }
);




// ===============================================
// 通報機能 → callable/reports.ts に移動
// ===============================================

// ===============================================
// フォロー機能
// ===============================================

/**
 * ユーザーをフォローする
 */
export const followUser = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const currentUserId = request.auth.uid;
    const { targetUserId } = request.data;

    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "フォロー対象のユーザーIDが必要です");
    }

    if (currentUserId === targetUserId) {
      throw new HttpsError("invalid-argument", "自分自身をフォローすることはできません");
    }

    const batch = db.batch();
    const currentUserRef = db.collection("users").doc(currentUserId);
    const targetUserRef = db.collection("users").doc(targetUserId);

    // 対象ユーザーが存在するか確認
    const targetUser = await targetUserRef.get();
    if (!targetUser.exists) {
      throw new HttpsError("not-found", "ユーザーが見つかりません");
    }

    // 現在のユーザーのfollowing配列に追加
    batch.update(currentUserRef, {
      following: admin.firestore.FieldValue.arrayUnion(targetUserId),
      followingCount: admin.firestore.FieldValue.increment(1),
    });

    // 対象ユーザーのfollowers配列に追加
    batch.update(targetUserRef, {
      followers: admin.firestore.FieldValue.arrayUnion(currentUserId),
      followersCount: admin.firestore.FieldValue.increment(1),
    });

    await batch.commit();

    console.log(`User ${currentUserId} followed ${targetUserId} `);

    return { success: true };
  }
);

/**
 * フォローを解除する
 */
export const unfollowUser = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const currentUserId = request.auth.uid;
    const { targetUserId } = request.data;

    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "フォロー解除対象のユーザーIDが必要です");
    }

    const batch = db.batch();
    const currentUserRef = db.collection("users").doc(currentUserId);
    const targetUserRef = db.collection("users").doc(targetUserId);

    // 現在のユーザーのfollowing配列から削除
    batch.update(currentUserRef, {
      following: admin.firestore.FieldValue.arrayRemove(targetUserId),
      followingCount: admin.firestore.FieldValue.increment(-1),
    });

    // 対象ユーザーのfollowers配列から削除
    batch.update(targetUserRef, {
      followers: admin.firestore.FieldValue.arrayRemove(currentUserId),
      followersCount: admin.firestore.FieldValue.increment(-1),
    });

    await batch.commit();

    console.log(`User ${currentUserId} unfollowed ${targetUserId} `);

    return { success: true };
  }
);

/**
 * フォロー状態を取得する
 */
export const getFollowStatus = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const currentUserId = request.auth.uid;
    const { targetUserId } = request.data;

    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "ユーザーIDが必要です");
    }

    const currentUser = await db.collection("users").doc(currentUserId).get();

    if (!currentUser.exists) {
      return { isFollowing: false };
    }

    const following = currentUser.data()?.following || [];
    const isFollowing = following.includes(targetUserId);

    return { isFollowing };
  }
);

/**
 * 徳ポイント履歴を取得
 */
export const getVirtueHistory = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;

    const history = await db
      .collection("virtueHistory")
      .where("userId", "==", userId)
      .orderBy("createdAt", "desc")
      .limit(20)
      .get();

    return {
      history: history.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
        createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
      })),
    };
  }
);

/**
 * 徳ポイントの現在値と設定を取得
 */
export const getVirtueStatus = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const userDoc = await db.collection("users").doc(userId).get();

    if (!userDoc.exists) {
      throw new HttpsError("not-found", "ユーザーが見つかりません");
    }

    const userData = userDoc.data()!;

    return {
      virtue: userData.virtue || VIRTUE_CONFIG.initial,
      isBanned: userData.isBanned || false,
      warningThreshold: VIRTUE_CONFIG.warningThreshold,
      maxVirtue: VIRTUE_CONFIG.initial,
    };
  }
);

// ===============================================
// タスク機能 (callable/tasks.ts に移動)
// - createTask, getTasks
// ===============================================

/**
 * (Trigger) タスクが更新された時の処理
 * - 完了状態になった場合: 徳ポイントとストリークの計算
 */
export const onTaskUpdated = onDocumentUpdated("tasks/{taskId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();

  if (!before || !after) return;

  // 1. 完了状態への変化を検知 (false -> true)
  if (!before.isCompleted && after.isCompleted) {
    const userId = after.userId;

    // ストリーク計算のための前回完了日時取得
    // Firestore上で、このユーザーの直近の完了タスク(自分以外)を取得
    // ※単純化のため、Userドキュメントに持たせるのがベストだが、ここではクエリで頑張るか、
    // あるいはTaskService側でStreakを計算して投げているのを「正」とするか？
    // -> セキュリティ重視ならサーバーで計算すべき。
    // しかしクエリコストが高い。
    // 折衷案: ユーザーデータに `lastTaskCompletedAt` と `currentStreak` を持たせる。

    const userRef = db.collection("users").doc(userId);

    await db.runTransaction(async (transaction) => {
      const userDoc = await transaction.get(userRef);
      if (!userDoc.exists) return; // ユーザーがいない

      const userData = userDoc.data()!;
      const now = new Date();
      const lastCompleted = userData.lastTaskCompletedAt?.toDate();

      let newStreak = 1;
      let streakBonus = 0;

      if (lastCompleted) {
        // 日付の差分計算 (JST考慮が必要だが、UTCベースの日付差分で簡易判定)
        // 厳密には「営業日」的なロジックが必要だが、24時間以内かどうか等で判定
        const diffTime = now.getTime() - lastCompleted.getTime();
        const diffDays = diffTime / (1000 * 3600 * 24);

        if (diffDays < 1.5 && now.getDate() !== lastCompleted.getDate()) {
          // "昨日"完了している（大体36時間以内かつ日付が違う）
          // ※もっと厳密なロジックは必要だが、一旦簡易実装
          newStreak = (userData.currentStreak || 0) + 1;
        } else if (now.getDate() === lastCompleted.getDate()) {
          // 今日すでに完了している -> ストリーク維持
          newStreak = userData.currentStreak || 1;
        } else {
          // 途切れた
          newStreak = 1;
        }
      }

      // ポイント計算
      const baseVirtue = 2;
      streakBonus = Math.min(newStreak - 1, 5);
      const virtueGain = baseVirtue + streakBonus;

      // User更新
      transaction.update(userRef, {
        virtue: admin.firestore.FieldValue.increment(virtueGain),
        currentStreak: newStreak,
        lastTaskCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 履歴記録
      const historyRef = db.collection("virtueHistory").doc();
      transaction.set(historyRef, {
        userId: userId,
        change: virtueGain,
        reason: `タスク完了: ${after.content} ${newStreak > 1 ? `(${newStreak}連!)` : ''}`,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // タスク自体のStreak値も更新しておく（事後更新になるが結果整合性）
      // ※トリガー内で自身のドキュメントを更新すると無限ループのリスクがあるため注意。
      // ここでは `streak` が変化した場合のみ...だが、今回はやめておく。
      // アプリ側で表示用Streakは計算済みのはず。
    });
  }

  // 2. 完了取り消し (true -> false)
  if (before.isCompleted && !after.isCompleted) {
    // ポイント減算
    const userId = after.userId;
    // 減算ロジックは複雑（どのボーナス分だったか不明）なので、一律 -2 とする、等の運用が一般的
    // ここでは簡易的に Base + StreakBonus(Userの現在値から推測) を引く

    await db.runTransaction(async (transaction) => {
      const userRef = db.collection("users").doc(userId);
      transaction.update(userRef, {
        virtue: admin.firestore.FieldValue.increment(-2), // 最低限引く
      });

      // 履歴
      const historyRef = db.collection("virtueHistory").doc();
      transaction.set(historyRef, {
        userId: userId,
        change: -2,
        reason: `タスク完了取消: ${after.content}`,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  }
});



// ===============================================
// 名前パーツ方式 → callable/names.ts に移動
// ===============================================

// ===============================================
// プッシュ通知
// ===============================================

/**
 * プッシュ通知を送信
 */
async function sendPushNotification(
  userId: string,
  title: string,
  body: string,
  data: { [key: string]: string } = {},
  options?: {
    type: "comment" | "reaction" | "system";
    senderId: string;
    senderName: string;
    senderAvatarUrl?: string; // アイコンURLまたはインデックス
  }
) {
  try {
    // 1. Firestoreに通知ドキュメントを保存 (オプション指定時)
    if (options) {
      await db.collection("users").doc(userId).collection("notifications").add({
        userId: userId,
        senderId: options.senderId,
        senderName: options.senderName,
        senderAvatarUrl: options.senderAvatarUrl || "",
        type: options.type,
        title: title,
        body: body,
        postId: data.postId || null,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`Notification saved to Firestore for user: ${userId}`);
    }

    // 2. FCMトークン取得
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      console.log(`User not found: ${userId} `);
      return;
    }

    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;

    if (!fcmToken) {
      console.log(`No FCM token for user: ${userId} `);
      return;
    }

    // 2.5 通知設定の確認
    if (options && userData?.notificationSettings) {
      const type = options.type;
      // 設定キーへのマッピング (comment -> comments, reaction -> reactions)
      const settingKey = type === "comment" ? "comments" : type === "reaction" ? "reactions" : null;

      if (settingKey && userData.notificationSettings[settingKey] === false) {
        console.log(`Notification skipped due to user setting: ${type} for user ${userId}`);
        return;
      }
    }

    // 3. FCM送信
    // dataにはtype, postId等を含める（クライアントの通知タップ時ナビゲーション用）
    const fcmData: { [key: string]: string } = {
      ...data,
    };
    if (options?.type) {
      fcmData.type = options.type;
    }

    const message = {
      token: fcmToken,
      notification: {
        title,
        body,
      },
      data: fcmData,
      android: {
        priority: "high" as const,
        notification: {
          sound: "default",
          channelId: "default_channel",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    await admin.messaging().send(message);
    console.log(`Push notification sent to ${userId}: ${title} `);
  } catch (error) {
    console.error(`Failed to send push notification to ${userId}: `, error);
  }
}

/**
 * コメント作成時に投稿者へ通知
 */
export const onCommentCreatedNotify = onDocumentCreated(
  {
    document: "comments/{commentId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const commentData = snap.data();
    const postId = commentData.postId;
    const commenterName = commentData.userDisplayName;
    const commenterId = commentData.userId;
    // AIかどうかに関わらず通知（コンセプト: AIと人間の区別をつけない）

    // 投稿を取得
    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists) return;

    const postData = postDoc.data();
    const postOwnerId = postData?.userId;

    // 自分へのコメントは通知しない
    console.log(`Comment Notification Check: postOwner = ${postOwnerId}, commenter = ${commenterId} `);

    // 文字列として確実に比較（空白除去なども念のため）
    if (String(postOwnerId).trim() === String(commenterId).trim()) {
      console.log("Skipping self-comment notification");
      return;
    }

    // 未来の投稿（AIの予約投稿）の場合は通知しない
    // Note: クライアント側で表示される時間になったら通知を送る仕組みが必要（現在はCronジョブ等がないためスキップのみ）
    if (commentData.scheduledAt) {
      const scheduledAt = commentData.scheduledAt.toDate();
      const now = new Date();
      if (scheduledAt > now) {
        console.log(`Skipping notification for scheduled comment(scheduledAt: ${scheduledAt.toISOString()})`);
        return;
      }
    }

    // 通知を送信
    await sendPushNotification(
      postOwnerId,
      "コメント",
      `${commenterName}さんがコメントしました`,
      { postId },
      {
        type: "comment",
        senderId: commenterId,
        senderName: commenterName,
        senderAvatarUrl: String(commentData.userAvatarIndex ?? ""), // アバターインデックスを文字列として保存
      }
    );
  }
);

/**
 * リアクション追加時に投稿者へ通知
 */
export const onReactionAddedNotify = onDocumentCreated(
  {
    document: "reactions/{reactionId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const reactionData = snap.data();
    const postId = reactionData.postId;
    const reactorId = reactionData.userId;
    const reactorName = reactionData.userDisplayName || "誰か";

    // 投稿を取得
    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists) return;

    const postData = postDoc.data();
    const postOwnerId = postData?.userId;

    // 自分へのリアクションは通知しない
    if (postOwnerId === reactorId) {
      console.log("Skipping self-reaction notification");
      return;
    }

    // 通知を送信
    await sendPushNotification(
      postOwnerId,
      "リアクション",
      `${reactorName}さんがリアクションしました`,
      { postId },
      {
        type: "reaction",
        senderId: reactorId,
        senderName: reactorName,
        senderAvatarUrl: "", // リアクションはアバターURLを持たないので空（クライアント側で適宜処理）
      }
    );
  }
);

/**
 * Cloud Tasks から呼び出される AI コメント生成関数 (v1)
 * v1を使用することでURLを固定化: https://asia-northeast1-positive-sns.cloudfunctions.net/generateAICommentV1
 */
// Imports removed as they are already in scope or invalid

export const generateAICommentV1 = functionsV1.region("asia-northeast1").runWith({
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
  const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

  const prompt = `
あなたはSNSのコミュニティマネージャーです。以下のテキストが、ポジティブで優しいSNS「ほめっぷ」にふさわしいかどうか（攻撃的、誹謗中傷、不適切でないか）を判定してください。
文脈として、ユーザーは「投稿内容」に対して「コメント」をしようとしています。
たとえ一見普通の言葉でも、文脈によって嫌味や攻撃になる場合はネガティブと判定してください。
特に「死ね」「殺す」「きもい」などの直接的な暴言・攻撃は厳しく判定してください。

【投稿内容】
"${postContent}"

【コメントしようとしている内容】
"${text}"

以下のJSON形式のみで回答してください:
{
  "isNegative": boolean, // ネガティブ（不適切）ならtrue
  "category": "harassment" | "hate_speech" | "profanity" | "self_harm" | "spam" | "none",
  "confidence": number, // 0.0〜1.0 (確信度)
  "reason": "判定理由（ユーザーに簡潔に伝える用）",
  "suggestion": "より優しい言い方の提案（もしあれば）"
}
`;

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
    region: "asia-northeast1",
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
export const generateAIReactionV1 = functionsV1.region("asia-northeast1").https.onRequest(async (request, response) => {
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

/**
 * 管理用: 全ユーザーのフォローリストを掃除する
 * 存在しないユーザーIDをフォローリストから削除し、カウントを整合させます。
 */
export const cleanUpUserFollows = onCall(
  { region: "asia-northeast1", timeoutSeconds: 540 },
  async (request) => {
    // 認証チェック
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    // 管理者チェック
    const userIsAdmin = await isAdmin(request.auth.uid);
    if (!userIsAdmin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    try {
      const usersSnapshot = await db.collection("users").get();
      let updatedCount = 0;

      for (const userDoc of usersSnapshot.docs) {
        const userData = userDoc.data();
        const following = userData.following || [];

        if (following.length === 0) continue;

        // フォロー中のIDが本当に存在するかチェック
        const validFollowing: string[] = [];
        const invalidFollowing: string[] = [];

        for (const followedId of following) {
          // 簡易チェック: IDにスペースが含まれていたら不正なので削除
          if (followedId.trim() !== followedId) {
            invalidFollowing.push(followedId);
            continue;
          }

          // Firestore確認 (コストかかるが確実)
          const followedUserDoc = await db.collection("users").doc(followedId).get();
          if (followedUserDoc.exists) {
            validFollowing.push(followedId);
          } else {
            invalidFollowing.push(followedId);
          }
        }

        // 変更がある場合のみ更新
        if (invalidFollowing.length > 0) {
          await userDoc.ref.update({
            following: validFollowing,
            followingCount: validFollowing.length
          });
          updatedCount++;
          console.log(`Cleaned up user ${userDoc.id}: Removed ${invalidFollowing.length} invalid follows.`);
        }
      }

      console.log(`cleanUpUserFollows completed by admin ${request.auth.uid}. Updated ${updatedCount} users.`);
      return { success: true, updatedCount, message: `${updatedCount}件のユーザーを更新しました` };

    } catch (error) {
      console.error("Error cleaning up follows:", error);
      throw new HttpsError("internal", "処理中にエラーが発生しました");
    }
  }
);

/**
 * 管理用: 全てのAIユーザーを削除する (v1)
 * AIユーザーとその投稿、コメント、リアクションを全て削除します。
 */
export const deleteAllAIUsers = functionsV1.region("asia-northeast1").runWith({
  timeoutSeconds: 540, // 処理が重くなる可能性があるので長めに
  memory: "1GB"
}).https.onCall(async (data, context) => {
  // セキュリティ: ログイン必須
  if (!context.auth) {
    throw new functionsV1.https.HttpsError("unauthenticated", "ログインが必要です");
  }

  // セキュリティ: 管理者権限チェック
  const userIsAdmin = await isAdmin(context.auth.uid);
  if (!userIsAdmin) {
    throw new functionsV1.https.HttpsError("permission-denied", "管理者権限が必要です");
  }

  try {
    console.log("Starting deletion of all AI users...");
    const batchSize = 400;
    let batch = db.batch();
    let operationCount = 0;

    // 1. AIユーザーを取得
    const aiUsersSnapshot = await db.collection("users").where("isAI", "==", true).get();
    console.log(`Found ${aiUsersSnapshot.size} AI users to delete.`);

    if (aiUsersSnapshot.empty) {
      return { success: true, message: "AIユーザーはいませんでした" };
    }

    const aiUserIds = aiUsersSnapshot.docs.map(doc => doc.id);

    // バッチコミット用ヘルパー
    const commitBatchIfNeeded = async () => {
      if (operationCount >= batchSize) {
        await batch.commit();
        batch = db.batch();
        operationCount = 0;
      }
    };

    // 2. 関連データの削除 (Posts, Comments, Reactions)
    // Helper to process deletion in chunks
    const deleteCollectionByUserId = async (collectionName: string) => {
      // 10人ずつ処理
      const chunkSize = 10;
      for (let i = 0; i < aiUserIds.length; i += chunkSize) {
        const chunk = aiUserIds.slice(i, i + chunkSize);
        const snapshot = await db.collection(collectionName).where("userId", "in", chunk).get();

        for (const doc of snapshot.docs) {
          batch.delete(doc.ref);
          operationCount++;
          await commitBatchIfNeeded();
        }
      }
    };

    console.log("Deleting AI posts...");
    await deleteCollectionByUserId("posts");

    console.log("Deleting AI comments...");
    await deleteCollectionByUserId("comments");

    console.log("Deleting AI reactions...");
    await deleteCollectionByUserId("reactions");

    // 3. ユーザー自身の削除（サブコレクション 'notifications' も含めて）
    console.log("Deleting AI user profiles and subcollections...");
    for (const doc of aiUsersSnapshot.docs) {
      // notificationsサブコレクションを削除
      const notificationsSnapshot = await doc.ref.collection("notifications").get();
      for (const notifDoc of notificationsSnapshot.docs) {
        batch.delete(notifDoc.ref);
        operationCount++;
        await commitBatchIfNeeded();
      }

      batch.delete(doc.ref);
      operationCount++;
      await commitBatchIfNeeded();
    }

    // 残りのバッチを実行
    if (operationCount > 0) {
      await batch.commit();
    }

    console.log("Successfully deleted all AI data.");
    return { success: true, message: `AIユーザー${aiUsersSnapshot.size}人とそのデータを削除しました` };

  } catch (error) {
    console.error("Error deleting AI users:", error);
    throw new functionsV1.https.HttpsError("internal", "削除処理中にエラーが発生しました");
  }
});

/**
 * 孤児サークルAI（サブコレクションのみ残っている状態）を一括削除
 */
export const cleanupOrphanedCircleAIs = onCall(
  { region: "asia-northeast1", timeoutSeconds: 300 },
  async (request) => {
    // セキュリティ: 管理者権限チェック
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const userIsAdmin = await isAdmin(request.auth.uid);
    if (!userIsAdmin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    console.log("=== cleanupOrphanedCircleAIs START ===");

    // circle_ai_で始まるユーザーを全て取得
    const circleAIsSnapshot = await db.collection("users")
      .where("__name__", ">=", "circle_ai_")
      .where("__name__", "<", "circle_ai_\uf8ff")
      .get();

    let deletedCount = 0;
    let notificationCount = 0;

    for (const doc of circleAIsSnapshot.docs) {
      const userId = doc.id;
      const userRef = db.collection("users").doc(userId);

      // サブコレクション（notifications）を削除
      const notificationsSnapshot = await userRef.collection("notifications").get();
      if (!notificationsSnapshot.empty) {
        const batch = db.batch();
        notificationsSnapshot.docs.forEach(notifDoc => batch.delete(notifDoc.ref));
        await batch.commit();
        notificationCount += notificationsSnapshot.size;
      }

      // ユーザードキュメント本体を削除
      await userRef.delete();
      deletedCount++;
      console.log(`Deleted circle AI: ${userId}`);
    }

    console.log(`=== cleanupOrphanedCircleAIs COMPLETE: ${deletedCount} users, ${notificationCount} notifications ===`);
    return {
      success: true,
      message: `孤児サークルAIを${deletedCount}件削除しました（通知${notificationCount}件）`,
      deletedUsers: deletedCount,
      deletedNotifications: notificationCount,
    };
  }
);


/**
 * Cloud Tasks から呼び出される AI 投稿生成関数 (Worker)
 */
export const executeAIPostGeneration = functionsV1.region("asia-northeast1").runWith({
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
    const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

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
    const prompt = `
${getSystemPrompt(persona, "みんな")}

【指示】
あなたは「ホームップ」というSNSのユーザー「${persona.name}」です。
職業は「${persona.occupation.name}」、性格は「${persona.personality.name}」です。

今の時間帯（${hours}時頃）に合わせた、自然な「つぶやき」を投稿してください。
テーマは「今日頑張ったこと」「小さな達成」「日常の努力」「ふとした気づき」などです。
ポジティブで、他のユーザーが見て「頑張ってるな」と思えるような内容にしてください。

【条件】
- ネガティブな発言禁止
- 誹謗中傷禁止
- ハッシュタグ不要
- 絵文字を適度に使用して人間らしく
- 文章は短め〜中くらい（30文字〜80文字程度）

【例】
- 「今日は早起きして朝活できた！気持ちいい✨」
- 「仕事の資料、期限内に終わった〜！自分へのご褒美にコンビニスイーツ買う🍰」
- 「今日は疲れたけど、筋トレだけは欠かさずやった💪 えらい！」
`;

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
  { document: "tasks/{taskId}", region: "asia-northeast1" },
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
  { document: "tasks/{taskId}", region: "asia-northeast1" },
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
export const executeTaskReminder = functionsV1.region("asia-northeast1").runWith({
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
  { secrets: [geminiApiKey], region: "asia-northeast1" },
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
      const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash-exp" });

      const prompt = `
この画像がSNSへの投稿として適切かどうか判定してください。

【ブロック対象（isInappropriate: true）】
- adult: 成人向けコンテンツ、露出の多い画像、性的な内容
- violence: 暴力的な画像、血液、怪我、残虐な内容
- hate: ヘイトシンボル、差別的な画像
- dangerous: 危険な行為、違法行為、武器

【許可する内容（isInappropriate: false）】
- 通常の人物写真（水着でも一般的なものはOK）
- 風景、食べ物、ペット
- 趣味の写真
- 芸術作品（明らかにアダルトでない限り）

【回答形式】
必ず以下のJSON形式のみで回答してください：
{
  "isInappropriate": true または false,
  "category": "adult" | "violence" | "hate" | "dangerous" | "none",
  "confidence": 0から1の数値,
  "reason": "判定理由"
}
`;

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

/**
 * 孤立メディアクリーンアップ
 * Cloud Schedulerで毎日実行
 * 24時間以上経過した孤立メディアを削除
 */
export const cleanupOrphanedMedia = onSchedule(
  {
    schedule: "0 3 * * *", // 毎日午前3時 JST
    timeZone: "Asia/Tokyo",
    region: "asia-northeast1",
    timeoutSeconds: 600, // 10分タイムアウト
  },
  async () => {
    console.log("=== cleanupOrphanedMedia START ===");
    const bucket = admin.storage().bucket();
    const now = Date.now();
    const TWENTY_FOUR_HOURS = 24 * 60 * 60 * 1000;

    let deletedCount = 0;
    let checkedCount = 0;

    // ===============================================
    // 1. 投稿メディアのクリーンアップ
    // ===============================================
    console.log("Checking posts media...");
    const [postFiles] = await bucket.getFiles({ prefix: "posts/" });

    for (const file of postFiles) {
      checkedCount++;
      try {
        const [metadata] = await file.getMetadata();
        const customMetadata = metadata.metadata || {};
        const uploadedAtStr = customMetadata.uploadedAt;
        const uploadedAt = uploadedAtStr ? parseInt(String(uploadedAtStr)) : 0;
        const postId = customMetadata.postId ? String(customMetadata.postId) : null;

        // 24時間以上経過していないならスキップ
        if (now - uploadedAt < TWENTY_FOUR_HOURS) continue;

        // postId未設定（古いファイル）はスキップ
        if (!postId) continue;

        let shouldDelete = false;

        if (postId === "PENDING") {
          // 投稿前に離脱したケース
          shouldDelete = true;
          console.log(`Orphan (PENDING): ${file.name}`);
        } else {
          // 投稿が存在するか確認
          const postDoc = await db.collection("posts").doc(postId).get();
          if (!postDoc.exists) {
            shouldDelete = true;
            console.log(`Orphan (post deleted): ${file.name}`);
          }
        }

        if (shouldDelete) {
          await file.delete();
          deletedCount++;
        }
      } catch (error) {
        console.error(`Error checking ${file.name}:`, error);
      }
    }

    // ===============================================
    // 2. サークル画像のクリーンアップ
    // ===============================================
    console.log("Checking circles media...");
    const [circleFiles] = await bucket.getFiles({ prefix: "circles/" });

    for (const file of circleFiles) {
      checkedCount++;
      try {
        const [metadata] = await file.getMetadata();
        const timeCreated = metadata.timeCreated;
        const createdAt = timeCreated ? new Date(timeCreated).getTime() : 0;

        // 24時間以上経過していないならスキップ
        if (now - createdAt < TWENTY_FOUR_HOURS) continue;

        // パスからcircleIdを抽出: circles/{circleId}/icon/{fileName}
        const pathParts = file.name.split("/");
        if (pathParts.length >= 2) {
          const circleId = pathParts[1];
          const circleDoc = await db.collection("circles").doc(circleId).get();

          if (!circleDoc.exists) {
            console.log(`Orphan (circle deleted): ${file.name}`);
            await file.delete();
            deletedCount++;
          }
        }
      } catch (error) {
        console.error(`Error checking ${file.name}:`, error);
      }
    }

    // ===============================================
    // 3. タスク添付のクリーンアップ
    // ===============================================
    console.log("Checking task attachments...");
    const [taskFiles] = await bucket.getFiles({ prefix: "task_attachments/" });

    for (const file of taskFiles) {
      checkedCount++;
      try {
        const [metadata] = await file.getMetadata();
        const taskTimeCreated = metadata.timeCreated;
        const taskCreatedAt = taskTimeCreated ? new Date(taskTimeCreated).getTime() : 0;

        // 24時間以上経過していないならスキップ
        if (now - taskCreatedAt < TWENTY_FOUR_HOURS) continue;

        // パスからtaskIdを抽出: task_attachments/{userId}/{taskId}/{fileName}
        const pathParts = file.name.split("/");
        if (pathParts.length >= 3) {
          const taskId = pathParts[2];
          const taskDoc = await db.collection("tasks").doc(taskId).get();

          if (!taskDoc.exists) {
            console.log(`Orphan (task deleted): ${file.name}`);
            await file.delete();
            deletedCount++;
          }
        }
      } catch (error) {
        console.error(`Error checking ${file.name}:`, error);
      }
    }

    // ===============================================
    // 4. 孤立サークル投稿のクリーンアップ（Firestore）
    // サークルが存在しない投稿を削除
    // ===============================================
    console.log("Checking orphaned circle posts...");
    let orphanedPostsDeleted = 0;

    // circleIdがnullでない投稿を取得（サークル投稿のみ）
    const circlePostsSnapshot = await db.collection("posts")
      .where("circleId", "!=", null)
      .limit(500) // バッチサイズ制限
      .get();

    // サークルの存在を確認するためのキャッシュ
    const circleExistsCache: Map<string, boolean> = new Map();

    for (const postDoc of circlePostsSnapshot.docs) {
      try {
        const postData = postDoc.data();
        const circleId = postData.circleId;

        if (!circleId) continue;

        // キャッシュを確認
        let circleExists = circleExistsCache.get(circleId);
        if (circleExists === undefined) {
          const circleDoc = await db.collection("circles").doc(circleId).get();
          circleExists = circleDoc.exists;
          circleExistsCache.set(circleId, circleExists);
        }

        if (!circleExists) {
          console.log(`Orphaned circle post found: ${postDoc.id} (circleId: ${circleId})`);

          // 関連データを削除
          const deleteRefs: FirebaseFirestore.DocumentReference[] = [];

          // コメント削除
          const comments = await db.collection("comments").where("postId", "==", postDoc.id).get();
          comments.docs.forEach((c) => deleteRefs.push(c.ref));

          // リアクション削除
          const reactions = await db.collection("reactions").where("postId", "==", postDoc.id).get();
          reactions.docs.forEach((r) => deleteRefs.push(r.ref));

          // 投稿自体を削除
          deleteRefs.push(postDoc.ref);

          // バッチ削除
          const batch = db.batch();
          deleteRefs.forEach((ref) => batch.delete(ref));
          await batch.commit();

          // メディアも削除
          const mediaItems = postData.mediaItems || [];
          for (const media of mediaItems) {
            if (media.url && media.url.includes("firebasestorage.googleapis.com")) {
              try {
                const urlParts = media.url.split("/o/")[1];
                if (urlParts) {
                  const filePath = decodeURIComponent(urlParts.split("?")[0]);
                  await bucket.file(filePath).delete().catch(() => { });
                }
              } catch (e) {
                console.error(`Media delete failed:`, e);
              }
            }
          }

          orphanedPostsDeleted++;
        }
      } catch (error) {
        console.error(`Error checking post ${postDoc.id}:`, error);
      }
    }

    // ===============================================
    // 5. 孤立コメントのクリーンアップ（Firestore）
    // 存在しない投稿に紐づくコメントを削除
    // ===============================================
    console.log("Checking orphaned comments...");
    let orphanedCommentsDeleted = 0;

    const commentsSnapshot = await db.collection("comments")
      .limit(1000)
      .get();

    // 投稿の存在を確認するためのキャッシュ
    const postExistsCache: Map<string, boolean> = new Map();

    for (const commentDoc of commentsSnapshot.docs) {
      try {
        const commentData = commentDoc.data();
        const postId = commentData.postId;

        if (!postId) continue;

        let postExists = postExistsCache.get(postId);
        if (postExists === undefined) {
          const postDoc = await db.collection("posts").doc(postId).get();
          postExists = postDoc.exists;
          postExistsCache.set(postId, postExists);
        }

        if (!postExists) {
          console.log(`Orphaned comment found: ${commentDoc.id} (postId: ${postId})`);
          await commentDoc.ref.delete();
          orphanedCommentsDeleted++;
        }
      } catch (error) {
        console.error(`Error checking comment ${commentDoc.id}:`, error);
      }
    }

    // ===============================================
    // 6. 孤立リアクションのクリーンアップ（Firestore）
    // 存在しない投稿に紐づくリアクションを削除
    // ===============================================
    console.log("Checking orphaned reactions...");
    let orphanedReactionsDeleted = 0;

    const reactionsSnapshot = await db.collection("reactions")
      .limit(1000)
      .get();

    for (const reactionDoc of reactionsSnapshot.docs) {
      try {
        const reactionData = reactionDoc.data();
        const postId = reactionData.postId;

        if (!postId) continue;

        let postExists = postExistsCache.get(postId);
        if (postExists === undefined) {
          const postDoc = await db.collection("posts").doc(postId).get();
          postExists = postDoc.exists;
          postExistsCache.set(postId, postExists);
        }

        if (!postExists) {
          console.log(`Orphaned reaction found: ${reactionDoc.id} (postId: ${postId})`);
          await reactionDoc.ref.delete();
          orphanedReactionsDeleted++;
        }
      } catch (error) {
        console.error(`Error checking reaction ${reactionDoc.id}:`, error);
      }
    }

    // サークルAI投稿履歴のクリーンアップ（2日以上前の履歴を削除）
    const twoDaysAgo = new Date();
    twoDaysAgo.setDate(twoDaysAgo.getDate() - 2);
    const twoDaysAgoStr = twoDaysAgo.toISOString().split("T")[0];

    const oldHistorySnapshot = await db.collection("circleAIPostHistory")
      .where("date", "<", twoDaysAgoStr)
      .get();

    let historyDeleted = 0;
    for (const doc of oldHistorySnapshot.docs) {
      await doc.ref.delete();
      historyDeleted++;
    }
    if (historyDeleted > 0) {
      console.log(`Deleted ${historyDeleted} old circleAIPostHistory documents`);
    }

    // AI投稿履歴のクリーンアップ（2日以上前の履歴を削除）
    const oldAIHistorySnapshot = await db.collection("aiPostHistory")
      .where("date", "<", twoDaysAgoStr)
      .get();

    let aiHistoryDeleted = 0;
    for (const doc of oldAIHistorySnapshot.docs) {
      await doc.ref.delete();
      aiHistoryDeleted++;
    }
    if (aiHistoryDeleted > 0) {
      console.log(`Deleted ${aiHistoryDeleted} old aiPostHistory documents`);
    }

    console.log(`=== cleanupOrphanedMedia COMPLETE: checked=${checkedCount}, deleted=${deletedCount}, orphanedPosts=${orphanedPostsDeleted}, orphanedComments=${orphanedCommentsDeleted}, orphanedReactions=${orphanedReactionsDeleted} ===`);
  }
);

// ============================================================
// 目標リマインダー通知機能
// ============================================================

/**
 * 目標リマインダー用時刻計算（期限から逆算）
 */
function calculateGoalReminderTime(deadline: Date, reminder: { unit: string; value: number }): Date {
  const ms = deadline.getTime();
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
 * 目標リマインダー実行エンドポイント
 */
export const executeGoalReminder = onRequest(
  { region: "asia-northeast1" },
  async (req, res) => {
    // 認証チェック（Cloud Tasksからのみ呼び出し可能）
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).send("Unauthorized");
      return;
    }

    try {
      const { goalId, userId, goalTitle, timeLabel, reminderKey, type } = req.body;

      if (!goalId || !userId) {
        res.status(400).send("Missing required fields");
        return;
      }

      // 重複チェック
      const sentKey = `goal_${goalId}_${type}_${reminderKey}`;
      const sentDoc = await db.collection("sentReminders").doc(sentKey).get();
      if (sentDoc.exists) {
        console.log(`[GoalReminder] Already sent: ${sentKey}`);
        res.status(200).send("Already sent");
        return;
      }

      // 目標がまだ存在し、未完了か確認
      const goalDoc = await db.collection("goals").doc(goalId).get();
      if (!goalDoc.exists) {
        console.log(`[GoalReminder] Goal ${goalId} no longer exists`);
        res.status(200).send("Goal deleted");
        return;
      }

      const goalData = goalDoc.data();
      if (goalData?.completedAt) {
        console.log(`[GoalReminder] Goal ${goalId} is already completed`);
        res.status(200).send("Goal completed");
        return;
      }

      // ユーザーのFCMトークン取得
      const userDoc = await db.collection("users").doc(userId).get();
      if (!userDoc.exists) {
        console.log(`[GoalReminder] User ${userId} not found`);
        res.status(200).send("User not found");
        return;
      }

      const fcmToken = userDoc.data()?.fcmToken;
      if (!fcmToken) {
        console.log(`[GoalReminder] User ${userId} has no FCM token`);
        res.status(200).send("No FCM token");
        return;
      }

      // 通知タイトル・本文
      const isDeadline = type === "goal_deadline";
      const title = isDeadline ? "🚩 目標の期限です！" : "🚩 目標リマインダー";
      const body = isDeadline
        ? `「${goalTitle}」の期限になりました。達成状況を確認しましょう！`
        : `「${goalTitle}」の期限まで${timeLabel}です`;

      // FCM送信
      await admin.messaging().send({
        token: fcmToken,
        notification: { title, body },
        data: {
          type: "goal_reminder",
          goalId,
        },
        android: {
          priority: "high",
          notification: {
            channelId: "reminders",
            priority: "high",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      });

      // 送信済みとして記録
      await db.collection("sentReminders").doc(sentKey).set({
        goalId,
        userId,
        type,
        reminderKey,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`[GoalReminder] Sent: ${goalId} - ${timeLabel}`);
      res.status(200).send("OK");
    } catch (error) {
      console.error("[GoalReminder] Error:", error);
      res.status(500).send("Error");
    }
  }
);

/**
 * 目標作成時にリマインダーをスケジュール
 */
export const scheduleGoalRemindersOnCreate = onDocumentCreated(
  { document: "goals/{goalId}", region: "asia-northeast1" },
  async (event) => {
    const goalId = event.params.goalId;
    const data = event.data?.data();

    if (!data) return;

    // 完了済みは無視
    if (data.completedAt) return;

    const deadline = (data.deadline as admin.firestore.Timestamp)?.toDate();
    if (!deadline) {
      console.log(`[GoalReminder] Goal ${goalId} has no deadline`);
      return;
    }

    const userId = data.userId as string;
    const goalTitle = (data.title as string) || "目標";
    const reminders = data.reminders as Array<{ unit: string; value: number }> | undefined;

    if (!reminders || reminders.length === 0) {
      console.log(`[GoalReminder] Goal ${goalId} has no reminders`);
      return;
    }

    console.log(`[GoalReminder] Scheduling reminders for new goal ${goalId}`);

    const tasksClient = new CloudTasksClient();
    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    const location = LOCATION;

    const queuePath = tasksClient.queuePath(project, location, TASK_REMINDER_QUEUE);
    const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeGoalReminder`;
    const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

    const now = new Date();

    for (const reminder of reminders) {
      const reminderTime = calculateGoalReminderTime(deadline, reminder);

      if (reminderTime <= now) {
        console.log(`[GoalReminder] Skipping past reminder: ${reminderTime.toISOString()}`);
        continue;
      }

      const reminderKey = `${reminder.unit}_${reminder.value}`;
      const timeLabel = reminder.unit === "minutes"
        ? `${reminder.value}分`
        : reminder.unit === "hours"
          ? `${reminder.value}時間`
          : `${reminder.value}日`;

      const payload = {
        goalId,
        userId,
        goalTitle,
        timeLabel,
        reminderKey,
        type: "goal_reminder",
      };

      const task = {
        httpRequest: {
          httpMethod: "POST" as const,
          url: targetUrl,
          headers: { "Content-Type": "application/json" },
          body: Buffer.from(JSON.stringify(payload)).toString("base64"),
          oidcToken: {
            serviceAccountEmail,
            audience: targetUrl,
          },
        },
        scheduleTime: {
          seconds: Math.floor(reminderTime.getTime() / 1000),
        },
      };

      try {
        const [response] = await tasksClient.createTask({ parent: queuePath, task });
        console.log(`[GoalReminder] Created task: ${response.name}`);

        // scheduledRemindersに記録
        await db.collection("scheduledReminders").add({
          goalId,
          reminderKey,
          type: "goal_reminder",
          scheduledFor: reminderTime,
          cloudTaskName: response.name,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (e) {
        console.error(`[GoalReminder] Failed to create task:`, e);
      }
    }

    // 2. 期限時刻通知（期限ちょうど）
    if (deadline > now) {
      const deadlinePayload = {
        goalId,
        userId,
        goalTitle,
        timeLabel: "期限",
        reminderKey: "deadline",
        type: "goal_deadline",
      };

      const deadlineTask = {
        httpRequest: {
          httpMethod: "POST" as const,
          url: targetUrl,
          headers: { "Content-Type": "application/json" },
          body: Buffer.from(JSON.stringify(deadlinePayload)).toString("base64"),
          oidcToken: {
            serviceAccountEmail,
            audience: targetUrl,
          },
        },
        scheduleTime: {
          seconds: Math.floor(deadline.getTime() / 1000),
        },
      };

      try {
        const [response] = await tasksClient.createTask({ parent: queuePath, task: deadlineTask });
        console.log(`[GoalReminder] Created deadline task: ${response.name}`);

        await db.collection("scheduledReminders").add({
          goalId,
          reminderKey: "deadline",
          type: "goal_deadline",
          scheduledFor: deadline,
          cloudTaskName: response.name,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (e) {
        console.error(`[GoalReminder] Failed to create deadline task:`, e);
      }
    }
  }
);

/**
 * 目標更新時にリマインダーを再スケジュール
 */
export const scheduleGoalReminders = onDocumentUpdated(
  { document: "goals/{goalId}", region: "asia-northeast1" },
  async (event) => {
    const goalId = event.params.goalId;
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();

    if (!afterData) return;

    // 完了した目標は無視
    if (afterData.completedAt) {
      console.log(`[GoalReminder] Goal ${goalId} is completed, skipping`);
      return;
    }

    const deadline = (afterData.deadline as admin.firestore.Timestamp)?.toDate();
    if (!deadline) {
      console.log(`[GoalReminder] Goal ${goalId} has no deadline`);
      return;
    }

    // 期限またはリマインダーが変更されたか確認
    const beforeDeadline = (beforeData?.deadline as admin.firestore.Timestamp)?.toDate();
    const beforeReminders = JSON.stringify(beforeData?.reminders || []);
    const afterReminders = JSON.stringify(afterData.reminders || []);

    if (
      beforeDeadline?.getTime() === deadline.getTime() &&
      beforeReminders === afterReminders
    ) {
      console.log(`[GoalReminder] Goal ${goalId} schedule unchanged`);
      return;
    }

    const userId = afterData.userId as string;
    const goalTitle = (afterData.title as string) || "目標";
    const reminders = afterData.reminders as Array<{ unit: string; value: number }> | undefined;

    console.log(`[GoalReminder] Rescheduling reminders for goal ${goalId}`);

    const tasksClient = new CloudTasksClient();
    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    const location = LOCATION;

    // 既存のリマインダータスクをキャンセル
    const existingReminders = await db.collection("scheduledReminders")
      .where("goalId", "==", goalId)
      .get();

    const batch = db.batch();
    for (const doc of existingReminders.docs) {
      const taskName = doc.data().cloudTaskName;
      if (taskName) {
        try {
          await tasksClient.deleteTask({ name: taskName });
          console.log(`[GoalReminder] Cancelled task: ${taskName}`);
        } catch (e) {
          console.log(`[GoalReminder] Task already gone: ${taskName}`);
        }
      }
      batch.delete(doc.ref);
    }
    await batch.commit();

    if (!reminders || reminders.length === 0) {
      console.log(`[GoalReminder] Goal ${goalId} has no reminders after update`);
      return;
    }

    // 新しいリマインダーをスケジュール
    const queuePath = tasksClient.queuePath(project, location, TASK_REMINDER_QUEUE);
    const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeGoalReminder`;
    const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

    const now = new Date();

    for (const reminder of reminders) {
      const reminderTime = calculateGoalReminderTime(deadline, reminder);

      if (reminderTime <= now) {
        console.log(`[GoalReminder] Skipping past reminder: ${reminderTime.toISOString()}`);
        continue;
      }

      const reminderKey = `${reminder.unit}_${reminder.value}`;
      const timeLabel = reminder.unit === "minutes"
        ? `${reminder.value}分`
        : reminder.unit === "hours"
          ? `${reminder.value}時間`
          : `${reminder.value}日`;

      const payload = {
        goalId,
        userId,
        goalTitle,
        timeLabel,
        reminderKey,
        type: "goal_reminder",
      };

      const task = {
        httpRequest: {
          httpMethod: "POST" as const,
          url: targetUrl,
          headers: { "Content-Type": "application/json" },
          body: Buffer.from(JSON.stringify(payload)).toString("base64"),
          oidcToken: {
            serviceAccountEmail,
            audience: targetUrl,
          },
        },
        scheduleTime: {
          seconds: Math.floor(reminderTime.getTime() / 1000),
        },
      };

      try {
        const [response] = await tasksClient.createTask({ parent: queuePath, task });
        console.log(`[GoalReminder] Created task: ${response.name}`);

        await db.collection("scheduledReminders").add({
          goalId,
          reminderKey,
          type: "goal_reminder",
          scheduledFor: reminderTime,
          cloudTaskName: response.name,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (e) {
        console.error(`[GoalReminder] Failed to create task:`, e);
      }
    }

    // 2. 期限時刻通知（期限ちょうど）
    if (deadline > now) {
      const deadlinePayload = {
        goalId,
        userId,
        goalTitle,
        timeLabel: "期限",
        reminderKey: "deadline",
        type: "goal_deadline",
      };

      const deadlineTask = {
        httpRequest: {
          httpMethod: "POST" as const,
          url: targetUrl,
          headers: { "Content-Type": "application/json" },
          body: Buffer.from(JSON.stringify(deadlinePayload)).toString("base64"),
          oidcToken: {
            serviceAccountEmail,
            audience: targetUrl,
          },
        },
        scheduleTime: {
          seconds: Math.floor(deadline.getTime() / 1000),
        },
      };

      try {
        const [response] = await tasksClient.createTask({ parent: queuePath, task: deadlineTask });
        console.log(`[GoalReminder] Created deadline task: ${response.name}`);

        await db.collection("scheduledReminders").add({
          goalId,
          reminderKey: "deadline",
          type: "goal_deadline",
          scheduledFor: deadline,
          cloudTaskName: response.name,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (e) {
        console.error(`[GoalReminder] Failed to create deadline task:`, e);
      }
    }
  }
);

// ===============================================
// 問い合わせ・要望機能 (callable/inquiries.ts に移動)
// - createInquiry, sendInquiryMessage, sendInquiryReply, updateInquiryStatus
// ===============================================

/**
 * 問い合わせ自動クリーンアップ（毎日実行）
 * - 6日経過: 削除予告通知
 * - 7日経過: 本体削除 + アーカイブ保存
 */
export const cleanupResolvedInquiries = onSchedule(
  {
    schedule: "0 3 * * *", // 毎日午前3時（日本時間）
    timeZone: "Asia/Tokyo",
    region: "asia-northeast1",
  },
  async () => {
    console.log("=== cleanupResolvedInquiries started ===");

    const now = new Date();
    const sixDaysAgo = new Date(now.getTime() - 6 * 24 * 60 * 60 * 1000);
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    // 解決済みの問い合わせを取得
    const inquiriesSnapshot = await db.collection("inquiries")
      .where("status", "==", "resolved")
      .get();

    console.log(`Found ${inquiriesSnapshot.size} resolved inquiries`);

    for (const doc of inquiriesSnapshot.docs) {
      const inquiry = doc.data();
      const inquiryId = doc.id;
      const resolvedAt = inquiry.resolvedAt?.toDate?.();

      if (!resolvedAt) {
        console.log(`Inquiry ${inquiryId} has no resolvedAt, skipping`);
        continue;
      }

      // 7日以上経過 → 削除
      if (resolvedAt <= sevenDaysAgo) {
        console.log(`Deleting inquiry ${inquiryId} (resolved at ${resolvedAt})`);
        await deleteInquiryWithArchive(inquiryId, inquiry);
        continue;
      }

      // 6日以上経過 & 7日未満 → 削除予告通知
      if (resolvedAt <= sixDaysAgo && resolvedAt > sevenDaysAgo) {
        console.log(`Sending deletion warning for inquiry ${inquiryId}`);
        await sendDeletionWarning(inquiryId, inquiry);
      }
    }

    console.log("=== cleanupResolvedInquiries completed ===");
  }
);

/**
 * 問い合わせを削除し、アーカイブに保存
 */
async function deleteInquiryWithArchive(
  inquiryId: string,
  inquiry: FirebaseFirestore.DocumentData
): Promise<void> {
  try {
    const inquiryRef = db.collection("inquiries").doc(inquiryId);

    // 1. メッセージを取得して会話ログを作成
    const messagesSnapshot = await inquiryRef.collection("messages")
      .orderBy("createdAt", "asc")
      .get();

    let conversationLog = "";
    let firstMessage = "";

    messagesSnapshot.docs.forEach((msgDoc, index) => {
      const msg = msgDoc.data();
      const msgDate = msg.createdAt?.toDate?.() || new Date();
      const dateStr = `${msgDate.getFullYear()}-${String(msgDate.getMonth() + 1).padStart(2, "0")}-${String(msgDate.getDate()).padStart(2, "0")} ${String(msgDate.getHours()).padStart(2, "0")}:${String(msgDate.getMinutes()).padStart(2, "0")}`;
      const sender = msg.senderType === "admin" ? "運営チーム" : "ユーザー";
      conversationLog += `[${dateStr} ${sender}]\n${msg.content}\n\n`;

      if (index === 0) {
        firstMessage = msg.content || "";
      }
    });

    // 2. カテゴリラベル
    const categoryLabels: { [key: string]: string } = {
      bug: "バグ報告",
      feature: "機能要望",
      account: "アカウント関連",
      other: "その他",
    };
    const categoryLabel = categoryLabels[inquiry.category] || inquiry.category;

    // 3. 日時フォーマット
    const createdAtDate = inquiry.createdAt?.toDate?.() || new Date();
    const resolvedAtDate = inquiry.resolvedAt?.toDate?.() || new Date();
    const formatDate = (d: Date) =>
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;

    // 4. アーカイブに保存
    await db.collection("inquiry_archives").add({
      originalInquiryId: inquiryId,
      userId: inquiry.userId,
      userDisplayName: inquiry.userDisplayName,
      category: categoryLabel,
      subject: inquiry.subject,
      firstMessage,
      conversationLog: conversationLog.trim(),
      createdAt: inquiry.createdAt,
      resolvedAt: inquiry.resolvedAt,
      archivedAt: admin.firestore.FieldValue.serverTimestamp(),
      // 1年後に削除予定
      expiresAt: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000),
    });

    console.log(`Archived inquiry ${inquiryId}`);

    // 5. メッセージサブコレクションを削除
    const batch = db.batch();
    messagesSnapshot.docs.forEach((msgDoc) => {
      batch.delete(msgDoc.ref);
    });
    await batch.commit();

    console.log(`Deleted ${messagesSnapshot.size} messages for inquiry ${inquiryId}`);

    // 6. Storage画像を削除（存在する場合）
    for (const msgDoc of messagesSnapshot.docs) {
      const msg = msgDoc.data();
      if (msg.imageUrl) {
        await deleteStorageFileFromUrl(msg.imageUrl);
      }
    }

    // 7. 問い合わせ本体を削除
    await inquiryRef.delete();
    console.log(`Deleted inquiry ${inquiryId}`);

  } catch (error) {
    console.error(`Error deleting inquiry ${inquiryId}:`, error);
  }
}

/**
 * 削除予告通知を送信
 */
async function sendDeletionWarning(
  inquiryId: string,
  inquiry: FirebaseFirestore.DocumentData
): Promise<void> {
  try {
    const userId = inquiry.userId;
    const now = admin.firestore.FieldValue.serverTimestamp();
    const notifyBody = `「${inquiry.subject}」は明日削除されます（ステータス: 解決済み）`;

    // アプリ内通知
    await db.collection("users").doc(userId).collection("notifications").add({
      type: "inquiry_deletion_warning",
      title: "問い合わせ削除予告",
      body: notifyBody,
      inquiryId,
      isRead: false,
      createdAt: now,
    });

    // プッシュ通知 (onNotificationCreatedで自動送信)

    console.log(`Sent deletion warning to user ${userId} for inquiry ${inquiryId}`);
  } catch (error) {
    console.error(`Error sending deletion warning for inquiry ${inquiryId}:`, error);
  }
}

// ===============================================
// 定期実行処理
// ===============================================

/**
 * 毎日深夜に実行されるレポートクリーンアップ処理
 * 対処済み（reviewed/dismissed）かつ1ヶ月以上前のレポートを削除する
 */
export const cleanupReports = onSchedule(
  {
    schedule: "every day 00:00",
    timeZone: "Asia/Tokyo",
    timeoutSeconds: 300,
  },
  async (event) => {
    console.log("Starting cleanupReports function...");

    try {
      // 1ヶ月前の日時を計算
      const cutoffDate = new Date();
      cutoffDate.setMonth(cutoffDate.getMonth() - 1);
      const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoffDate);

      // Reviewed reports
      // status == 'reviewed' AND createdAt < cutoffTimestamp
      const reviewedSnapshot = await db
        .collection("reports")
        .where("status", "==", "reviewed")
        .where("createdAt", "<", cutoffTimestamp)
        .get();

      // Dismissed reports
      // status == 'dismissed' AND createdAt < cutoffTimestamp
      const dismissedSnapshot = await db
        .collection("reports")
        .where("status", "==", "dismissed")
        .where("createdAt", "<", cutoffTimestamp)
        .get();

      console.log(
        `Found ${reviewedSnapshot.size} reviewed and ${dismissedSnapshot.size} dismissed reports to delete.`
      );

      // 削除対象のドキュメントを結合
      const allDocs = [...reviewedSnapshot.docs, ...dismissedSnapshot.docs];

      if (allDocs.length === 0) {
        console.log("No reports to delete.");
        return;
      }

      // バッチ処理で削除（500件ずつ）
      const MAX_BATCH_SIZE = 500;
      const chunks = [];
      for (let i = 0; i < allDocs.length; i += MAX_BATCH_SIZE) {
        chunks.push(allDocs.slice(i, i + MAX_BATCH_SIZE));
      }

      let deletedCount = 0;
      for (const chunk of chunks) {
        const batch = db.batch();
        chunk.forEach((doc) => {
          batch.delete(doc.ref);
        });
        await batch.commit();
        deletedCount += chunk.length;
        console.log(`Deleted batch of ${chunk.length} reports.`);
      }

      console.log(`Cleanup completed. Total deleted: ${deletedCount}`);
    } catch (error) {
      console.error("Error in cleanupReports:", error);
    }
  }
);

// ===================================
// カスケード削除 (Post)
// ===================================
/**
 * 投稿削除トリガー
 * - コメント、リアクションの削除
 * - Storageの画像削除
 * - ユーザー/サークルの投稿数減算
 */
export const onPostDeleted = onDocumentDeleted("posts/{postId}", async (event) => {
  const snap = event.data;
  if (!snap) return;

  const postData = snap.data();
  const postId = event.params.postId;
  const userRef = postData.userId ? db.collection("users").doc(postData.userId) : null;
  const circleRef = postData.circleId ? db.collection("circles").doc(postData.circleId) : null;

  console.log(`=== onPostDeleted: postId=${postId} start ===`);

  try {
    const batch = db.batch();
    let opCount = 0;

    // 1. コメント削除
    const commentsSnap = await db.collection("comments").where("postId", "==", postId).get();
    commentsSnap.docs.forEach((doc) => {
      batch.delete(doc.ref);
      opCount++;
    });

    // 2. リアクション削除
    const reactionsSnap = await db.collection("reactions").where("postId", "==", postId).get();
    reactionsSnap.docs.forEach((doc) => {
      batch.delete(doc.ref);
      opCount++;
    });

    // 3. 関連通知の削除 (Post Owner)
    // 自分の投稿に対する「いいね」「コメント」通知などを削除
    if (userRef) {
      const notificationsSnap = await userRef.collection("notifications").where("postId", "==", postId).get();
      notificationsSnap.docs.forEach((doc) => {
        batch.delete(doc.ref);
        opCount++;
      });
    }

    // 4. ユーザー投稿数 減算
    if (userRef) {
      batch.update(userRef, {
        totalPosts: admin.firestore.FieldValue.increment(-1),
      });
      opCount++;
    }

    // 4. サークル投稿数 減算
    if (circleRef) {
      batch.update(circleRef, {
        postCount: admin.firestore.FieldValue.increment(-1),
      });
      opCount++;
    }

    if (opCount > 0) {
      await batch.commit();
      console.log(`Deleted ${commentsSnap.size} comments, ${reactionsSnap.size} reactions.`);
    }

    // 5. Storage削除（ヘルパー関数を使用）
    const mediaItems = postData.mediaItems;
    if (Array.isArray(mediaItems) && mediaItems.length > 0) {
      console.log(`Attempting to delete ${mediaItems.length} media items...`);
      for (const item of mediaItems) {
        // メディア本体を削除
        if (item.url) {
          await deleteStorageFileFromUrl(item.url);
        }
        // 動画の場合、サムネイルも削除
        if (item.thumbnailUrl) {
          await deleteStorageFileFromUrl(item.thumbnailUrl);
        }
      }
    }

  } catch (error) {
    console.error(`Error in onPostDeleted for ${postId}:`, error);
  }
});

// ===================================
// プッシュ通知自動送信
// ===================================
/**
 * 通知ドキュメント作成時に自動的にFCMプッシュ通知を送信
 * トリガー: users/{userId}/notifications/{notificationId}
 */
export const onNotificationCreated = onDocumentCreated("users/{userId}/notifications/{notificationId}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data();
  const userId = event.params.userId;

  // タイトルと本文があれば送信
  if (data.title && data.body) {
    try {
      // ユーザー設定を確認
      const userDoc = await db.collection("users").doc(userId).get();
      const userData = userDoc.data();
      if (!userData) return;

      const settings = userData.notificationSettings || {};
      const type = data.type;

      // 通知設定チェック (コメントとリアクションのみチェック、他は重要通知として通す)
      if (type === 'comment' && settings.comments === false) {
        console.log(`Skipping push for ${type} due to user settings`);
        return;
      }
      if (type === 'reaction' && settings.reactions === false) {
        console.log(`Skipping push for ${type} due to user settings`);
        return;
      }

      await sendPushOnly(userId, data.title, data.body, { ...data, notificationId: event.params.notificationId });
      console.log(`Auto push notification sent to ${userId} for notification ${event.params.notificationId}`);
    } catch (e) {
      console.error(`Failed to send auto push notification to ${userId}:`, e);
    }
  }
});

// ===================================
// 管理者権限管理
// ===================================

/**
 * 管理者権限を設定（既存の管理者のみが実行可能）
 */
export const setAdminRole = onCall(async (request) => {
  const callerId = request.auth?.uid;
  if (!callerId) {
    throw new HttpsError("unauthenticated", "認証が必要です");
  }

  // 呼び出し元が管理者かチェック
  const callerIsAdmin = await isAdmin(callerId);
  if (!callerIsAdmin) {
    throw new HttpsError("permission-denied", "管理者権限が必要です");
  }

  const { targetUid } = request.data;
  if (!targetUid || typeof targetUid !== "string") {
    throw new HttpsError("invalid-argument", "対象ユーザーIDが必要です");
  }

  try {
    // Custom Claimを設定
    await admin.auth().setCustomUserClaims(targetUid, { admin: true });
    console.log(`Admin role granted to user: ${targetUid} by ${callerId}`);

    return { success: true, message: `ユーザー ${targetUid} を管理者に設定しました` };
  } catch (error) {
    console.error(`Error setting admin role for ${targetUid}:`, error);
    throw new HttpsError("internal", "管理者権限の設定に失敗しました");
  }
});

/**
 * 管理者権限を削除（既存の管理者のみが実行可能）
 */
export const removeAdminRole = onCall(async (request) => {
  const callerId = request.auth?.uid;
  if (!callerId) {
    throw new HttpsError("unauthenticated", "認証が必要です");
  }

  // 呼び出し元が管理者かチェック
  const callerIsAdmin = await isAdmin(callerId);
  if (!callerIsAdmin) {
    throw new HttpsError("permission-denied", "管理者権限が必要です");
  }

  const { targetUid } = request.data;
  if (!targetUid || typeof targetUid !== "string") {
    throw new HttpsError("invalid-argument", "対象ユーザーIDが必要です");
  }

  // 自分自身の管理者権限は削除できない
  if (callerId === targetUid) {
    throw new HttpsError("invalid-argument", "自分自身の管理者権限は削除できません");
  }

  try {
    // Custom Claimを削除（adminをfalseに設定）
    const user = await admin.auth().getUser(targetUid);
    const claims = user.customClaims || {};
    delete claims.admin;
    await admin.auth().setCustomUserClaims(targetUid, claims);

    console.log(`Admin role removed from user: ${targetUid} by ${callerId}`);

    return { success: true, message: `ユーザー ${targetUid} の管理者権限を削除しました` };
  } catch (error) {
    console.error(`Error removing admin role for ${targetUid}:`, error);
    throw new HttpsError("internal", "管理者権限の削除に失敗しました");
  }
});


// ===============================================
// ユーザーBAN機能
// ===============================================

/**
 * ユーザーを一時BANにする
 */
export const banUser = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    // 呼び出し元が管理者かチェック
    if (!request.auth?.token.admin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    const { userId, reason } = request.data;
    if (!userId || !reason) {
      throw new HttpsError("invalid-argument", "userIdとreasonは必須です");
    }

    // 自分自身や他の管理者はBAN不可
    if (userId === request.auth.uid) {
      throw new HttpsError("invalid-argument", "自分自身をBANすることはできません");
    }

    // 対象ユーザー確認
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      throw new HttpsError("not-found", "ユーザーが見つかりません");
    }

    // 対象が管理者かどうかのチェックは、Firestore上のデータやCustom Claimsで確認すべきだが、
    // ここではFirestoreの管理者フラグがないため省略（ただし運用上管理者はBANされない前提）

    const banRecord = {
      type: "temporary",
      reason: reason,
      bannedAt: admin.firestore.Timestamp.now(),
      bannedBy: request.auth.uid,
    };

    const batch = db.batch();

    // ユーザー更新
    batch.update(userDoc.ref, {
      banStatus: "temporary",
      isBanned: true,
      banHistory: admin.firestore.FieldValue.arrayUnion(banRecord),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 通知送信
    const notificationRef = db.collection("users").doc(userId).collection("notifications").doc();
    batch.set(notificationRef, {
      userId: userId,
      type: "user_banned",
      title: "アカウントが一時停止されました",
      body: `規約違反のため、アカウント機能の一部を制限しました。理由: ${reason}`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Custom Claims更新
    await admin.auth().setCustomUserClaims(userId, { banned: true, banStatus: 'temporary' });

    console.log(`User ${userId} temporarily banned by ${request.auth.uid}`);
    return { success: true };
  }
);

/**
 * ユーザーを永久BANにする
 */
export const permanentBanUser = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    // Admin check
    if (!request.auth?.token.admin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    const { userId, reason } = request.data;
    if (!userId || !reason) {
      throw new HttpsError("invalid-argument", "userIdとreasonは必須です");
    }

    if (userId === request.auth.uid) {
      throw new HttpsError("invalid-argument", "自分自身をBANすることはできません");
    }

    const banRecord = {
      type: "permanent",
      reason: reason,
      bannedAt: admin.firestore.Timestamp.now(),
      bannedBy: request.auth.uid,
    };

    const batch = db.batch();

    // 180日後の日付
    const deletionDate = new Date();
    deletionDate.setDate(deletionDate.getDate() + 180);

    batch.update(db.collection("users").doc(userId), {
      banStatus: "permanent",
      isBanned: true,
      banHistory: admin.firestore.FieldValue.arrayUnion(banRecord),
      permanentBanScheduledDeletionAt: admin.firestore.Timestamp.fromDate(deletionDate),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 通知（機能しませんが記録として）
    const notificationRef = db.collection("users").doc(userId).collection("notifications").doc();
    batch.set(notificationRef, {
      userId: userId,
      type: "user_banned",
      title: "アカウントが永久停止されました",
      body: `規約違反のため、アカウントを永久停止しました。理由: ${reason}`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Auth無効化 & トークン破棄
    try {
      await admin.auth().updateUser(userId, { disabled: true });
      await admin.auth().revokeRefreshTokens(userId);
      // Custom Claims更新
      await admin.auth().setCustomUserClaims(userId, { banned: true, banStatus: 'permanent' });
    } catch (e) {
      console.warn(`Auth update failed for ${userId}:`, e);
    }

    console.log(`User ${userId} permanently banned by ${request.auth.uid}`);
    return { success: true };
  }
);

/**
 * BANを解除する
 */
export const unbanUser = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    // Admin check
    if (!request.auth?.token.admin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    const { userId } = request.data;
    if (!userId) {
      throw new HttpsError("invalid-argument", "userIdは必須です");
    }

    const batch = db.batch();

    batch.update(db.collection("users").doc(userId), {
      banStatus: "none",
      isBanned: false,
      permanentBanScheduledDeletionAt: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 解除通知
    const notificationRef = db.collection("users").doc(userId).collection("notifications").doc();
    batch.set(notificationRef, {
      userId: userId,
      type: "user_unbanned",
      title: "アカウント制限が解除されました",
      body: `アカウントの制限が解除されました。`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // banAppealsの削除（該当ユーザーのチャット履歴を削除）
    try {
      const appealsSnapshot = await db.collection("banAppeals")
        .where("bannedUserId", "==", userId)
        .get();

      if (!appealsSnapshot.empty) {
        const deleteBatch = db.batch();
        appealsSnapshot.docs.forEach(doc => {
          deleteBatch.delete(doc.ref);
        });
        await deleteBatch.commit();
        console.log(`Deleted ${appealsSnapshot.size} ban appeal(s) for user ${userId}`);
      }
    } catch (e) {
      console.warn(`Failed to delete ban appeals for ${userId}:`, e);
    }

    // Auth有効化
    try {
      await admin.auth().updateUser(userId, { disabled: false });
      // Custom Claims更新（bannedフラグ削除）
      const userRecord = await admin.auth().getUser(userId);
      const currentClaims = userRecord.customClaims || {};
      delete currentClaims.banned;
      delete currentClaims.banStatus;
      await admin.auth().setCustomUserClaims(userId, currentClaims);
    } catch (e) {
      console.warn(`Auth update failed for ${userId}:`, e);
    }

    console.log(`User ${userId} unbanned by ${request.auth.uid}`);
    return { success: true };
  }
);

/**
 * 永久BANユーザーのデータ削除クリーンアップ（毎日午前4時）
 */
export const cleanupBannedUsers = onSchedule(
  {
    schedule: "0 4 * * *",
    timeZone: "Asia/Tokyo",
    region: "asia-northeast1",
    timeoutSeconds: 540,
  },
  async () => {
    console.log("=== cleanupBannedUsers START ===");
    const now = admin.firestore.Timestamp.now();

    const snapshot = await db.collection("users")
      .where("banStatus", "==", "permanent")
      .where("permanentBanScheduledDeletionAt", "<=", now)
      .limit(20)
      .get();

    if (snapshot.empty) {
      console.log("No users to delete");
      return;
    }

    console.log(`Found ${snapshot.size} users to scheduled delete`);

    for (const doc of snapshot.docs) {
      try {
        const uid = doc.id;
        console.log(`Deleting banned user: ${uid}`);

        await admin.auth().deleteUser(uid).catch(e => {
          console.warn(`Auth delete failed for ${uid}:`, e);
        });

        // ユーザードキュメント削除
        await db.collection("users").doc(uid).delete();

      } catch (error) {
        console.error(`Error deleting user ${doc.id}:`, error);
      }
    }

    console.log("=== cleanupBannedUsers COMPLETE ===");
  }
);

