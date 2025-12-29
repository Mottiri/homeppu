import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as functionsV1 from "firebase-functions/v1";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";

import * as admin from "firebase-admin";
import { GoogleGenerativeAI, Part, GenerativeModel } from "@google/generative-ai";
import { GoogleAIFileManager } from "@google/generative-ai/server";
import * as https from "https";
import { CloudTasksClient } from "@google-cloud/tasks";

// プロジェクトIDとロケーション（Cloud Tasks用）
const PROJECT_ID = "positive-sns"; // ※デプロイ環境に合わせて変更される前提、またはprocess.env.GCLOUD_PROJECT
const LOCATION = "asia-northeast1";
const QUEUE_NAME = "generateAIComment";

// Gemini API Key
const geminiApiKey = defineSecret("GEMINI_API_KEY");
// OpenAI API Key
const openaiApiKey = defineSecret("OPENAI_API_KEY");

import { AIProviderFactory } from "./ai/provider";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

admin.initializeApp();
const db = admin.firestore();

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

// ネガティブ判定のカテゴリ
type NegativeCategory =
  | "harassment"      // 誹謗中傷
  | "hate_speech"     // ヘイトスピーチ
  | "profanity"       // 不適切な言葉
  | "self_harm"       // 自傷行為の助長
  | "spam"            // スパム
  | "none";           // 問題なし

interface ModerationResult {
  isNegative: boolean;
  category: NegativeCategory;
  confidence: number;    // 0-1の確信度
  reason: string;        // 判定理由（ユーザーへの説明用）
  suggestion: string;    // 改善提案
}

// メディアモデレーション結果
interface MediaModerationResult {
  isInappropriate: boolean;
  category: "adult" | "violence" | "hate" | "dangerous" | "none";
  confidence: number;
  reason: string;
}

// メディアアイテムの型
interface MediaItem {
  url: string;
  type: "image" | "video" | "file";
  fileName?: string;
  mimeType?: string;
  fileSize?: number;
}



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

// ===============================================
// AIキャラ設計：ランダム組み合わせ方式
// 性別 × 年齢層 × 職業 × 性格 × 褒め方 = AIキャラ
// ===============================================

// 性別
type Gender = "male" | "female";

// 年齢層
type AgeGroup = "late_teens" | "twenties" | "thirties";

// 職業（性別別）
const OCCUPATIONS = {
  male: [
    { id: "college_student", name: "大学生", bio: "学業やサークル活動に励む" },
    { id: "sales", name: "営業マン", bio: "会社で営業職として働く" },
    { id: "engineer", name: "エンジニア", bio: "IT系の仕事をしている" },
    { id: "streamer", name: "配信者", bio: "ゲーム配信やYouTubeをやっている" },
    { id: "freeter", name: "フリーター", bio: "バイトしながら夢を追いかけている" },
  ],
  female: [
    { id: "ol", name: "OL", bio: "会社で事務や営業として働く" },
    { id: "college_student", name: "大学生", bio: "学業やサークル活動に励む" },
    { id: "nursery_teacher", name: "保育士", bio: "保育園で働いている" },
    { id: "designer", name: "デザイナー", bio: "Webや広告のデザインをしている" },
    { id: "nurse", name: "看護師", bio: "病院で働いている" },
  ],
};

// 性格（性別別）
// reactionType: 褒める/ねぎらう/寄り添う/いたわる/応援する/関心を持つ/刺激を受ける/尊敬する/感謝する/感心する
const PERSONALITIES = {
  male: [
    {
      id: "bright",
      name: "明るい",
      trait: "ポジティブで元気",
      style: "明るくテンション高め、感嘆符や絵文字で盛り上げる",
      examples: ["（未使用）"],
      reactionType: "褒める",
      reactionGuide: "相手の行動や結果を素直に褒めてください。",
    },
    {
      id: "passionate",
      name: "熱血",
      trait: "応援が熱い",
      style: "熱意を込めて全力で応援する姿勢",
      examples: ["（未使用）"],
      reactionType: "応援する",
      reactionGuide: "相手を全力で応援し、エールを送ってください。",
    },
    {
      id: "gentle",
      name: "穏やか",
      trait: "落ち着いている",
      style: "穏やかで落ち着いたトーン",
      examples: ["（未使用）"],
      reactionType: "ねぎらう",
      reactionGuide: "相手の労をねぎらい、優しく声をかけてください。",
    },
    {
      id: "cheerful",
      name: "ノリ良い",
      trait: "テンション高め",
      style: "くだけた口調でフレンドリーに",
      examples: ["（未使用）"],
      reactionType: "感心する",
      reactionGuide: "素直に感心・感嘆を表現してください。",
    },
    {
      id: "easygoing",
      name: "マイペース",
      trait: "ゆるい感じ",
      style: "ゆったりとしたマイペースな姿勢",
      examples: ["（未使用）"],
      reactionType: "関心を持つ",
      reactionGuide: "相手に興味を持った姿勢で、軽く質問や感想を言ってください。",
    },
  ],
  female: [
    {
      id: "kind",
      name: "優しい",
      trait: "包容力がある",
      style: "共感ベースで柔らかく寄り添う姿勢",
      examples: ["（未使用）"],
      reactionType: "寄り添う",
      reactionGuide: "相手の気持ち（達成感、疲れ、嬉しさなど）に寄り添ってください。内容そのものではなく感情に共感してください。",
    },
    {
      id: "energetic",
      name: "元気",
      trait: "明るくハキハキ",
      style: "元気いっぱい、明るいテンションで",
      examples: ["（未使用）"],
      reactionType: "褒める",
      reactionGuide: "相手の行動や結果を元気よく褒めてください。",
    },
    {
      id: "healing",
      name: "癒し系",
      trait: "ほんわかしている",
      style: "ほんわか優しい雰囲気で包み込む",
      examples: ["（未使用）"],
      reactionType: "いたわる",
      reactionGuide: "相手を優しく気遣い、無理しないでねという姿勢で。",
    },
    {
      id: "stylish",
      name: "おしゃれ",
      trait: "トレンドに敏感",
      style: "洗練された言葉選びで",
      examples: ["（未使用）"],
      reactionType: "尊敬する",
      reactionGuide: "相手を尊敬し、かっこいい・素敵だという気持ちを伝えてください。",
    },
    {
      id: "reliable",
      name: "しっかり者",
      trait: "頼りになる",
      style: "丁寧で信頼感のある姿勢",
      examples: ["（未使用）"],
      reactionType: "ねぎらう",
      reactionGuide: "相手の努力を認め、労をねぎらってください。",
    },
  ],
};

// 褒め方タイプ
const PRAISE_STYLES = [
  {
    id: "short_casual",
    name: "短文カジュアル",
    minLength: 15,
    maxLength: 35,
    description: "絵文字多め、気軽",
    example: "すごい！めっちゃいいじゃん✨",
  },
  {
    id: "medium_balanced",
    name: "中文バランス",
    minLength: 30,
    maxLength: 60,
    description: "共感+褒め",
    example: "わかる〜！こういう積み重ねが大事だよね、応援してる！",
  },
  {
    id: "long_polite",
    name: "長文しっかり",
    minLength: 50,
    maxLength: 80,
    description: "丁寧、具体的",
    example: "素敵ですね。こういった努力の積み重ねが結果に繋がるのだと思います",
  },
];

// 年齢層の情報
const AGE_GROUPS = {
  late_teens: { name: "10代後半", examples: ["大学1年", "19歳"] },
  twenties: { name: "20代", examples: ["25歳", "社会人3年目"] },
  thirties: { name: "30代", examples: ["32歳", "ベテラン"] },
};

// 名前パーツの型定義
interface NamePart {
  id: string;
  text: string;
  category: string;
  rarity: "normal" | "rare" | "super_rare" | "ultra_rare";
  order: number;
}

// 形容詞パーツ（前半）のマスタデータ
const PREFIX_PARTS: NamePart[] = [
  // ポジティブ系（ノーマル）
  { id: "pre_01", text: "がんばる", category: "positive", rarity: "normal", order: 1 },
  { id: "pre_02", text: "キラキラ", category: "positive", rarity: "normal", order: 2 },
  { id: "pre_03", text: "全力", category: "positive", rarity: "normal", order: 3 },
  { id: "pre_04", text: "輝く", category: "positive", rarity: "normal", order: 4 },
  { id: "pre_05", text: "前向き", category: "positive", rarity: "normal", order: 5 },
  // ゆるい系（ノーマル）
  { id: "pre_06", text: "のんびり", category: "relaxed", rarity: "normal", order: 6 },
  { id: "pre_07", text: "まったり", category: "relaxed", rarity: "normal", order: 7 },
  { id: "pre_08", text: "ゆるふわ", category: "relaxed", rarity: "normal", order: 8 },
  { id: "pre_09", text: "ぼちぼち", category: "relaxed", rarity: "normal", order: 9 },
  { id: "pre_10", text: "ほのぼの", category: "relaxed", rarity: "normal", order: 10 },
  // 努力系（ノーマル）
  { id: "pre_11", text: "コツコツ", category: "effort", rarity: "normal", order: 11 },
  { id: "pre_12", text: "もくもく", category: "effort", rarity: "normal", order: 12 },
  { id: "pre_13", text: "ひたむき", category: "effort", rarity: "normal", order: 13 },
  { id: "pre_14", text: "地道な", category: "effort", rarity: "normal", order: 14 },
  // 動物っぽい系（レア）
  { id: "pre_15", text: "もふもふ", category: "animal", rarity: "rare", order: 15 },
  { id: "pre_16", text: "ぴょんぴょん", category: "animal", rarity: "rare", order: 16 },
  { id: "pre_17", text: "わんわん", category: "animal", rarity: "rare", order: 17 },
  { id: "pre_18", text: "にゃんにゃん", category: "animal", rarity: "rare", order: 18 },
  // おもしろ系（スーパーレア）
  { id: "pre_19", text: "伝説の", category: "funny", rarity: "super_rare", order: 19 },
  { id: "pre_20", text: "覚醒した", category: "funny", rarity: "super_rare", order: 20 },
  { id: "pre_21", text: "無敵の", category: "funny", rarity: "super_rare", order: 21 },
  { id: "pre_22", text: "最強の", category: "funny", rarity: "super_rare", order: 22 },
  // ウルトラレア
  { id: "pre_23", text: "神に愛された", category: "legendary", rarity: "ultra_rare", order: 23 },
  { id: "pre_24", text: "運命の", category: "legendary", rarity: "ultra_rare", order: 24 },
  { id: "pre_25", text: "永遠の", category: "legendary", rarity: "ultra_rare", order: 25 },
];

// 名詞パーツ（後半）のマスタデータ
const SUFFIX_PARTS: NamePart[] = [
  // 動物（ノーマル）
  { id: "suf_01", text: "🐰うさぎ", category: "animal", rarity: "normal", order: 1 },
  { id: "suf_02", text: "🐱ねこ", category: "animal", rarity: "normal", order: 2 },
  { id: "suf_03", text: "🐶いぬ", category: "animal", rarity: "normal", order: 3 },
  { id: "suf_04", text: "🐼パンダ", category: "animal", rarity: "normal", order: 4 },
  { id: "suf_05", text: "🐻くま", category: "animal", rarity: "normal", order: 5 },
  { id: "suf_06", text: "🐢かめ", category: "animal", rarity: "normal", order: 6 },
  // 自然（ノーマル）
  { id: "suf_07", text: "🌸さくら", category: "nature", rarity: "normal", order: 7 },
  { id: "suf_08", text: "🌻ひまわり", category: "nature", rarity: "normal", order: 8 },
  { id: "suf_09", text: "⭐ほし", category: "nature", rarity: "normal", order: 9 },
  { id: "suf_10", text: "🌙つき", category: "nature", rarity: "normal", order: 10 },
  { id: "suf_11", text: "☀️たいよう", category: "nature", rarity: "normal", order: 11 },
  // 食べ物（ノーマル）
  { id: "suf_12", text: "🍙おにぎり", category: "food", rarity: "normal", order: 12 },
  { id: "suf_13", text: "🍩ドーナツ", category: "food", rarity: "normal", order: 13 },
  { id: "suf_14", text: "🍮プリン", category: "food", rarity: "normal", order: 14 },
  { id: "suf_15", text: "🍰ケーキ", category: "food", rarity: "normal", order: 15 },
  // 職業風（レア）
  { id: "suf_16", text: "チャレンジャー", category: "occupation", rarity: "rare", order: 16 },
  { id: "suf_17", text: "ファイター", category: "occupation", rarity: "rare", order: 17 },
  { id: "suf_18", text: "ドリーマー", category: "occupation", rarity: "rare", order: 18 },
  { id: "suf_19", text: "見習い", category: "occupation", rarity: "rare", order: 19 },
  // レア動物
  { id: "suf_20", text: "🦊きつね", category: "animal", rarity: "rare", order: 20 },
  { id: "suf_21", text: "🦁ライオン", category: "animal", rarity: "rare", order: 21 },
  { id: "suf_22", text: "🦄ユニコーン", category: "animal", rarity: "rare", order: 22 },
  // おもしろ系（スーパーレア）
  { id: "suf_23", text: "勇者", category: "funny", rarity: "super_rare", order: 23 },
  { id: "suf_24", text: "魔王", category: "funny", rarity: "super_rare", order: 24 },
  { id: "suf_25", text: "賢者", category: "funny", rarity: "super_rare", order: 25 },
  { id: "suf_26", text: "修行僧", category: "funny", rarity: "super_rare", order: 26 },
  { id: "suf_27", text: "冒険者", category: "funny", rarity: "super_rare", order: 27 },
  // ウルトラレア
  { id: "suf_28", text: "🐉ドラゴン", category: "legendary", rarity: "ultra_rare", order: 28 },
  { id: "suf_29", text: "🔥不死鳥", category: "legendary", rarity: "ultra_rare", order: 29 },
  { id: "suf_30", text: "覇王", category: "legendary", rarity: "ultra_rare", order: 30 },
];

// AIペルソナの型定義
interface AIPersona {
  id: string;
  name: string;
  namePrefixId: string;  // 名前パーツ（前半）のID
  nameSuffixId: string;  // 名前パーツ（後半）のID
  gender: Gender;
  ageGroup: AgeGroup;
  occupation: typeof OCCUPATIONS.male[0];
  personality: typeof PERSONALITIES.male[0];
  praiseStyle: typeof PRAISE_STYLES[0];
  avatarIndex: number;
  bio: string;
}

// bioテンプレート（職業×性格の組み合わせでより自然に）
const BIO_TEMPLATES: Record<string, Record<string, string[]>> = {
  // 男性職業
  college_student: {
    bright: [
      "大学生やってます！カフェ巡りとバスケが好き🏀",
      "心理学専攻の大学生📚 毎日楽しく過ごしてます✨",
      "サークルとバイトで忙しい大学生活🎵",
    ],
    passionate: [
      "大学でバスケ部！目標に向かって全力で頑張ってる💪",
      "熱い仲間と一緒に大学生活満喫中🔥",
      "部活も勉強も全力投球！後悔しない大学生活を！",
    ],
    gentle: [
      "のんびり大学生活送ってます。読書と散歩が好き",
      "大学3年生。穏やかに過ごす日々が好きです",
      "マイペースな大学生。カフェでまったりするのが至福☕",
    ],
    cheerful: [
      "大学生してるww ゲームとラーメンが好き🍜",
      "サークルの仲間と遊ぶのが一番楽しいww",
      "テスト前なのに遊んじゃう系大学生😇",
    ],
    easygoing: [
      "ゆるく大学生やってます〜 趣味は映画鑑賞",
      "のんびり屋の大学生。急がない生き方が好き",
      "気ままに過ごす大学生活。それがいちばん",
    ],
    kind: [
      "大学で心理学勉強中📚 人の話聞くの好きです",
      "サークルでみんなの相談役やってます",
      "穏やかな大学生活送ってます。友達大切にしてる",
    ],
    energetic: [
      "大学生！！毎日全力で楽しんでます✨✨",
      "サークルもバイトも全部楽しい！！大学最高！",
      "元気だけが取り柄の大学生です💪✨",
    ],
    healing: [
      "のほほんと大学生やってます〜 お菓子作りが趣味",
      "ゆるふわ大学生。癒しを求めて生きてる🌸",
      "まったり過ごすのが好きな大学生です",
    ],
    stylish: [
      "大学生👗 ファッションとカフェ巡りが好き",
      "トレンド追いかけてる大学生✨ コスメ好き",
      "おしゃれな大学生活目指してます☕",
    ],
    reliable: [
      "大学でゼミ長やってます。責任感は強い方かな",
      "しっかり者って言われる大学生です",
      "計画的に動くのが好きな大学生。目標は資格取得",
    ],
  },
  sales: {
    bright: ["IT企業で営業してます！休日はカフェ巡り☕✨", "営業マン3年目！仕事も遊びも全力で💪", "仕事終わりのビールが最高🍺 週末はフットサル"],
    passionate: ["営業で日本一目指してます！！夢は大きく🔥", "熱血営業マン！お客様の笑顔が原動力💪", "仕事に燃えてます！休日は筋トレ🏋️"],
    gentle: ["営業してます。人と話すのが好きです", "穏やかに仕事してます。趣味は読書と料理", "マイペースな営業マン。焦らず着実に"],
    cheerful: ["営業マンやってるww 飲み会大好き🍻", "ノリと勢いで生きてる営業マンですww", "仕事も遊びもテンション高めで！"],
    easygoing: ["ゆるく営業やってます〜 休日はゴロゴロ", "のんびり屋の営業マン。急がない主義", "マイペースに働いてます。趣味はドライブ"],
  },
  engineer: {
    bright: ["Webエンジニアです！技術が好き💻✨", "コード書くのが楽しいエンジニア。休日は勉強会", "IT企業でエンジニアしてます。新技術にワクワク"],
    passionate: ["エンジニアとして日々成長中！目標はCTO💪", "技術で世界を変えたいエンジニアです🔥", "プログラミングに情熱燃やしてます！"],
    gentle: ["穏やかにコード書いてます。コーヒーが友達☕", "のんびりエンジニアしてます。猫が好き🐱", "黙々と開発するのが好きなエンジニアです"],
    cheerful: ["エンジニアやってるww バグと格闘する日々", "深夜のコーディングが捗るタイプww", "新技術見つけるとテンション上がるww"],
    easygoing: ["ゆるくエンジニアしてます〜 リモートワーク最高", "マイペースに開発してます。趣味はゲーム", "のんびりコード書く生活が好き"],
  },
  streamer: {
    bright: ["ゲーム配信してます！見に来てね✨", "配信者やってます🎮 みんなと話すの楽しい！", "ゲームと配信が生きがい！フォローよろしく"],
    passionate: ["配信で有名になる！！夢に向かって全力🔥", "毎日配信頑張ってます！！応援よろしく💪", "ゲーム配信者として本気で活動中！"],
    gentle: ["まったり配信してます。ゲームは癒し", "のんびりゲーム配信。雑談も好きです", "穏やかに配信活動してます。よろしくね"],
    cheerful: ["配信者やってるwww 深夜テンションで草", "ゲーム配信してるよ〜見に来てww", "推しVtuberの話で盛り上がりたいww"],
    easygoing: ["ゆるく配信活動してます〜 気軽に見てね", "マイペースに配信。数字は気にしない派", "のんびりゲーム実況やってます"],
  },
  freeter: {
    bright: ["バイトしながら夢追いかけてます✨", "フリーターだけど毎日楽しい！音楽が好き🎵", "自由に生きてます！やりたいことをやる人生"],
    passionate: ["夢のために今は修行中！絶対叶える🔥", "バイトしながら創作活動！諦めない💪", "いつか絶対成功してやる！！"],
    gentle: ["のんびりバイト生活。焦らず自分のペースで", "ゆっくり将来考え中。今を大切に生きてる", "マイペースに生きてます。それでいいかなって"],
    cheerful: ["フリーターやってるww 自由最高〜", "バイト掛け持ち生活ww 意外と楽しい", "将来？なんとかなるっしょww"],
    easygoing: ["気ままにフリーター生活〜 ストレスフリー", "のんびり生きてます。急がない人生", "自分のペースで生きるのが一番"],
  },
  // 女性職業
  ol: {
    kind: ["都内でOLしてます。週末はカフェでまったり☕", "事務職3年目。人の役に立てると嬉しい", "仕事終わりのスイーツが癒し🍰"],
    energetic: ["OL頑張ってます！！毎日充実✨✨", "仕事もプライベートも全力！！楽しい毎日💪", "元気だけが取り柄のOLです！！"],
    healing: ["ゆるっとOLしてます〜 お花が好き🌸", "まったりOL生活。癒しを求めて生きてる", "のほほんとお仕事してます。紅茶が好き"],
    stylish: ["都内OL👗 休日はショッピングとカフェ巡り", "おしゃれなOL目指してます✨ コスメ大好き", "トレンドチェックが趣味のOLです"],
    reliable: ["OL5年目。後輩の面倒見るのが好きです", "しっかり仕事するタイプのOLです", "責任感強めなOL。プライベートも計画的に"],
  },
  nursery_teacher: {
    kind: ["保育士してます🌷 子どもたちに元気もらってる", "子どもたちの笑顔が宝物。保育士やってます", "毎日子どもたちと過ごせて幸せな保育士です"],
    energetic: ["保育士！！子どもたちと全力で遊んでます💪", "元気いっぱいの保育士です！！毎日楽しい✨", "子どもたちのパワーに負けないぞ！！"],
    healing: ["保育士やってます〜 子どもたちに癒される毎日", "のほほんと保育士生活🌸 お菓子作りが趣味", "子どもたちとまったり過ごす日々が幸せ"],
    stylish: ["保育士だけどおしゃれも諦めない✨", "子どもたちに可愛いって言われたい保育士です", "休日はカフェ巡りする保育士👗"],
    reliable: ["保育士5年目。子どもたちの成長が嬉しい", "しっかり者って言われる保育士です", "安心して預けてもらえる保育士を目指してます"],
  },
  designer: {
    kind: ["Webデザイナーしてます🎨 創ることが好き", "デザインで人を笑顔にしたい。そんなデザイナーです", "休日は美術館巡り。インプット大事にしてます"],
    energetic: ["デザイナー！！毎日クリエイティブ全開✨✨", "デザインで世界を変えたい！！夢は大きく💪", "作品作りに燃えてます！！見てほしい！"],
    healing: ["ゆるっとデザイナーしてます〜 イラストも描くよ", "まったりデザイン生活🎨 猫と暮らしてます", "のほほんとデザイナーやってます。お茶が好き"],
    stylish: ["デザイナー✨ おしゃれなもの作りたい", "トレンドを取り入れたデザインが得意です", "デザインもファッションも好き👗✨"],
    reliable: ["デザイナー歴5年。クライアントの期待に応えたい", "納期はしっかり守るタイプのデザイナーです", "丁寧な仕事を心がけてます"],
  },
  nurse: {
    kind: ["看護師してます。患者さんの笑顔が励み", "人の役に立ちたくて看護師になりました", "毎日大変だけど、やりがいのある仕事です"],
    energetic: ["看護師頑張ってます！！体力勝負💪✨", "夜勤明けでも元気！！この仕事が好き！！", "患者さんを元気にしたい！！看護師です"],
    healing: ["看護師やってます〜 休日はお昼寝が至福", "まったり休日を過ごす看護師です🌸", "癒し系看護師目指してます〜"],
    stylish: ["看護師だけど休日はおしゃれしたい✨", "オフの日はカフェ巡りする看護師です", "仕事もプライベートも充実させたい看護師👗"],
    reliable: ["看護師7年目。後輩の指導もしてます", "頼られる看護師を目指して日々勉強中", "患者さんに安心してもらえる看護師でいたい"],
  },
};

// AIが使用可能な名前パーツ（ノーマルとレアのみ、スーパーレア以上は使用不可）
const AI_USABLE_PREFIXES = PREFIX_PARTS.filter((p) => p.rarity === "normal" || p.rarity === "rare");
const AI_USABLE_SUFFIXES = SUFFIX_PARTS.filter((p) => p.rarity === "normal" || p.rarity === "rare");

// AIペルソナを生成する関数
function generateAIPersona(index: number): AIPersona {
  // 性別を決定（偶数=女性、奇数=男性で半々にする）
  const gender: Gender = index % 2 === 0 ? "female" : "male";

  // 各カテゴリをインデックスベースで分散
  const occupations = OCCUPATIONS[gender];
  const personalities = PERSONALITIES[gender];

  const occupation = occupations[index % occupations.length];
  const personality = personalities[Math.floor(index / 2) % personalities.length];
  const praiseStyle = PRAISE_STYLES[Math.floor(index / 4) % PRAISE_STYLES.length];
  const ageGroup: AgeGroup = (["late_teens", "twenties", "thirties"] as const)[
    Math.floor(index / 6) % 3
  ];

  // 名前パーツから選択（インデックスを使って分散）
  const prefixIndex = index % AI_USABLE_PREFIXES.length;
  const suffixIndex = Math.floor(index * 1.618) % AI_USABLE_SUFFIXES.length; // 黄金比で分散
  const namePrefix = AI_USABLE_PREFIXES[prefixIndex];
  const nameSuffix = AI_USABLE_SUFFIXES[suffixIndex];
  const name = `${namePrefix.text}${nameSuffix.text}`;

  // アバターインデックス（0-9の範囲）
  const avatarIndex = index % 10;

  // bioを生成（職業×性格の組み合わせから選択）
  const occupationBios = BIO_TEMPLATES[occupation.id] || {};
  const personalityBios = occupationBios[personality.id] || [];

  // bioが見つからない場合はデフォルト
  let bio: string;
  if (personalityBios.length > 0) {
    bio = personalityBios[index % personalityBios.length];
  } else {
    // フォールバック：シンプルだけど自然なbio
    const defaultBios = [
      `${occupation.name} してます！よろしくね✨`,
      `${occupation.name} やってます。毎日頑張ってる`,
      `${occupation.name} です。趣味は読書と散歩`,
    ];
    bio = defaultBios[index % defaultBios.length];
  }

  return {
    id: `ai_${index.toString().padStart(2, "0")}`,
    name: name.trim(),
    namePrefixId: `prefix_${namePrefix.id}`,
    nameSuffixId: `suffix_${nameSuffix.id}`,
    gender,
    ageGroup,
    occupation,
    personality,
    praiseStyle,
    avatarIndex,
    bio,
  };
}

// 20体のAIペルソナを生成
const AI_PERSONAS: AIPersona[] = Array.from({ length: 20 }, (_, i) => generateAIPersona(i));

/**
 * システムプロンプトを生成
 */
function getSystemPrompt(
  persona: AIPersona,
  posterName: string
): string {
  const genderStr = persona.gender === "male" ? "男性" : "女性";
  const ageStr = AGE_GROUPS[persona.ageGroup].name;

  return `
# Role (役割)
あなたは自己肯定感を高めるポジティブなSNS「ほめっぷ」のユーザーです。

# Task (命令)
提示されたユーザーの投稿内容を読み取り、以下の【ペルソナ】および【反応スタイル】に従って、返信コメントを一つ作成してください。
※アプリのコンセプト上、批判やネガティブな発言は禁止です。

# Output Constraints (出力制約 - 絶対遵守)
1. **出力は「返信コメントの本文のみ」としてください**。
2. 「〜について返信します」などの前置き、挨拶、思考プロセスは**一切禁止**です。
3. 自然な会話文（プレーンテキスト）のみを出力してください。

【ペルソナ】
- 名前: ${persona.name}
- 性別: ${genderStr}
- 年齢: ${ageStr}
- 職業: ${persona.occupation.name}（${persona.occupation.bio}）
- 性格: ${persona.personality.name}（${persona.personality.trait}）
- 話し方: ${persona.personality.style}

【反応スタイル: ${persona.personality.reactionType}】
${persona.personality.reactionGuide}

【固有名詞の誤字への対応】
- 投稿内容に誤字と思われる固有名詞（曲名、人名など）がある場合、そのままオウム返しにしないでください。
- あなたの性格に応じて以下のいずれかの対応をしてください：
  - 知識豊富・ツッコミ系 → 「〇〇って●●の事かな？」と軽く確認しつつ返信
  - 優しい系 → 固有名詞には触れず「その曲いいよね！」など曖昧に返信
  - 熱血・応援系 → 話題の本質（「好き」という気持ち）にフォーカスして返信

【禁止事項】
1. 疑問形で文章を完結させること
2. 投稿内容をそのまま要約して繰り返すこと（例：「〇〇されたんですね」）
3. 「その通りですね」「わかります」などの相槌だけで文を始めない
4. 外国語の直訳や不自然な日本語
5. 「すごい！」「応援してる！」などのテンプレ的な褒め方の乱用
6. ネガティブな発言

【投稿内容が意味不明な場合】
- 投稿内容がランダムな文字列や極端な誤字で意味が通じない場合は、無理に返信せず「SKIP_COMMENT」とだけ出力してください。

【文字数の目安】
- ${persona.praiseStyle.minLength}〜${persona.praiseStyle.maxLength} 文字程度
      `;
}

/**
 * サークル投稿専用のシステムプロンプトを生成
 */
function getCircleSystemPrompt(
  persona: AIPersona,
  posterName: string,
  circleName: string,
  circleDescription: string,
  postContent: string,
  circleGoal?: string,
  circleRules?: string
): string {
  const rulesSection = circleRules
    ? `\n【サークルルール（必ず遵守してください）】\n${circleRules}\n`
    : "";

  const genderStr = persona.gender === "male" ? "男性" : "女性";
  const ageStr = AGE_GROUPS[persona.ageGroup].name;

  // 目標がある場合のプロンプト
  if (circleGoal) {
    return `
# Role (役割)
あなたはポジティブなSNS「ほめっぷ」のサークルメンバーです。

# Task (命令)
サークル「${circleName}」のメンバーとして、投稿に対して【ペルソナ】および【反応スタイル】に従って返信コメントを作成してください。
同じ目標を持つ仲間として振る舞ってください。

# Output Constraints (出力制約 - 絶対遵守)
1. **出力は「返信コメントの本文のみ」としてください**。
2. 「〜について返信します」などの前置き、挨拶、思考プロセスは**一切禁止**です。
3. 自然な会話文（プレーンテキスト）のみを出力してください。

【サークル情報】
- サークル名: ${circleName}
- 概要: ${circleDescription}
- 共通の目標: ${circleGoal}
${rulesSection}

【ペルソナ】
- 名前: ${persona.name}
- 性別: ${genderStr}
- 年齢: ${ageStr}
- 職業: ${persona.occupation.name}
- 性格: ${persona.personality.name}（${persona.personality.trait}）
- 話し方: ${persona.personality.style}

【反応スタイル: ${persona.personality.reactionType}】
${persona.personality.reactionGuide}

【固有名詞の誤字への対応】
- 投稿内容に誤字と思われる固有名詞がある場合、そのままオウム返しにしないでください。
- あなたの性格に応じて以下のいずれかの対応をしてください：
  - 知識豊富・ツッコミ系 → 「〇〇って●●の事かな？」と軽く確認しつつ返信
  - 優しい系 → 固有名詞には触れず曖昧に返信
  - 熱血・応援系 → 話題の本質にフォーカスして返信

【専門用語の扱い方】
投稿内容を分析し、専門用語がある場合は、その専門用語の知識がある程度あるが、勉強中という立場で返信を作成してください。

【禁止事項】
1. 疑問形で文章を完結させること
2. 投稿内容をそのまま要約して繰り返すこと
3. 「すごい！」「応援してる！」などのテンプレ的な褒め方
4. 「奥が深い」「すごい技術」などの曖昧な逃げ表現
5. ネガティブな発言
6. 日本語として不自然な表現

【投稿内容が意味不明な場合】
- 意味が通じない場合は「SKIP_COMMENT」とだけ出力してください。

【文字数の目安】
- ${persona.praiseStyle.minLength}〜${persona.praiseStyle.maxLength} 文字程度
`;
  }

  // 目標がない場合のプロンプト
  return `
# Role (役割)
あなたはポジティブなSNS「ほめっぷ」のサークルメンバーです。

# Task (命令)
サークル「${circleName}」のメンバーとして、投稿に対して【ペルソナ】および【反応スタイル】に従って返信コメントを作成してください。
共通の趣味や話題を楽しむ仲間として振る舞ってください。

# Output Constraints (出力制約 - 絶対遵守)
1. **出力は「返信コメントの本文のみ」としてください**。
2. 前置き、挨拶、思考プロセスは一切禁止です。
3. 自然な会話文（プレーンテキスト）のみを出力してください。

【サークル情報】
- サークル名: ${circleName}
- 概要: ${circleDescription}
${rulesSection}

【ペルソナ】
- 名前: ${persona.name}
- 性別: ${genderStr}
- 年齢: ${ageStr}
- 職業: ${persona.occupation.name}
- 性格: ${persona.personality.name}（${persona.personality.trait}）
- 話し方: ${persona.personality.style}

【反応スタイル: ${persona.personality.reactionType}】
${persona.personality.reactionGuide}

【固有名詞の誤字への対応】
- 投稿内容に誤字と思われる固有名詞がある場合、そのままオウム返しにしないでください。
- あなたの性格に応じて適切な対応をしてください。

【専門用語の扱い方】
投稿内容を分析し、専門用語がある場合は、その専門用語の知識がある程度あるが、勉強中という立場で返信を作成してください。

【禁止事項】
1. 疑問形で文章を完結させること
2. 「すごい！」「応援してる！」などのテンプレ的な褒め方
3. 「奥が深い」「すごい技術」などの曖昧な逃げ表現
4. ネガティブな発言

【投稿内容が意味不明な場合】
- 意味が通じない場合は「SKIP_COMMENT」とだけ出力してください。

【文字数の目安】
- ${persona.praiseStyle.minLength}〜${persona.praiseStyle.maxLength} 文字程度
`;
}

/**
 * 投稿内容がAIにとって安全かつ適切か（意味が通じるか）を判定する
 */
async function evaluatePostSafety(
  apiKey: string,
  model: GenerativeModel,
  content: string
): Promise<boolean> {
  // 短すぎる、または明らかに意味のない文字列はAPIを呼ばずに弾く（簡易フィルタ）
  if (content.length < 2 && !/^[\u4e00-\u9faf]+$/.test(content)) return false; // 1文字のひらがな/カタカナ等は弾く（漢字1文字はOK）

  const prompt = `
あなたはコンテンツフィルターです。
以下のテキストが「会話として成立する日本語」かどうかを判定してください。

【判定基準】
- YES (許可):
  - 日常会話、報告、感想など、意味が汲み取れるもの。
  - **主語や目的語が省略されていても、状況が想像できるならYES**としてください。（例：「飾り付けした」（何を？がなくてもXmasならOK）、「お腹すいた」「やったー」）
  - 方言や多少の崩れた表現も、意味が通じるならOK。

- NO (拒否):
  - **ランダムな文字の羅列**。（例：「あかま」「てておか」「あいうえお」）
  - 文脈が全くなく、単語単体で意味をなさないもの。（例：「山田」（呼びかけか名前か不明）、「テスト」）
  - 完全に意味不明な文字列。

迷った場合は、会話の糸口が見つかるなら「YES」に倒してください。

テキスト:
${content}

フォーマット: [YES/NO] [理由]
`;

  try {
    const result = await model.generateContent(prompt);
    const response = result.response.text().trim();
    console.log(`Safety evaluation raw response: ${response}`);

    // YESで始まっているか判定（大文字小文字無視、先頭一致）
    const isSafe = response.toUpperCase().startsWith("YES");
    console.log(`Safety evaluation result: ${isSafe ? "YES" : "NO"}`);
    return isSafe;
  } catch (error) {
    console.error("Safety evaluation failed:", error);
    return true; // エラー時はフェイルオープン（念のため通す）かクローズか...ここでは通す
  }
}

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

    // 投稿内容の安全性・意味チェック (Binary Filter)
    /*
     * 判定ロジックを一時的に無効化 (2025-12-24)
     * 理由: 現在のGemini Flashモデルでは、短いテキストに対する「文脈の有無」や「意味の通じる/通じない」の線引きが難しく、
     * 「あかま」のような無意味な文字列を通してしまうか、逆に「飾り付けした」のような会話的な省略を弾いてしまうため。
     * UXを優先し、フィルターなしで運用する。
     */
    /*
    const postContent = postData.content || "";
    console.log(`[DEBUG] content check: "${postContent}", length=${postContent.length}`);
    
    if (postContent && !postContent.match(/^http/)) { // URLのみの場合はスキップしない（画像判定に任せる）
      console.log(`[DEBUG] Entering safety evaluation block`);
      console.log(`Evaluating post safety for content: ${postContent}`);
      const isSafe = await evaluatePostSafety(apiKey, model, postContent);
      if (!isSafe) {
        console.log("Post evaluated as UNSAFE or MEANINGLESS. Skipping AI comments.");
        return;
      }
      console.log("Post evaluated as SAFE. Proceeding with AI comments.");
    }
    */

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
      selectedPersonas = generatedAIs.map((ai) => ({
        id: ai.id,
        name: ai.name,
        namePrefixId: "",
        nameSuffixId: "",
        gender: ai.gender,
        ageGroup: ai.ageGroup,
        occupation: ai.occupation,
        personality: {
          ...ai.personality,
          examples: ai.personality.examples || ["すごい！", "いいね！"],
          reactionType: (ai.personality as any).reactionType || "寄り添う",
          reactionGuide: (ai.personality as any).reactionGuide || "相手の気持ちに寄り添ってください。",
        },
        praiseStyle: PRAISE_STYLES[Math.floor(Math.random() * PRAISE_STYLES.length)],
        avatarIndex: ai.avatarIndex,
        bio: "",
      }));

      console.log(`Using ${selectedPersonas.length} circle AIs for comments`);
    } else {
      // 一般投稿：ランダムに3〜10人のAIを選択
      const commentCount = Math.floor(Math.random() * 8) + 3;
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
    // 2. AIリアクションの大量投下 (5〜15件、平均10件)
    // ===========================================
    const reactionCount = Math.floor(Math.random() * 11) + 5; // 5〜15
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
  async () => {
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
  async () => {
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
        "申し訳ありませんが、現在投稿できません。運営にお問い合わせください。"
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
    const ADMIN_UID = "hYr5LUH4mhR60oQfVOggrjGYJjG2";
    if (userId === ADMIN_UID && mediaItems && Array.isArray(mediaItems) && mediaItems.length > 0) {
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

        // アプリ内通知を作成（管理者のnotificationsサブコレクション）
        await db.collection("users").doc(ADMIN_UID).collection("notifications").add({
          type: "review_needed",
          title: "要審査投稿",
          body: `フラグ付き投稿があります: ${needsReviewReason}`,
          postId: postRef.id,
          fromUserId: userId,
          fromUserName: userDisplayName,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          read: false,
        });
        console.log("Admin in-app notification created");

        // 管理者にFCM通知を送信
        const adminUserDoc = await db.collection("users").doc(ADMIN_UID).get();
        const fcmToken = adminUserDoc.data()?.fcmToken;
        if (fcmToken) {
          await admin.messaging().send({
            token: fcmToken,
            notification: {
              title: "要審査投稿",
              body: `フラグ付き投稿があります: ${needsReviewReason}`,
            },
            data: {
              type: "review_needed",
              postId: postRef.id,
            },
          });
          console.log("Admin FCM notification sent successfully");
        }
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
// 通報機能
// ===============================================

/**
 * コンテンツを通報する
 */
export const reportContent = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const reporterId = request.auth.uid;
    const { contentId, contentType, reason, targetUserId } = request.data;

    if (!contentId || !contentType || !reason || !targetUserId) {
      throw new HttpsError("invalid-argument", "必要な情報が不足しています");
    }

    // 自分自身を通報できない
    if (reporterId === targetUserId) {
      throw new HttpsError("invalid-argument", "自分自身を通報することはできません");
    }

    // 既に同じ内容を通報していないかチェック
    const existingReport = await db
      .collection("reports")
      .where("reporterId", "==", reporterId)
      .where("contentId", "==", contentId)
      .get();

    if (!existingReport.empty) {
      throw new HttpsError("already-exists", "既にこの内容を通報しています");
    }

    // 通報を記録
    const reportRef = await db.collection("reports").add({
      reporterId: reporterId,
      targetUserId: targetUserId,
      contentId: contentId,
      contentType: contentType,  // "post" | "comment"
      reason: reason,
      status: "pending",  // pending, reviewed, resolved, dismissed
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 対象ユーザーの通報カウントを増加
    const targetUserRef = db.collection("users").doc(targetUserId);
    await targetUserRef.update({
      reportCount: admin.firestore.FieldValue.increment(1),
    });

    // 通報が3件以上溜まったら自動で徳を減少
    const reportsCount = await db
      .collection("reports")
      .where("targetUserId", "==", targetUserId)
      .where("status", "==", "pending")
      .get();

    if (reportsCount.size >= 3) {
      const virtueResult = await decreaseVirtue(
        targetUserId,
        "複数の通報を受けたため",
        VIRTUE_CONFIG.lossPerReport
      );

      // 通報をreviewedに更新
      const batch = db.batch();
      reportsCount.docs.forEach((doc) => {
        batch.update(doc.ref, { status: "reviewed" });
      });
      await batch.commit();

      console.log(`Auto virtue decrease for ${targetUserId}: ${virtueResult.newVirtue} `);
    }

    return {
      success: true,
      reportId: reportRef.id,
      message: "通報を受け付けました。ご協力ありがとうございます。",
    };
  }
);

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
// タスク機能
// ===============================================

/**
 * タスクを作成
 */
export const createTask = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const { content, emoji, type, scheduledAt, priority, googleCalendarEventId, subtasks, recurrenceInterval, recurrenceUnit, recurrenceDaysOfWeek, recurrenceEndDate, categoryId } = request.data;

    if (!content || !type) {
      throw new HttpsError("invalid-argument", "タスク内容とタイプは必須です");
    }

    const baseTaskData = {
      userId: userId,
      content: content,
      emoji: emoji || "📝",
      type: type, // "daily" | "goal" | "todo"
      isCompleted: false,
      streak: 0,
      lastCompletedAt: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      priority: priority || 0,
      googleCalendarEventId: googleCalendarEventId || null,
      subtasks: subtasks || [],
      // 展開後の各タスクには繰り返しルールを持たせない（独立したタスクとする）
      // ただし、もし「繰り返し元」を知りたい場合はIDが必要だが、今回は要件に含まれないため単純展開する
      // UIで「繰り返し」と表示されなくなるが、ユーザーは「カレンダーに登録される」ことを望んでいるため許容
      // 保存したルール自体は残したい場合、fieldsを残すが、そうすると編集時に再展開の判断が難しくなる
      // ここでは「展開したらルールは消す」方針とする（Googleカレンダー形式）
      recurrenceInterval: null,
      recurrenceUnit: null,
      recurrenceDaysOfWeek: null,
      recurrenceEndDate: null,
      categoryId: categoryId || null,
      recurrenceGroupId: null, // 初期値
    };

    const tasksToCreate: any[] = [];
    const startDate = scheduledAt ? new Date(scheduledAt) : new Date();

    // グループID生成（最初のドキュメントIDを使う）
    const firstRef = db.collection("tasks").doc();
    const groupId = recurrenceUnit ? firstRef.id : null;

    if (!recurrenceUnit) {
      // 単発
      tasksToCreate.push({
        ...baseTaskData,
        scheduledAt: scheduledAt ? admin.firestore.Timestamp.fromDate(startDate) : null,
      });
    } else {
      // 繰り返し展開
      const interval = recurrenceInterval || 1;
      let currentDate = new Date(startDate);
      let endDate = recurrenceEndDate ? new Date(recurrenceEndDate) : new Date(startDate);

      if (!recurrenceEndDate) {
        // デフォルト3年
        endDate.setFullYear(endDate.getFullYear() + 3);
      }

      // 無限ループ防止
      let count = 0;
      const MAX_COUNT = 1100; // 約3年分

      while (currentDate <= endDate && count < MAX_COUNT) {
        // 週次の曜日指定がある場合
        let isValidDate = true;
        if (recurrenceUnit === 'weekly' && recurrenceDaysOfWeek && recurrenceDaysOfWeek.length > 0) {
          // Firestore/JS Day: 0=Sun, 1=Mon...
          // App Day: 1=Mon...7=Sun.
          // Convert App(1-7) to JS(1-6, 0)
          const appDay = recurrenceDaysOfWeek; // Array of 1-7
          const jsDay = currentDate.getDay(); // 0-6
          const appDayConverted = jsDay === 0 ? 7 : jsDay;

          if (!appDay.includes(appDayConverted)) {
            isValidDate = false;
          }
        }

        if (isValidDate) {
          tasksToCreate.push({
            ...baseTaskData,
            scheduledAt: admin.firestore.Timestamp.fromDate(new Date(currentDate)),
            recurrenceGroupId: groupId, // リンク用ID
          });
        }

        // 次の日付計算
        if (recurrenceUnit === 'daily') {
          currentDate.setDate(currentDate.getDate() + interval);
        } else if (recurrenceUnit === 'weekly') {
          // 曜日指定がある場合は1日ずつ進めてチェックする方が確実だが、
          // シンプルに「指定曜日以外スキップ」ロジックだと interval > 1 の週次ができなくなる
          // ここでは interval=1 (毎週) の場合、1日ずつ進めるのが正しい挙動（曜日チェックで拾う）
          // interval > 1 の場合も考慮すると複雑だが、ユーザー要件「毎日」が主。
          // 実装: 常に1日進めて、曜日マッチ＆週周期マッチを確認するのは重い。
          // 簡易実装: 
          // 曜日指定あり -> 1日ずつ進める (interval無視、またはinterval=1前提)
          // 曜日指定なし -> interval週進める
          if (recurrenceDaysOfWeek && recurrenceDaysOfWeek.length > 0) {
            currentDate.setDate(currentDate.getDate() + 1);
          } else {
            currentDate.setDate(currentDate.getDate() + (7 * interval));
          }
        } else if (recurrenceUnit === 'monthly') {
          currentDate.setMonth(currentDate.getMonth() + interval);
        } else if (recurrenceUnit === 'yearly') {
          currentDate.setFullYear(currentDate.getFullYear() + interval);
        } else {
          // Fallback
          currentDate.setDate(currentDate.getDate() + 1);
        }

        count++;
      }
    }

    // Batch Write (Max 500 per batch)
    const batches = [];
    let currentBatch = db.batch();
    let opCount = 0;
    let firstTaskId = "";

    let isFirst = true;
    for (const taskData of tasksToCreate) {
      let ref;
      if (isFirst) {
        ref = firstRef;
        isFirst = false;
        firstTaskId = ref.id;
      } else {
        ref = db.collection("tasks").doc();
      }

      currentBatch.set(ref, taskData);
      opCount++;

      if (opCount >= 500) {
        batches.push(currentBatch.commit());
        currentBatch = db.batch();
        opCount = 0;
      }
    }
    if (opCount > 0) {
      batches.push(currentBatch.commit());
    }

    await Promise.all(batches);

    return { success: true, taskId: firstTaskId };
  }
);

/**
 * タスク一覧を取得
 */
export const getTasks = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const { type } = request.data;

    let query = db.collection("tasks").where("userId", "==", userId);

    if (type) {
      query = query.where("type", "==", type);
    }

    const snapshot = await query.orderBy("createdAt", "desc").get();

    // 今日の開始時刻を計算（日本時間）
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    const tasks = snapshot.docs.map((doc) => {
      const data = doc.data();
      const lastCompletedAt = data.lastCompletedAt?.toDate?.();

      // isCompletedTodayを計算（lastCompletedAtが今日かどうか）
      let isCompletedToday = false;
      if (lastCompletedAt) {
        isCompletedToday = lastCompletedAt >= todayStart;
      }

      return {
        id: doc.id,
        ...data,
        isCompletedToday,
        createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
        updatedAt: data.updatedAt?.toDate?.()?.toISOString() || null,
        lastCompletedAt: lastCompletedAt?.toISOString() || null,
        scheduledAt: data.scheduledAt?.toDate?.()?.toISOString() || null,
        priority: data.priority || 0,
        googleCalendarEventId: data.googleCalendarEventId || null,
        subtasks: data.subtasks || [],
      };
    });

    return { tasks };
  }
);
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
// 名前パーツ方式
// ===============================================

/**
 * 名前パーツマスタを初期化する関数（管理者用）
 */
export const initializeNameParts = onCall(
  { region: "asia-northeast1" },
  async () => {
    const batch = db.batch();
    let prefixCount = 0;
    let suffixCount = 0;

    // 形容詞パーツを追加
    for (const part of PREFIX_PARTS) {
      const docRef = db.collection("nameParts").doc(`prefix_${part.id} `);
      batch.set(docRef, {
        ...part,
        type: "prefix",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      prefixCount++;
    }

    // 名詞パーツを追加
    for (const part of SUFFIX_PARTS) {
      const docRef = db.collection("nameParts").doc(`suffix_${part.id} `);
      batch.set(docRef, {
        ...part,
        type: "suffix",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      suffixCount++;
    }

    await batch.commit();

    console.log(`Initialized ${prefixCount} prefix parts and ${suffixCount} suffix parts`);

    return {
      success: true,
      message: `名前パーツを初期化しました`,
      prefixCount,
      suffixCount,
    };
  }
);

/**
 * 名前パーツ一覧を取得する関数
 */
export const getNameParts = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;

    // ユーザーのアンロック済みパーツを取得
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    const unlockedParts: string[] = userData?.unlockedNameParts || [];
    const isAI = userData?.isAI || false;

    // 全パーツを取得
    const partsSnapshot = await db.collection("nameParts").orderBy("order").get();

    const prefixes: (NamePart & { unlocked: boolean })[] = [];
    const suffixes: (NamePart & { unlocked: boolean })[] = [];

    partsSnapshot.docs.forEach((doc) => {
      const data = doc.data() as NamePart & { type: string };
      const partId = doc.id;

      // ノーマルは最初からアンロック、それ以外はアンロック済みリストに含まれているか確認
      const isUnlocked = data.rarity === "normal" || unlockedParts.includes(partId);

      // AIはスーパーレア以上を持てない
      if (isAI && (data.rarity === "super_rare" || data.rarity === "ultra_rare")) {
        return;
      }

      const partWithUnlock = {
        ...data,
        id: partId,
        unlocked: isUnlocked,
      };

      if (data.type === "prefix") {
        prefixes.push(partWithUnlock);
      } else {
        suffixes.push(partWithUnlock);
      }
    });

    return {
      prefixes,
      suffixes,
      currentPrefix: userData?.namePrefix || null,
      currentSuffix: userData?.nameSuffix || null,
    };
  }
);

/**
 * ユーザー名を更新する関数
 */
export const updateUserName = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const { prefixId, suffixId } = request.data;

    if (!prefixId || !suffixId) {
      throw new HttpsError("invalid-argument", "パーツIDが必要です");
    }

    // ユーザー情報を取得
    const userRef = db.collection("users").doc(userId);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      throw new HttpsError("not-found", "ユーザーが見つかりません");
    }

    const userData = userDoc.data()!;
    const unlockedParts: string[] = userData.unlockedNameParts || [];

    // パーツを取得
    const prefixDoc = await db.collection("nameParts").doc(prefixId).get();
    const suffixDoc = await db.collection("nameParts").doc(suffixId).get();

    if (!prefixDoc.exists || !suffixDoc.exists) {
      throw new HttpsError("not-found", "パーツが見つかりません");
    }

    const prefixData = prefixDoc.data() as NamePart;
    const suffixData = suffixDoc.data() as NamePart;

    // アンロック済みか確認（ノーマルは最初からOK）
    const prefixUnlocked = prefixData.rarity === "normal" || unlockedParts.includes(prefixId);
    const suffixUnlocked = suffixData.rarity === "normal" || unlockedParts.includes(suffixId);

    if (!prefixUnlocked || !suffixUnlocked) {
      throw new HttpsError("permission-denied", "アンロックしていないパーツは使用できません");
    }

    // 名前変更回数チェック（月1回まで）
    const lastNameChange = userData.lastNameChangeAt?.toDate();
    const now = new Date();

    if (lastNameChange) {
      const lastChangeMonth = lastNameChange.getMonth();
      const lastChangeYear = lastNameChange.getFullYear();
      const currentMonth = now.getMonth();
      const currentYear = now.getFullYear();

      // 同じ月に既に変更している場合（初回設定は除く）
      if (
        userData.namePrefix && // 既に名前が設定されている場合のみチェック
        lastChangeYear === currentYear &&
        lastChangeMonth === currentMonth
      ) {
        throw new HttpsError(
          "resource-exhausted",
          "名前の変更は月1回までです。来月まで待ってね！"
        );
      }
    }

    // 新しい表示名を生成
    const newDisplayName = `${prefixData.text}${suffixData.text} `;

    // 更新
    await userRef.update({
      namePrefix: prefixId,
      nameSuffix: suffixId,
      displayName: newDisplayName,
      lastNameChangeAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`User ${userId} changed name to: ${newDisplayName} `);

    return {
      success: true,
      displayName: newDisplayName,
      message: `名前を「${newDisplayName}」に変更しました！`,
    };
  }
);

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
    const message = {
      token: fcmToken,
      notification: {
        title,
        body,
      },
      data: data || {},
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
  // Cloud Tasks からのリクエスト以外は拒否（簡易的なセキュリティチェック）
  const authHeader = request.headers["authorization"];
  if (!authHeader) {
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
      persona = {
        id: personaId,
        name: personaName,
        namePrefixId: "",
        nameSuffixId: "",
        gender: personaGender || "female" as Gender,
        ageGroup: personaAgeGroup || "twenties" as AgeGroup,
        occupation: personaOccupation || { id: "student", name: "頑張り中", bio: "" },
        personality: personaPersonality || {
          id: "bright",
          name: "明るい",
          trait: "ポジティブで元気",
          style: "「！」多め、絵文字使う",
          examples: ["すごい！", "いいね！", "頑張ってる！"],
          reactionType: "褒める",
          reactionGuide: "相手の行動や結果を素直に褒めてください。",
        },
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
        const existingComments = existingCommentsSnapshot.docs.map(doc => {
          const data = doc.data();
          const commentText = `- ${data.userDisplayName || "AI"}: 「${data.content}」`;
          console.log(`[DUPLICATE CHECK] Found: ${commentText.substring(0, 80)}...`);
          return commentText;
        });
        existingCommentsContext = `
【既に投稿されているコメント】
以下過去のコメントで使われている単語・フレーズは絶対に使わないでください。
まったく異なる言い回しで、別の角度から返信してください：
例：お疲れ様というフレーズが既に使われていたら、頑張ったね！に変えるなど
【以下過去のコメント】
${existingComments.join("\n")}
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
        prompt = prompt.replace(
          "【あなた（" + persona.name + "）の返信】",
          additionalContext + "\n\n【あなた（" + persona.name + "）の返信】"
        );
      }
    } else {
      // 一般投稿: 従来のプロンプトを使用
      prompt = `
${getSystemPrompt(persona, userDisplayName)}

【${userDisplayName}さんの投稿】
${postContent || "(テキストなし)"}${mediaContext}
${existingCommentsContext}
【重要】
${mediaDescriptions && mediaDescriptions.length > 0
          ? "添付されたメディア（画像・動画）の内容も考慮して、具体的に褒めてください。"
          : ""}

【あなた（${persona.name}）の返信】
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
        "申し訳ありませんが、現在コメントできません。"
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
  // 簡易セキュリティチェック
  const authHeader = request.headers["authorization"];
  if (!authHeader) {
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
 * 管理用: 全ユーザーのフォローリストを掃除する (v1)
 * 存在しないユーザーIDをフォローリストから削除し、カウントを整合させます。
 */
export const cleanUpUserFollows = functionsV1.region("asia-northeast1").https.onRequest(async (request, response) => {
  const key = request.query.key;
  if (key !== "admin_secret_homeppu_2025") {
    response.status(403).send("Forbidden");
    return;
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

    response.status(200).send(`Cleanup complete. Updated ${updatedCount} users.`);

  } catch (error) {
    console.error("Error cleaning up follows:", error);
    response.status(500).send("Internal Server Error");
  }
});

/**
 * 管理用: 全てのAIユーザーを削除する (v1)
 * AIユーザーとその投稿、コメント、リアクションを全て削除します。
 */
export const deleteAllAIUsers = functionsV1.region("asia-northeast1").runWith({
  timeoutSeconds: 540, // 処理が重くなる可能性があるので長めに
  memory: "1GB"
}).https.onCall(async (data, context) => {
  // 簡易セキュリティ: ログイン必須
  if (!context.auth) {
    throw new functionsV1.https.HttpsError("unauthenticated", "ログインが必要です");
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
  async () => {
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
  // Cloud Tasks からのリクエスト以外は拒否（簡易的なセキュリティチェック）
  // 実際にはOIDCトークン検証が推奨されますが、ここでは最低限のヘッダーチェックを行います
  const authHeader = request.headers["authorization"];
  if (!authHeader) {
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
    const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;

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
    const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;

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
  // Cloud Tasksからのリクエスト以外は拒否
  const authHeader = request.headers["authorization"];
  if (!authHeader) {
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

    // 通知を送信
    const title = type === "on_time" ? "📋 タスクの時間です" : "🔔 タスクリマインダー";
    const body = type === "on_time"
      ? `「${taskContent}」の予定時刻になりました`
      : `「${taskContent}」の${timeLabel}です`;

    await admin.messaging().send({
      token: fcmToken,
      notification: { title, body },
      data: {
        type: type === "on_time" ? "task_due" : "task_reminder",
        taskId: taskId,
      },
      android: {
        priority: "high",
        notification: {
          sound: "default",
          channelId: "task_reminders",
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
// サークル削除（ソフトデリート方式）
// 即座にUIから削除し、バックグラウンドでデータをクリーンアップ
// 1万投稿以上にも対応
// ===============================================
export const deleteCircle = onCall(
  {
    region: "asia-northeast1",
    timeoutSeconds: 60, // 即座にレスポンスするため短く
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "認証が必要です");
    }

    const { circleId, reason } = request.data;
    const userId = request.auth.uid;

    if (!circleId) {
      throw new HttpsError("invalid-argument", "circleIdが必要です");
    }

    console.log(`=== deleteCircle START: circleId=${circleId}, userId=${userId} ===`);

    try {
      // 1. サークル情報を取得
      const circleDoc = await db.collection("circles").doc(circleId).get();
      if (!circleDoc.exists) {
        throw new HttpsError("not-found", "サークルが見つかりません");
      }

      const circleData = circleDoc.data()!;
      const ownerId = circleData.ownerId;
      const circleName = circleData.name;
      const memberIds: string[] = circleData.memberIds || [];

      // オーナーチェック
      if (ownerId !== userId) {
        throw new HttpsError("permission-denied", "サークル削除はオーナーのみ可能です");
      }

      // 2. サークルをソフトデリート（即座にUIから非表示）
      await db.collection("circles").doc(circleId).update({
        isDeleted: true,
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        deletedBy: userId,
        deleteReason: reason || null,
      });

      console.log(`Soft deleted circle: ${circleName}`);

      // 3. メンバーに通知送信（オーナー以外）
      const ownerDoc = await db.collection("users").doc(ownerId).get();
      const ownerName = ownerDoc.exists ? ownerDoc.data()?.displayName || "オーナー" : "オーナー";

      const notificationMessage = reason && reason.trim()
        ? `${circleName}が削除されました。理由: ${reason}`
        : `${circleName}が削除されました`;
      const notificationTitle = `${ownerName}さんがサークルを削除しました`;

      // 通知はバックグラウンドで送信（Promise.allで高速化）
      const notificationPromises = memberIds
        .filter((id) => id !== ownerId && !id.startsWith("circle_ai_"))
        .map(async (memberId) => {
          try {
            await db.collection("users").doc(memberId).collection("notifications").add({
              type: "circle_deleted",
              senderId: ownerId,
              senderName: ownerName,
              senderAvatarUrl: ownerDoc.data()?.avatarIndex?.toString() || "0",
              title: "サークルを削除しました",
              body: notificationMessage,
              circleName: circleName,
              isRead: false,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            const userDoc = await db.collection("users").doc(memberId).get();
            if (userDoc.data()?.fcmToken) {
              await admin.messaging().send({
                token: userDoc.data()!.fcmToken,
                notification: { title: notificationTitle, body: notificationMessage },
                data: { type: "circle_deleted", circleName: circleName },
              });
            }
          } catch (e) {
            console.error(`Notification failed for ${memberId}:`, e);
          }
        });

      await Promise.all(notificationPromises);

      // 4. バックグラウンドクリーンアップをスケジュール
      const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
      const location = LOCATION;
      const queue = "circle-cleanup";

      const tasksClient = new CloudTasksClient();
      const queuePath = tasksClient.queuePath(project, location, queue);
      const targetUrl = `https://${location}-${project}.cloudfunctions.net/cleanupDeletedCircle`;
      const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;

      const payload = { circleId, circleName };
      const task = {
        httpRequest: {
          httpMethod: "POST" as const,
          url: targetUrl,
          body: Buffer.from(JSON.stringify(payload)).toString("base64"),
          headers: { "Content-Type": "application/json" },
          oidcToken: { serviceAccountEmail },
        },
        scheduleTime: { seconds: Math.floor(Date.now() / 1000) + 5 }, // 5秒後に開始
      };

      await tasksClient.createTask({ parent: queuePath, task });
      console.log(`Scheduled cleanup task for circle: ${circleId}`);

      console.log(`=== deleteCircle SUCCESS: ${circleName} ===`);
      return { success: true, message: `${circleName}を削除しました` };

    } catch (error) {
      console.error(`=== deleteCircle ERROR:`, error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", `削除に失敗しました: ${error}`);
    }
  }
);

/**
 * バックグラウンドでサークルデータをクリーンアップ
 * Cloud Tasksから呼び出される
 * 100投稿ずつ処理し、残りがあれば自分自身を再スケジュール
 */
export const cleanupDeletedCircle = functionsV1.region("asia-northeast1").runWith({
  timeoutSeconds: 540,
  memory: "1GB",
}).https.onRequest(async (request, response) => {
  try {
    // 認証チェック
    const authHeader = request.headers.authorization || "";
    if (!authHeader.startsWith("Bearer ")) {
      console.error("Missing or invalid authorization header");
      response.status(401).send("Unauthorized");
      return;
    }

    // リクエストボディを取得（Cloud Tasksからは既にパース済みの場合がある）
    let payload: { circleId: string; circleName: string };
    if (typeof request.body === "string") {
      // Base64文字列の場合
      payload = JSON.parse(Buffer.from(request.body, "base64").toString());
    } else if (request.body && typeof request.body === "object") {
      // 既にJSONオブジェクトの場合
      payload = request.body as { circleId: string; circleName: string };
    } else {
      console.error("Invalid request body:", request.body);
      response.status(400).send("Invalid request body");
      return;
    }

    const { circleId, circleName } = payload;

    if (!circleId) {
      console.error("Missing circleId in payload");
      response.status(400).send("Missing circleId");
      return;
    }

    console.log(`=== cleanupDeletedCircle START: ${circleId} ===`);

    // 1. まず投稿を100件取得
    const BATCH_LIMIT = 100;
    const postsSnapshot = await db
      .collection("posts")
      .where("circleId", "==", circleId)
      .limit(BATCH_LIMIT)
      .get();

    console.log(`Found ${postsSnapshot.size} posts to process`);

    if (postsSnapshot.size > 0) {
      // 削除対象を収集
      const deleteRefs: FirebaseFirestore.DocumentReference[] = [];
      const mediaDeletePromises: Promise<void>[] = [];

      for (const postDoc of postsSnapshot.docs) {
        const postId = postDoc.id;
        const postData = postDoc.data();

        // コメント収集
        const comments = await db.collection("comments").where("postId", "==", postId).get();
        comments.docs.forEach((c) => deleteRefs.push(c.ref));

        // リアクション収集
        const reactions = await db.collection("reactions").where("postId", "==", postId).get();
        reactions.docs.forEach((r) => deleteRefs.push(r.ref));

        // メディア削除
        const mediaItems = postData.mediaItems || [];
        for (const media of mediaItems) {
          if (media.url && media.url.includes("firebasestorage.googleapis.com")) {
            const urlParts = media.url.split("/o/")[1];
            if (urlParts) {
              const filePath = decodeURIComponent(urlParts.split("?")[0]);
              mediaDeletePromises.push(
                admin.storage().bucket().file(filePath).delete()
                  .then(() => { })
                  .catch((e) => console.error(`Storage delete failed: ${filePath}`, e))
              );
            }
          }
        }

        deleteRefs.push(postDoc.ref);
      }

      // バッチ削除
      const MAX_BATCH = 400;
      for (let i = 0; i < deleteRefs.length; i += MAX_BATCH) {
        const batch = db.batch();
        deleteRefs.slice(i, i + MAX_BATCH).forEach((ref) => batch.delete(ref));
        await batch.commit();
      }

      // メディア並列削除
      await Promise.all(mediaDeletePromises.slice(0, 50));
      for (let i = 50; i < mediaDeletePromises.length; i += 50) {
        await Promise.all(mediaDeletePromises.slice(i, i + 50));
      }

      console.log(`Deleted ${postsSnapshot.size} posts and related data`);

      // まだ投稿が残っているか確認
      const remainingPosts = await db
        .collection("posts")
        .where("circleId", "==", circleId)
        .limit(1)
        .get();

      if (!remainingPosts.empty) {
        // 自分自身を再スケジュール
        const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
        const tasksClient = new CloudTasksClient();
        const queuePath = tasksClient.queuePath(project, LOCATION, "circle-cleanup");
        const targetUrl = `https://${LOCATION}-${project}.cloudfunctions.net/cleanupDeletedCircle`;

        await tasksClient.createTask({
          parent: queuePath,
          task: {
            httpRequest: {
              httpMethod: "POST" as const,
              url: targetUrl,
              body: Buffer.from(JSON.stringify({ circleId, circleName })).toString("base64"),
              headers: { "Content-Type": "application/json" },
              oidcToken: { serviceAccountEmail: `${project}@appspot.gserviceaccount.com` },
            },
            scheduleTime: { seconds: Math.floor(Date.now() / 1000) + 2 },
          },
        });

        console.log(`Scheduled next cleanup batch for ${circleId}`);
        response.status(200).send(`Processed ${postsSnapshot.size} posts, more remaining`);
        return;
      }
    }

    // 2. 全投稿削除完了 → 参加申請削除
    const joinRequests = await db.collection("circleJoinRequests").where("circleId", "==", circleId).get();
    const reqBatch = db.batch();
    joinRequests.docs.forEach((doc) => reqBatch.delete(doc.ref));
    if (joinRequests.size > 0) await reqBatch.commit();
    console.log(`Deleted ${joinRequests.size} join requests`);

    // 3. サークル画像をStorageから削除（icon, cover）
    try {
      const bucket = admin.storage().bucket();
      const [files] = await bucket.getFiles({ prefix: `circles/${circleId}/` });
      for (const file of files) {
        await file.delete().catch((e) => console.error(`Storage delete failed: ${file.name}`, e));
      }
      console.log(`Deleted ${files.length} circle image files from Storage`);
    } catch (storageError) {
      console.error("Circle image storage cleanup error:", storageError);
      // Storage削除失敗しても処理は継続
    }

    // 4. サークルAIアカウント削除（サブコレクション含む）
    const circleDoc = await db.collection("circles").doc(circleId).get();
    if (circleDoc.exists) {
      const generatedAIs = circleDoc.data()?.generatedAIs || [];
      for (const ai of generatedAIs) {
        if (ai.id && ai.id.startsWith("circle_ai_")) {
          const aiUserRef = db.collection("users").doc(ai.id);

          // サブコレクション（notifications）を削除
          const notificationsSnapshot = await aiUserRef.collection("notifications").get();
          if (!notificationsSnapshot.empty) {
            const subBatch = db.batch();
            notificationsSnapshot.docs.forEach(doc => subBatch.delete(doc.ref));
            await subBatch.commit();
            console.log(`Deleted ${notificationsSnapshot.size} notifications for AI ${ai.id}`);
          }

          // AIユーザードキュメント本体を削除
          await aiUserRef.delete().catch(() => { });
        }
      }
      console.log(`Deleted ${generatedAIs.length} AI accounts with subcollections`);

      // 5. サークル本体を完全削除
      await circleDoc.ref.delete();
      console.log(`Permanently deleted circle: ${circleName}`);
    }

    console.log(`=== cleanupDeletedCircle COMPLETE: ${circleId} ===`);
    response.status(200).send("Cleanup complete");

  } catch (error) {
    console.error("cleanupDeletedCircle ERROR:", error);
    response.status(500).send(`Error: ${error}`);
  }
});

/**
 * 参加申請を承認
 */
export const approveJoinRequest = onCall(
  {
    region: "asia-northeast1",
  },
  async (request) => {
    const { requestId, circleId, circleName } = request.data;
    const userId = request.auth?.uid;

    if (!userId) {
      throw new HttpsError("unauthenticated", "認証が必要です");
    }

    if (!requestId || !circleId) {
      throw new HttpsError("invalid-argument", "必要なパラメータがありません");
    }

    try {
      const db = admin.firestore();

      // サークル情報を取得してオーナーチェック
      const circleDoc = await db.collection("circles").doc(circleId).get();
      if (!circleDoc.exists) {
        throw new HttpsError("not-found", "サークルが見つかりません");
      }
      if (circleDoc.data()?.ownerId !== userId) {
        throw new HttpsError("permission-denied", "オーナーのみ承認できます");
      }

      // 申請情報を取得
      const requestDoc = await db.collection("circleJoinRequests").doc(requestId).get();
      if (!requestDoc.exists) {
        throw new HttpsError("not-found", "申請が見つかりません");
      }
      const requestData = requestDoc.data()!;
      const applicantId = requestData.userId;

      // 申請を承認済みに更新
      await db.collection("circleJoinRequests").doc(requestId).update({
        status: "approved",
      });

      // サークルにメンバーを追加
      await db.collection("circles").doc(circleId).update({
        memberIds: admin.firestore.FieldValue.arrayUnion(applicantId),
        memberCount: admin.firestore.FieldValue.increment(1),
      });

      // 申請者の表示名を取得
      const ownerDoc = await db.collection("users").doc(userId).get();
      const ownerName = ownerDoc.data()?.displayName || "オーナー";

      // 申請者に通知を送信
      await db.collection("users").doc(applicantId).collection("notifications").add({
        type: "join_request_approved",
        senderId: userId,
        senderName: ownerName,
        senderAvatarUrl: ownerDoc.data()?.avatarIndex?.toString() || "0",
        title: "参加を承認しました",
        body: `${circleName || "サークル"}への参加が承認されました！`,
        circleName: circleName,
        circleId: circleId,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`=== approveJoinRequest SUCCESS: ${requestId} ===`);
      return { success: true };

    } catch (error) {
      console.error(`=== approveJoinRequest ERROR:`, error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", `承認に失敗しました: ${error}`);
    }
  }
);

/**
 * 参加申請を拒否
 */
export const rejectJoinRequest = onCall(
  {
    region: "asia-northeast1",
  },
  async (request) => {
    const { requestId, circleId, circleName } = request.data;
    const userId = request.auth?.uid;

    if (!userId) {
      throw new HttpsError("unauthenticated", "認証が必要です");
    }

    if (!requestId || !circleId) {
      throw new HttpsError("invalid-argument", "必要なパラメータがありません");
    }

    try {
      const db = admin.firestore();

      // サークル情報を取得してオーナーチェック
      const circleDoc = await db.collection("circles").doc(circleId).get();
      if (!circleDoc.exists) {
        throw new HttpsError("not-found", "サークルが見つかりません");
      }
      if (circleDoc.data()?.ownerId !== userId) {
        throw new HttpsError("permission-denied", "オーナーのみ拒否できます");
      }

      // 申請情報を取得
      const requestDoc = await db.collection("circleJoinRequests").doc(requestId).get();
      if (!requestDoc.exists) {
        throw new HttpsError("not-found", "申請が見つかりません");
      }
      const requestData = requestDoc.data()!;
      const applicantId = requestData.userId;

      // 申請を拒否済みに更新
      await db.collection("circleJoinRequests").doc(requestId).update({
        status: "rejected",
      });

      // オーナーの表示名を取得
      const ownerDoc = await db.collection("users").doc(userId).get();
      const ownerName = ownerDoc.data()?.displayName || "オーナー";

      // 申請者に通知を送信
      await db.collection("users").doc(applicantId).collection("notifications").add({
        type: "join_request_rejected",
        senderId: userId,
        senderName: ownerName,
        senderAvatarUrl: ownerDoc.data()?.avatarIndex?.toString() || "0",
        title: "参加申請が拒否されました",
        body: `${circleName || "サークル"}への参加申請は承認されませんでした`,
        circleName: circleName,
        circleId: circleId,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`=== rejectJoinRequest SUCCESS: ${requestId} ===`);
      return { success: true };

    } catch (error) {
      console.error(`=== rejectJoinRequest ERROR:`, error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", `拒否に失敗しました: ${error}`);
    }
  }
);

/**
 * 参加申請を送信（オーナーに通知）
 */
export const sendJoinRequest = onCall(
  {
    region: "asia-northeast1",
  },
  async (request) => {
    const { circleId } = request.data;
    const userId = request.auth?.uid;

    if (!userId) {
      throw new HttpsError("unauthenticated", "認証が必要です");
    }

    if (!circleId) {
      throw new HttpsError("invalid-argument", "サークルIDが必要です");
    }

    try {
      const db = admin.firestore();

      // サークル情報を取得
      const circleDoc = await db.collection("circles").doc(circleId).get();
      if (!circleDoc.exists) {
        throw new HttpsError("not-found", "サークルが見つかりません");
      }
      const circleData = circleDoc.data()!;
      const ownerId = circleData.ownerId;
      const circleName = circleData.name;

      // 既に申請中かチェック
      const existingRequest = await db
        .collection("circleJoinRequests")
        .where("circleId", "==", circleId)
        .where("userId", "==", userId)
        .where("status", "==", "pending")
        .limit(1)
        .get();

      if (!existingRequest.empty) {
        throw new HttpsError("already-exists", "既に申請中です");
      }

      // 申請を作成
      await db.collection("circleJoinRequests").add({
        circleId: circleId,
        userId: userId,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 申請者の情報を取得
      const applicantDoc = await db.collection("users").doc(userId).get();
      const applicantName = applicantDoc.data()?.displayName || "ユーザー";

      // アプリ内通知を送信
      await db.collection("users").doc(ownerId).collection("notifications").add({
        type: "join_request_received",
        senderId: userId,
        senderName: applicantName,
        senderAvatarUrl: applicantDoc.data()?.avatarIndex?.toString() || "0",
        title: "参加申請が届きました",
        body: `${applicantName}さんが${circleName}への参加を申請しました`,
        circleName: circleName,
        circleId: circleId,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // プッシュ通知を送信
      try {
        const ownerDoc = await db.collection("users").doc(ownerId).get();
        const ownerFcmToken = ownerDoc.data()?.fcmToken;

        if (ownerFcmToken) {
          await admin.messaging().send({
            token: ownerFcmToken,
            notification: {
              title: `${applicantName}さんから参加申請`,
              body: `${circleName}への参加申請が届きました`,
            },
            data: {
              type: "join_request_received",
              circleId: circleId,
            },
            android: {
              priority: "high",
              notification: {
                channelId: "default",
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
          console.log(`Push notification sent to owner: ${ownerId}`);
        }
      } catch (pushError) {
        console.error(`Failed to send push notification:`, pushError);
        // プッシュ通知失敗は無視して続行
      }

      console.log(`=== sendJoinRequest SUCCESS: ${userId} -> ${circleId} ===`);
      return { success: true };

    } catch (error) {
      console.error(`=== sendJoinRequest ERROR:`, error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", `申請に失敗しました: ${error}`);
    }
  }
);

// ===============================================
// サークルAI生成
// サークル作成時に自動でAI3体を生成
// ===============================================

/**
 * サークル専用AIペルソナを生成する関数
 * サークルの説明からテーマ・レベル感を抽出してペルソナに反映
 */
function generateCircleAIPersona(
  circleInfo: { name: string; description: string; category: string },
  index: number
): {
  id: string;
  name: string;
  namePrefixId: string;
  nameSuffixId: string;
  gender: Gender;
  ageGroup: AgeGroup;
  occupation: { id: string; name: string; bio: string };
  personality: { id: string; name: string; trait: string; style: string };
  avatarIndex: number;
  bio: string;
  circleContext: string;
  growthLevel: number;
  lastGrowthAt: Date;
} {
  // 性別を決定（インデックスで分散）
  const gender: Gender = index % 2 === 0 ? "female" : "male";

  // 各カテゴリをランダムに選択
  const occupations = OCCUPATIONS[gender];
  const personalities = PERSONALITIES[gender];

  const occupation = occupations[(index * 7) % occupations.length];
  const personality = personalities[(index * 3) % personalities.length];
  const ageGroup: AgeGroup = (["late_teens", "twenties", "thirties"] as const)[index % 3];

  // 名前パーツからランダム選択
  const prefixIndex = (index * 13) % AI_USABLE_PREFIXES.length;
  const suffixIndex = (index * 17) % AI_USABLE_SUFFIXES.length;
  const namePrefix = AI_USABLE_PREFIXES[prefixIndex];
  const nameSuffix = AI_USABLE_SUFFIXES[suffixIndex];
  const name = `${namePrefix.text}${nameSuffix.text}`;

  // アバターインデックス
  const avatarIndex = (index * 11) % 10;

  // サークルのコンテキストを生成
  const circleContext = `サークル「${circleInfo.name}」のメンバー。${circleInfo.description}`;

  // 一般AIと同じbio生成ロジックを使用
  const occupationBios = BIO_TEMPLATES[occupation.id] || {};
  const personalityBios = occupationBios[personality.id] || [];

  // bioが見つからない場合はデフォルト
  let bio: string;
  if (personalityBios.length > 0) {
    bio = personalityBios[index % personalityBios.length];
  } else {
    // フォールバック：シンプルだけど自然なbio
    const defaultBios = [
      `${occupation.name} してます！よろしくね✨`,
      `${occupation.name} やってます。毎日頑張ってる`,
      `${occupation.name} です。趣味は読書と散歩`,
    ];
    bio = defaultBios[index % defaultBios.length];
  }

  return {
    id: `circle_ai_${Date.now()}_${index}`,
    name: name.trim(),
    namePrefixId: `prefix_${namePrefix.id}`,
    nameSuffixId: `suffix_${nameSuffix.id}`,
    gender,
    ageGroup,
    occupation,
    personality,
    avatarIndex,
    bio,
    circleContext,
    growthLevel: 0, // 初期成長レベル（初心者）
    lastGrowthAt: new Date(),
  };
}

/**
 * サークル作成時にAI3体を自動生成
 */
export const onCircleCreated = onDocumentCreated(
  "circles/{circleId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No document data");
      return;
    }

    const circleData = snapshot.data();
    const circleId = event.params.circleId;

    console.log(`=== onCircleCreated: ${circleId} ===`);
    console.log(`Circle name: ${circleData.name}, AI mode: ${circleData.aiMode}`);

    // humanOnlyモードの場合はAIを生成しない
    if (circleData.aiMode === "humanOnly") {
      console.log(`Circle ${circleId} is humanOnly mode, skipping AI generation`);
      return;
    }

    try {
      // サークル情報を取得
      const circleInfo = {
        name: circleData.name || "",
        description: circleData.description || "",
        category: circleData.category || "その他",
      };

      // AI3体を生成してusersコレクションに作成
      const generatedAIs = [];
      const aiMemberIds = [];
      const batch = db.batch();

      for (let i = 0; i < 3; i++) {
        const aiPersona = generateCircleAIPersona(circleInfo, i);
        generatedAIs.push(aiPersona);

        // usersコレクションにAIユーザードキュメントを作成
        const aiUserRef = db.collection("users").doc(aiPersona.id);
        batch.set(aiUserRef, {
          uid: aiPersona.id,
          displayName: aiPersona.name,
          bio: aiPersona.bio,
          avatarIndex: aiPersona.avatarIndex,
          namePrefixId: aiPersona.namePrefixId,
          nameSuffixId: aiPersona.nameSuffixId,
          isAI: true,
          circleId: circleId, // このAIが所属するサークル
          circleContext: aiPersona.circleContext,
          growthLevel: aiPersona.growthLevel,
          lastGrowthAt: admin.firestore.Timestamp.fromDate(aiPersona.lastGrowthAt),
          publicMode: "mix", // AIはmixモードで動作
          virtue: 100, // 初期徳ポイント
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        aiMemberIds.push(aiPersona.id);
        console.log(`Generated AI ${i + 1}: ${aiPersona.name} (${aiPersona.id})`);
      }

      // バッチでAIユーザーを作成
      await batch.commit();

      // サークルドキュメントを更新（AI情報とメンバー数を更新）
      const currentMemberIds = circleData.memberIds || [];
      const updatedMemberIds = [...currentMemberIds, ...aiMemberIds];

      await db.collection("circles").doc(circleId).update({
        generatedAIs: generatedAIs,
        memberIds: updatedMemberIds,
        memberCount: updatedMemberIds.length,
      });

      console.log(`=== onCircleCreated SUCCESS: Added ${generatedAIs.length} AIs to ${circleId} ===`);

    } catch (error) {
      console.error(`=== onCircleCreated ERROR:`, error);
    }
  }
);

/**
 * サークル設定変更時にメンバーへ通知
 */
export const onCircleUpdated = onDocumentUpdated(
  "circles/{circleId}",
  async (event) => {
    const beforeData = event.data?.before?.data();
    const afterData = event.data?.after?.data();
    const circleId = event.params.circleId;

    if (!beforeData || !afterData) {
      console.log("No document data");
      return;
    }

    console.log(`=== onCircleUpdated START: ${circleId} ===`);

    try {
      // 通知すべき変更を検出
      const changes: string[] = [];

      // 変更された項目をチェック
      if (beforeData.name !== afterData.name) {
        changes.push(`名前: ${beforeData.name} → ${afterData.name}`);
      }
      if (beforeData.description !== afterData.description) {
        changes.push("説明が変更されました");
      }
      if (beforeData.category !== afterData.category) {
        changes.push(`カテゴリ: ${beforeData.category} → ${afterData.category}`);
      }
      if (beforeData.goal !== afterData.goal) {
        changes.push("目標が変更されました");
      }
      if (beforeData.rules !== afterData.rules) {
        changes.push("ルールが変更されました");
      }
      if (beforeData.isPublic !== afterData.isPublic) {
        changes.push(afterData.isPublic ? "公開に変更" : "非公開に変更");
      }
      if (beforeData.isInviteOnly !== afterData.isInviteOnly) {
        changes.push(afterData.isInviteOnly ? "招待制に変更" : "招待制を解除");
      }
      if (beforeData.participationMode !== afterData.participationMode) {
        const modeLabels: { [key: string]: string } = {
          ai: "AIモード",
          mix: "MIXモード",
          human: "人間モード",
        };
        const oldMode = modeLabels[beforeData.participationMode] || beforeData.participationMode;
        const newMode = modeLabels[afterData.participationMode] || afterData.participationMode;
        changes.push(`参加モード: ${oldMode} → ${newMode}`);
      }

      // AI情報やメンバー数など内部的な更新は通知しない
      if (changes.length === 0) {
        console.log("No user-facing changes detected, skipping notification");
        return;
      }

      console.log(`Changes detected: ${changes.join(", ")}`);

      // オーナー情報を取得
      const ownerId = afterData.ownerId;
      const ownerDoc = await db.collection("users").doc(ownerId).get();
      const ownerName = ownerDoc.exists ? ownerDoc.data()?.displayName || "オーナー" : "オーナー";
      const ownerAvatarIndex = ownerDoc.exists ? ownerDoc.data()?.avatarIndex?.toString() || "0" : "0";

      // メンバー一覧を取得（オーナーとAI以外）
      const memberIds: string[] = afterData.memberIds || [];
      const circleName = afterData.name;

      // 通知メッセージ
      const notificationBody = changes.length === 1
        ? changes[0]
        : `${changes.length}件の設定が変更されました`;

      // 各メンバーに通知
      for (const memberId of memberIds) {
        if (memberId === ownerId) continue;
        if (memberId.startsWith("circle_ai_")) continue; // AIはスキップ

        try {
          // アプリ内通知を作成
          await db.collection("users").doc(memberId).collection("notifications").add({
            type: "circle_settings_changed",
            senderId: ownerId,
            senderName: ownerName,
            senderAvatarUrl: ownerAvatarIndex,
            title: "サークルが更新されました",
            body: `${circleName}: ${notificationBody}`,
            circleName: circleName,
            circleId: circleId,
            changes: changes,
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          // プッシュ通知
          const userDoc = await db.collection("users").doc(memberId).get();
          const userData = userDoc.data();
          if (userData?.fcmToken) {
            await admin.messaging().send({
              token: userData.fcmToken,
              notification: {
                title: `🔔 ${circleName}`,
                body: notificationBody,
              },
              data: {
                type: "circle_settings_changed",
                circleId: circleId,
                circleName: circleName,
              },
            });
          }
        } catch (notifyError) {
          console.error(`Failed to notify member ${memberId}:`, notifyError);
        }
      }

      console.log(`=== onCircleUpdated SUCCESS: Notified ${memberIds.length - 1} members ===`);

    } catch (error) {
      console.error(`=== onCircleUpdated ERROR:`, error);
    }
  }
);

// ===============================================
// サークルAI投稿機能 (v1.1)
// Cloud Schedulerで1日1回実行、各サークルのAIが投稿
// ===============================================

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
${recentPosts.map((p, i) => `- ${p}`).join("\n")}
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
const MAX_CIRCLES_PER_RUN = 3; // テスト用：本番は100

export const generateCircleAIPosts = functionsV1.region("asia-northeast1").runWith({
  secrets: ["GEMINI_API_KEY"],
  timeoutSeconds: 120,
  memory: "256MB",
}).pubsub.schedule("0 9,20 * * *").timeZone("Asia/Tokyo").onRun(async () => {
  console.log("=== generateCircleAIPosts START (Scheduler - Optimized) ===");

  try {
    const tasksClient = new CloudTasksClient();
    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    const queue = "generate-circle-ai-posts";
    const location = "asia-northeast1";

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
      const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;

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
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
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
export const executeCircleAIPost = functionsV1.region("asia-northeast1").runWith({
  secrets: ["GEMINI_API_KEY"],
  timeoutSeconds: 60,
}).https.onRequest(async (request, response) => {
  // Cloud Tasksからのリクエスト以外は拒否
  const authHeader = request.headers["authorization"];
  if (!authHeader) {
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
    const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

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
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // サークルの投稿数を更新
    await db.collection("circles").doc(circleId).update({
      postCount: admin.firestore.FieldValue.increment(1),
      recentActivity: admin.firestore.FieldValue.serverTimestamp(),
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
  { region: "asia-northeast1", secrets: [geminiApiKey], timeoutSeconds: 300 },
  async () => {
    console.log("=== triggerCircleAIPosts (manual - optimized) START ===");

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      return { success: false, message: "GEMINI_API_KEY is not set" };
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

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
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          await db.collection("circles").doc(circleId).update({
            postCount: admin.firestore.FieldValue.increment(1),
            recentActivity: admin.firestore.FieldValue.serverTimestamp(),
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
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
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


// ===============================================
// サークルAI成長システム (v1.2)
// 月1回実行、AIのgrowthLevelを上げる
// growthLevel: 0=初心者, 1-2=初級, 3-4=中級初め, 5=中級（上限）
// ===============================================

/**
 * サークルAIの成長イベント（毎月1日に実行）
 */
export const evolveCircleAIs = functionsV1.region("asia-northeast1").runWith({
  timeoutSeconds: 300,
  memory: "256MB",
}).pubsub.schedule("0 10 1 * *").timeZone("Asia/Tokyo").onRun(async () => {
  console.log("=== evolveCircleAIs START (Monthly Growth Event) ===");

  try {
    // growthLevel < 5 のサークルAIを取得
    const aiUsersSnapshot = await db.collection("users")
      .where("isAI", "==", true)
      .where("circleId", "!=", null)
      .get();

    let evolvedCount = 0;
    const batch = db.batch();
    const now = new Date();

    for (const userDoc of aiUsersSnapshot.docs) {
      const userData = userDoc.data();
      const currentLevel = userData.growthLevel || 0;
      const lastGrowthAt = userData.lastGrowthAt?.toDate() || new Date(0);

      // 30日以上経過していない場合はスキップ
      const daysSinceLastGrowth = Math.floor((now.getTime() - lastGrowthAt.getTime()) / (1000 * 60 * 60 * 24));
      if (daysSinceLastGrowth < 30) {
        console.log(`${userData.displayName}: Only ${daysSinceLastGrowth} days since last growth, skipping`);
        continue;
      }

      // 上限チェック（中級者=5で成長停止）
      if (currentLevel >= 5) {
        console.log(`${userData.displayName}: Already at max level (${currentLevel}), skipping`);
        continue;
      }

      // 成長ロジック：80%の確率で成長（運も演出）
      if (Math.random() > 0.8) {
        console.log(`${userData.displayName}: Unlucky this month, no growth`);
        continue;
      }

      // レベルアップ
      const newLevel = currentLevel + 1;
      batch.update(userDoc.ref, {
        growthLevel: newLevel,
        lastGrowthAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`${userData.displayName}: Level up! ${currentLevel} -> ${newLevel}`);
      evolvedCount++;
    }

    if (evolvedCount > 0) {
      await batch.commit();
    }

    console.log(`=== evolveCircleAIs COMPLETE: ${evolvedCount} AIs evolved ===`);

  } catch (error) {
    console.error("=== evolveCircleAIs ERROR:", error);
  }
});

/**
 * サークルAI成長を手動トリガー（テスト用）
 */
export const triggerEvolveCircleAIs = onCall(
  { region: "asia-northeast1", timeoutSeconds: 120 },
  async () => {
    console.log("=== triggerEvolveCircleAIs (manual) START ===");

    try {
      const aiUsersSnapshot = await db.collection("users")
        .where("isAI", "==", true)
        .where("circleId", "!=", null)
        .get();

      let evolvedCount = 0;
      const batch = db.batch();

      for (const userDoc of aiUsersSnapshot.docs) {
        const userData = userDoc.data();
        const currentLevel = userData.growthLevel || 0;

        if (currentLevel >= 5) continue;

        // テスト用：100%成長
        const newLevel = currentLevel + 1;
        batch.update(userDoc.ref, {
          growthLevel: newLevel,
          lastGrowthAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        evolvedCount++;
      }

      if (evolvedCount > 0) {
        await batch.commit();
      }

      return {
        success: true,
        message: `${evolvedCount}体のサークルAIが成長しました`,
        evolvedCount,
      };

    } catch (error) {
      console.error("triggerEvolveCircleAIs ERROR:", error);
      return { success: false, message: `エラー: ${error}` };
    }
  }
);

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
    const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;

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
    const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;

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
// 問い合わせ・要望機能
// ===============================================

/**
 * 新規問い合わせを作成
 */
export const createInquiry = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const { category, subject, content, imageUrl } = request.data;

    if (!category || !subject || !content) {
      throw new HttpsError("invalid-argument", "カテゴリ、件名、内容は必須です");
    }

    console.log(`=== createInquiry: userId=${userId}, category=${category} ===`);

    // 管理者UID（通知送信先）
    const ADMIN_UIDS = ["hYr5LUH4mhR60oQfVOggrjGYJjG2"];

    try {
      // ユーザー情報を取得
      const userDoc = await db.collection("users").doc(userId).get();
      const userData = userDoc.data();
      const userDisplayName = userData?.displayName || "匿名ユーザー";
      const userAvatarIndex = userData?.avatarIndex || 0;

      // 問い合わせを作成
      const inquiryRef = db.collection("inquiries").doc();
      const now = admin.firestore.FieldValue.serverTimestamp();

      await inquiryRef.set({
        userId,
        userDisplayName,
        userAvatarIndex,
        category,
        subject,
        status: "open",
        hasUnreadReply: false,
        hasUnreadMessage: true, // 管理者向け未読
        createdAt: now,
        updatedAt: now,
      });

      // 最初のメッセージを追加
      await inquiryRef.collection("messages").add({
        senderId: userId,
        senderName: userDisplayName,
        senderType: "user",
        content,
        imageUrl: imageUrl || null,
        createdAt: now,
      });

      // 管理者に通知を送信
      for (const adminUid of ADMIN_UIDS) {
        await db.collection("users").doc(adminUid).collection("notifications").add({
          type: "inquiry_received",
          title: "新規問い合わせ",
          body: `${userDisplayName}さんから問い合わせ「${subject}」が届きました`,
          senderId: userId,
          senderName: userDisplayName,
          senderAvatarUrl: String(userAvatarIndex),
          inquiryId: inquiryRef.id,
          isRead: false,
          createdAt: now,
        });
      }

      console.log(`Created inquiry: ${inquiryRef.id}`);

      return { success: true, inquiryId: inquiryRef.id };
    } catch (error) {
      console.error("Error creating inquiry:", error);
      throw new HttpsError("internal", "問い合わせの作成に失敗しました");
    }
  }
);

/**
 * ユーザーがメッセージを送信
 */
export const sendInquiryMessage = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const { inquiryId, content, imageUrl } = request.data;

    if (!inquiryId || !content) {
      throw new HttpsError("invalid-argument", "問い合わせIDと内容は必須です");
    }

    console.log(`=== sendInquiryMessage: inquiryId=${inquiryId} ===`);

    // 管理者UID（通知送信先）
    const ADMIN_UIDS = ["hYr5LUH4mhR60oQfVOggrjGYJjG2"];

    try {
      // 問い合わせの存在と所有者確認
      const inquiryRef = db.collection("inquiries").doc(inquiryId);
      const inquiryDoc = await inquiryRef.get();

      if (!inquiryDoc.exists) {
        throw new HttpsError("not-found", "問い合わせが見つかりません");
      }

      const inquiryData = inquiryDoc.data()!;
      if (inquiryData.userId !== userId) {
        throw new HttpsError("permission-denied", "この問い合わせにはアクセスできません");
      }

      // ユーザー情報を取得
      const userDoc = await db.collection("users").doc(userId).get();
      const userData = userDoc.data();
      const userDisplayName = userData?.displayName || "匿名ユーザー";
      const userAvatarIndex = userData?.avatarIndex || 0;

      const now = admin.firestore.FieldValue.serverTimestamp();

      // メッセージを追加
      await inquiryRef.collection("messages").add({
        senderId: userId,
        senderName: userDisplayName,
        senderType: "user",
        content,
        imageUrl: imageUrl || null,
        createdAt: now,
      });

      // 問い合わせを更新
      await inquiryRef.update({
        hasUnreadMessage: true, // 管理者向け未読
        updatedAt: now,
      });

      // 管理者に通知を送信
      for (const adminUid of ADMIN_UIDS) {
        await db.collection("users").doc(adminUid).collection("notifications").add({
          type: "inquiry_user_reply",
          title: "問い合わせに返信",
          body: `${userDisplayName}さんが「${inquiryData.subject}」に返信しました`,
          senderId: userId,
          senderName: userDisplayName,
          senderAvatarUrl: String(userAvatarIndex),
          inquiryId,
          isRead: false,
          createdAt: now,
        });
      }

      console.log(`Added message to inquiry: ${inquiryId}`);

      return { success: true };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("Error sending inquiry message:", error);
      throw new HttpsError("internal", "メッセージの送信に失敗しました");
    }
  }
);

/**
 * 管理者が返信を送信
 */
export const sendInquiryReply = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const adminId = request.auth.uid;
    const { inquiryId, content } = request.data;

    // 管理者チェック（ハードコード - 実際は設定から取得すべき）
    const ADMIN_UIDS = ["hYr5LUH4mhR60oQfVOggrjGYJjG2"];
    if (!ADMIN_UIDS.includes(adminId)) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    if (!inquiryId || !content) {
      throw new HttpsError("invalid-argument", "問い合わせIDと内容は必須です");
    }

    console.log(`=== sendInquiryReply: inquiryId=${inquiryId} ===`);

    try {
      const inquiryRef = db.collection("inquiries").doc(inquiryId);
      const inquiryDoc = await inquiryRef.get();

      if (!inquiryDoc.exists) {
        throw new HttpsError("not-found", "問い合わせが見つかりません");
      }

      const inquiryData = inquiryDoc.data()!;
      const now = admin.firestore.FieldValue.serverTimestamp();

      // 返信メッセージを追加
      await inquiryRef.collection("messages").add({
        senderId: adminId,
        senderName: "運営チーム",
        senderType: "admin",
        content,
        imageUrl: null,
        createdAt: now,
      });

      // 問い合わせを更新
      await inquiryRef.update({
        hasUnreadReply: true, // ユーザー向け未読
        hasUnreadMessage: false, // 管理者は既読
        status: "in_progress", // 対応中に変更
        updatedAt: now,
      });

      // ユーザーに通知を送信
      const targetUserId = inquiryData.userId;
      await db.collection("users").doc(targetUserId).collection("notifications").add({
        type: "inquiry_reply",
        title: "問い合わせに返信がありました",
        body: `「${inquiryData.subject}」に運営チームから返信があります`,
        inquiryId,
        isRead: false,
        createdAt: now,
      });

      console.log(`Sent reply to inquiry: ${inquiryId}`);

      return { success: true };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("Error sending inquiry reply:", error);
      throw new HttpsError("internal", "返信の送信に失敗しました");
    }
  }
);

/**
 * 問い合わせステータスを変更
 */
export const updateInquiryStatus = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const adminId = request.auth.uid;
    const { inquiryId, status } = request.data;

    // 管理者チェック
    const ADMIN_UIDS = ["hYr5LUH4mhR60oQfVOggrjGYJjG2"];
    if (!ADMIN_UIDS.includes(adminId)) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    if (!inquiryId || !status) {
      throw new HttpsError("invalid-argument", "問い合わせIDとステータスは必須です");
    }

    // 有効なステータスかチェック
    const VALID_STATUSES = ["open", "in_progress", "resolved"];
    if (!VALID_STATUSES.includes(status)) {
      throw new HttpsError("invalid-argument", "無効なステータスです");
    }

    console.log(`=== updateInquiryStatus: inquiryId=${inquiryId}, status=${status} ===`);

    try {
      const inquiryRef = db.collection("inquiries").doc(inquiryId);
      const inquiryDoc = await inquiryRef.get();

      if (!inquiryDoc.exists) {
        throw new HttpsError("not-found", "問い合わせが見つかりません");
      }

      const inquiryData = inquiryDoc.data()!;
      const now = admin.firestore.FieldValue.serverTimestamp();

      // ステータスを更新
      await inquiryRef.update({
        status,
        updatedAt: now,
      });

      // ステータスのラベルを取得
      const statusLabels: { [key: string]: string } = {
        open: "未対応",
        in_progress: "対応中",
        resolved: "解決済み",
      };
      const statusLabel = statusLabels[status] || status;

      // ユーザーに通知を送信
      const targetUserId = inquiryData.userId;
      await db.collection("users").doc(targetUserId).collection("notifications").add({
        type: "inquiry_status_changed",
        title: "問い合わせステータス変更",
        body: `「${inquiryData.subject}」のステータスが「${statusLabel}」に変更されました`,
        inquiryId,
        isRead: false,
        createdAt: now,
      });

      console.log(`Updated inquiry status: ${inquiryId} -> ${status}`);

      return { success: true };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("Error updating inquiry status:", error);
      throw new HttpsError("internal", "ステータスの変更に失敗しました");
    }
  }
);
