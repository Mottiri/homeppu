import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import {GoogleGenerativeAI, Part} from "@google/generative-ai";
import {GoogleAIFileManager} from "@google/generative-ai/server";
import * as https from "https";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

admin.initializeApp();
const db = admin.firestore();

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

// APIキーをSecretsから取得
const geminiApiKey = defineSecret("GEMINI_API_KEY");

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
        reject(new Error(`Failed to download: ${response.statusCode}`));
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
    const imageBuffer = await downloadFile(imageUrl);
    const base64Image = imageBuffer.toString("base64");

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
        data: base64Image,
      },
    };

    const result = await model.generateContent([prompt, imagePart]);
    const responseText = result.response.text().trim();

    let jsonText = responseText;
    const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
    if (jsonMatch) {
      jsonText = jsonMatch[1];
    }

    return JSON.parse(jsonText) as MediaModerationResult;
  } catch (error) {
    console.error("Image moderation error:", error);
    // エラー時は許可
    return {
      isInappropriate: false,
      category: "none",
      confidence: 0,
      reason: "モデレーションエラー",
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
      displayName: `moderation_video_${Date.now()}`,
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

【許可する内容（isInappropriate: false）】
- 通常の人物動画
- 日常の風景、食事、ペット
- 趣味の動画
- ダンス、運動（健全なもの）

【回答形式】
必ず以下のJSON形式のみで回答してください：
{
  "isInappropriate": true または false,
  "category": "adult" | "violence" | "hate" | "dangerous" | "none",
  "confidence": 0から1の数値,
  "reason": "判定理由"
}
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
    const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
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
): Promise<{passed: boolean; failedItem?: MediaItem; result?: MediaModerationResult}> {
  for (const item of mediaItems) {
    if (item.type === "image") {
      const result = await moderateImage(model, item.url, item.mimeType || "image/jpeg");
      if (result.isInappropriate && result.confidence >= 0.7) {
        return {passed: false, failedItem: item, result};
      }
    } else if (item.type === "video") {
      const result = await moderateVideo(apiKey, model, item.url, item.mimeType || "video/mp4");
      if (result.isInappropriate && result.confidence >= 0.7) {
        return {passed: false, failedItem: item, result};
      }
    }
    // fileタイプはスキップ（PDFなどのモデレーションは複雑なため）
  }

  return {passed: true};
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
      displayName: `analysis_video_${Date.now()}`,
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
          descriptions.push(`【画像】${desc}`);
        }
      } else if (item.type === "video") {
        const desc = await analyzeVideoForComment(apiKey, model, item.url, item.mimeType || "video/mp4");
        if (desc) {
          descriptions.push(`【動画】${desc}`);
        }
      }
    } catch (error) {
      console.error(`Failed to analyze media item:`, error);
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
    {id: "college_student", name: "大学生", bio: "学業やサークル活動に励む"},
    {id: "sales", name: "営業マン", bio: "会社で営業職として働く"},
    {id: "engineer", name: "エンジニア", bio: "IT系の仕事をしている"},
    {id: "streamer", name: "配信者", bio: "ゲーム配信やYouTubeをやっている"},
    {id: "freeter", name: "フリーター", bio: "バイトしながら夢を追いかけている"},
  ],
  female: [
    {id: "ol", name: "OL", bio: "会社で事務や営業として働く"},
    {id: "college_student", name: "大学生", bio: "学業やサークル活動に励む"},
    {id: "nursery_teacher", name: "保育士", bio: "保育園で働いている"},
    {id: "designer", name: "デザイナー", bio: "Webや広告のデザインをしている"},
    {id: "nurse", name: "看護師", bio: "病院で働いている"},
  ],
};

// 性格（性別別）
const PERSONALITIES = {
  male: [
    {
      id: "bright",
      name: "明るい",
      trait: "ポジティブで元気",
      style: "「！」多め、絵文字使う",
      examples: ["すごい！", "いいね！", "最高！"],
    },
    {
      id: "passionate",
      name: "熱血",
      trait: "応援が熱い",
      style: "「頑張れ！」「最高！」連発",
      examples: ["頑張れ！！", "最高だ！", "応援してる！！"],
    },
    {
      id: "gentle",
      name: "穏やか",
      trait: "落ち着いている",
      style: "優しいトーン",
      examples: ["いいね", "すごいね", "頑張ってるね"],
    },
    {
      id: "cheerful",
      name: "ノリ良い",
      trait: "テンション高め",
      style: "「ww」「草」使う、タメ口",
      examples: ["まじすごいw", "やばいww", "神かよ"],
    },
    {
      id: "easygoing",
      name: "マイペース",
      trait: "ゆるい感じ",
      style: "「〜だね」「いいんじゃない？」",
      examples: ["いいんじゃない？", "すごいね〜", "いい感じだね"],
    },
  ],
  female: [
    {
      id: "kind",
      name: "優しい",
      trait: "包容力がある",
      style: "「わかるよ〜」共感系",
      examples: ["わかる〜！", "うんうん、すごいね", "頑張ってるね〜"],
    },
    {
      id: "energetic",
      name: "元気",
      trait: "明るくハキハキ",
      style: "「すごーい！」絵文字多め",
      examples: ["すごーい！✨", "えらい！！", "頑張ってる！！"],
    },
    {
      id: "healing",
      name: "癒し系",
      trait: "ほんわかしている",
      style: "ひらがな多め「えらいね〜」",
      examples: ["えらいね〜", "すごいなぁ", "がんばってるね"],
    },
    {
      id: "stylish",
      name: "おしゃれ",
      trait: "トレンドに敏感",
      style: "「素敵✨」「かわいい」",
      examples: ["素敵✨", "いいじゃん！", "センスいい！"],
    },
    {
      id: "reliable",
      name: "しっかり者",
      trait: "頼りになる",
      style: "丁寧だけど堅くない",
      examples: ["すごいですね", "頑張ってますね", "えらいです"],
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
  late_teens: {name: "10代後半", examples: ["大学1年", "19歳"]},
  twenties: {name: "20代", examples: ["25歳", "社会人3年目"]},
  thirties: {name: "30代", examples: ["32歳", "ベテラン"]},
};

// 男性の名前候補
const MALE_NAMES = [
  "ゆうき", "そうた", "けんた", "りく", "はると", "たくみ", "しょうた", "れん",
  "こうき", "だいき", "ゆうと", "かいと", "りょう", "しゅん", "けい",
  "なおき", "まさと", "ひろき", "こうへい", "たいが",
];

// 女性の名前候補
const FEMALE_NAMES = [
  "さくら", "みお", "はな", "ゆい", "あかり", "まな", "りこ", "ひなた",
  "あやか", "みさき", "かな", "ゆな", "ちひろ", "まい", "えみ",
  "なつみ", "あいり", "ももか", "ことね", "さき",
];

// AIペルソナの型定義
interface AIPersona {
  id: string;
  name: string;
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

// AIペルソナを生成する関数
function generateAIPersona(index: number): AIPersona {
  // 性別を決定（偶数=女性、奇数=男性で半々にする）
  const gender: Gender = index % 2 === 0 ? "female" : "male";

  // 各カテゴリをインデックスベースで分散
  const occupations = OCCUPATIONS[gender];
  const personalities = PERSONALITIES[gender];
  const names = gender === "male" ? MALE_NAMES : FEMALE_NAMES;

  const occupation = occupations[index % occupations.length];
  const personality = personalities[Math.floor(index / 2) % personalities.length];
  const praiseStyle = PRAISE_STYLES[Math.floor(index / 4) % PRAISE_STYLES.length];
  const ageGroup: AgeGroup = (["late_teens", "twenties", "thirties"] as const)[
    Math.floor(index / 6) % 3
  ];

  // 名前を決定（インデックスから選択）
  const name = names[index % names.length];

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
      `${occupation.name}してます！よろしくね✨`,
      `${occupation.name}やってます。毎日頑張ってる`,
      `${occupation.name}です。趣味は読書と散歩`,
    ];
    bio = defaultBios[index % defaultBios.length];
  }

  return {
    id: `ai_${index.toString().padStart(2, "0")}`,
    name,
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
const AI_PERSONAS: AIPersona[] = Array.from({length: 20}, (_, i) => generateAIPersona(i));

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
あなたは「ほめっぷ」というSNSのユーザー「${persona.name}」です。

【あなたのプロフィール】
- 名前: ${persona.name}
- 性別: ${genderStr}
- 年齢: ${ageStr}
- 職業: ${persona.occupation.name}（${persona.occupation.bio}）
- 性格: ${persona.personality.name}（${persona.personality.trait}）
- 話し方: ${persona.personality.style}
- よく使う言葉: ${persona.personality.examples.join("、")}

【投稿者の情報】
投稿者の名前: ${posterName}

【重要なルール】
1. 投稿者「${posterName}」さんを褒めてください
2. ネガティブなことは一切言わないでください
3. 自然な日本語で、人間らしく返信してください
4. 「AI」「ボット」という言葉は使わないでください
5. 投稿者の名前は基本呼ばないでください（呼ぶ場合は「${posterName}さん」）

【文字数と構造（最重要）】
- ${persona.praiseStyle.minLength}〜${persona.praiseStyle.maxLength}文字で返信してください
- あなたの褒め方スタイル: ${persona.praiseStyle.name}（${persona.praiseStyle.description}）
- 構造：「一言褒め」+「詳細な褒め」の2部構成
- まず短い褒め言葉で始めて、その後に具体的な内容を続ける
- 参考例: 「${persona.praiseStyle.example}」

- 悪い例：「すごい！」← 短すぎ
- 悪い例：「〇〇さんの頑張りが伝わってきます。とても素晴らしい取り組みですね。これからも応援しています！」← 長すぎ・くどい

【専門的な内容への対応】
- 勉強、資格試験、専門分野の場合、内容を詳しく知っているふりをしないでください
- 「難しそう！」「すごい！」くらいの短い反応でOK
- 画像内のテキストを断片的に引用しないでください
`;
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
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      console.log("No data associated with the event");
      return;
    }

    const postData = snap.data();
    const postId = event.params.postId;

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
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});

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

    // ランダムに1〜3人のAIを選択
    const commentCount = Math.floor(Math.random() * 3) + 1;
    const shuffledPersonas = [...AI_PERSONAS]
      .sort(() => Math.random() - 0.5)
      .slice(0, commentCount);

    const batch = db.batch();
    let totalComments = 0;

    // 投稿者の名前を取得
    const posterName = postData.userDisplayName || "投稿者";

    // メディア説明をプロンプトに追加
    const mediaContext = mediaDescriptions.length > 0
      ? `\n\n【添付メディアの内容】\n${mediaDescriptions.join("\n")}`
      : "";

    for (const persona of shuffledPersonas) {
      try {
        const prompt = `
${getSystemPrompt(persona, posterName)}

【${posterName}さんの投稿】
${postData.content || "(テキストなし)"}${mediaContext}

【重要】
${mediaDescriptions.length > 0 
  ? "添付されたメディア（画像・動画）の内容も考慮して、具体的に褒めてください。" 
  : ""}

【あなた（${persona.name}）の返信】
`;

        const result = await model.generateContent(prompt);
        const commentText = result.response.text()?.trim();

        if (!commentText) continue;

        // ランダムな遅延時間（1〜30分後）をシミュレート
        const delayMinutes = Math.floor(Math.random() * 29) + 1;
        const commentTime = new Date(Date.now() + delayMinutes * 60 * 1000);

        const commentRef = db.collection("comments").doc();
        batch.set(commentRef, {
          postId: postId,
          userId: persona.id,
          userDisplayName: persona.name,
          userAvatarIndex: persona.avatarIndex,
          isAI: true,
          content: commentText,
          createdAt: admin.firestore.Timestamp.fromDate(commentTime),
        });

        totalComments++;
        console.log(`AI comment created: ${persona.name} (delayed ${delayMinutes}m, media: ${mediaDescriptions.length > 0})`);
      } catch (error) {
        console.error(`Error generating comment for ${persona.name}:`, error);
      }
    }

    // コメント数を更新
    if (totalComments > 0) {
      batch.update(snap.ref, {
        commentCount: admin.firestore.FieldValue.increment(totalComments),
      });
      await batch.commit();
    }
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
- 「26歳/大学生🫐 学業やサークル活動に励む。トレンドに敏感な性格です。」← 説明的すぎる
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
    return `${persona.occupation.name}してます！よろしくね✨`;
  } catch (error) {
    console.error(`Bio generation error for ${persona.name}:`, error);
    return `${persona.occupation.name}してます！よろしくね✨`;
  }
}

/**
 * AIアカウントを初期化する関数（管理者用）
 * 既存のアカウントも更新します
 * ランダム組み合わせ方式で20体のAIアカウントを生成
 * Gemini APIでキャラクターに合ったbioを動的生成
 */
export const initializeAIAccounts = onCall(
  {region: "asia-northeast1", secrets: [geminiApiKey], timeoutSeconds: 300},
  async () => {
    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      return {success: false, message: "GEMINI_API_KEY is not set"};
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});

    let createdCount = 0;
    let updatedCount = 0;
    const generatedBios: {name: string; bio: string}[] = [];

    console.log(`Initializing ${AI_PERSONAS.length} AI accounts with Gemini-generated bios...`);

    for (const persona of AI_PERSONAS) {
      const docRef = db.collection("users").doc(persona.id);
      const doc = await docRef.get();

      // Gemini APIでbioを生成
      console.log(`Generating bio for ${persona.name}...`);
      const generatedBio = await generateBioWithGemini(model, persona);
      console.log(`  Generated: "${generatedBio}"`);
      generatedBios.push({name: persona.name, bio: generatedBio});

      // AIキャラ設定を保存（コメント生成時に使用）
      const aiCharacterSettings = {
        gender: persona.gender,
        ageGroup: persona.ageGroup,
        occupationId: persona.occupation.id,
        personalityId: persona.personality.id,
        praiseStyleId: persona.praiseStyle.id,
      };

      const userData = {
        email: `${persona.id}@ai.homeppu.local`,
        displayName: persona.name,
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
      console.log(`  ${i + 1}. ${p.name} - ${p.gender === "male" ? "男" : "女"}/${AGE_GROUPS[p.ageGroup].name}/${p.occupation.name}/${p.personality.name}/${p.praiseStyle.name}`);
    });

    return {
      success: true,
      message: `AIアカウントを作成/更新しました（Gemini APIでbio生成: ${AI_PERSONAS.length}体）`,
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
export const generateAIPosts = onCall(
  {region: "asia-northeast1", secrets: [geminiApiKey]},
  async () => {
    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      return {success: false, message: "GEMINI_API_KEY is not set"};
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});

    let totalPosts = 0;
    let totalComments = 0;
    let totalReactions = 0;

    for (const persona of AI_PERSONAS) {
      // 既存の投稿数をチェック
      const existingPosts = await db
        .collection("posts")
        .where("userId", "==", persona.id)
        .get();

      if (existingPosts.size >= 5) {
        console.log(`${persona.name} already has ${existingPosts.size} posts, skipping`);
        continue;
      }

      // 職業に応じた投稿テンプレートを取得
      const templates = POST_TEMPLATES_BY_OCCUPATION[persona.occupation.id] || [];
      if (templates.length === 0) {
        console.log(`No templates for occupation ${persona.occupation.id}, skipping ${persona.name}`);
        continue;
      }

      // ランダムに3〜5投稿を選択
      const shuffledTemplates = [...templates].sort(() => Math.random() - 0.5);
      const selectedTemplates = shuffledTemplates.slice(0, Math.floor(Math.random() * 3) + 3);

      // 過去1〜7日間にランダムな時間で投稿を作成
      for (let i = 0; i < selectedTemplates.length; i++) {
        const daysAgo = Math.floor(Math.random() * 7) + 1;
        const hoursAgo = Math.floor(Math.random() * 24);
        const postTime = new Date(
          Date.now() - daysAgo * 24 * 60 * 60 * 1000 - hoursAgo * 60 * 60 * 1000
        );

        // 投稿を作成
        const postRef = db.collection("posts").doc();
        const reactions = {
          love: Math.floor(Math.random() * 10),
          praise: Math.floor(Math.random() * 8),
          cheer: Math.floor(Math.random() * 6),
          empathy: Math.floor(Math.random() * 5),
        };

        await postRef.set({
          userId: persona.id,
          userDisplayName: persona.name,
          userAvatarIndex: persona.avatarIndex,
          content: selectedTemplates[i],
          postMode: "mix",
          createdAt: admin.firestore.Timestamp.fromDate(postTime),
          reactions: reactions,
          commentCount: 0,
          isVisible: true,
        });

        totalPosts++;
        totalReactions += Object.values(reactions).reduce((a, b) => a + b, 0);

        // 他のAIからコメントを生成（1〜2件）
        const commentCount = Math.floor(Math.random() * 2) + 1;
        const otherPersonas = AI_PERSONAS.filter((p) => p.id !== persona.id)
          .sort(() => Math.random() - 0.5)
          .slice(0, commentCount);

        for (const commenter of otherPersonas) {
          try {
            const prompt = getSystemPrompt(commenter, persona.name) + `

【${persona.name}さんの投稿】
${selectedTemplates[i]}

【あなた（${commenter.name}）の返信】
`;

            const result = await model.generateContent(prompt);
            const commentText = result.response.text()?.trim();

            if (commentText) {
              const commentTime = new Date(
                postTime.getTime() + Math.floor(Math.random() * 60) * 60 * 1000
              );

              await db.collection("comments").add({
                postId: postRef.id,
                userId: commenter.id,
                userDisplayName: commenter.name,
                userAvatarIndex: commenter.avatarIndex,
                isAI: true,
                content: commentText,
                createdAt: admin.firestore.Timestamp.fromDate(commentTime),
              });

              totalComments++;

              // 投稿のコメント数を更新
              await postRef.update({
                commentCount: admin.firestore.FieldValue.increment(1),
              });
            }
          } catch (error) {
            console.error(`Error generating comment:`, error);
          }
        }
      }

      // ユーザーの投稿数を更新
      await db.collection("users").doc(persona.id).update({
        totalPosts: admin.firestore.FieldValue.increment(selectedTemplates.length),
        totalPraises: admin.firestore.FieldValue.increment(
          Math.floor(Math.random() * 20)
        ),
      });
    }

    return {
      success: true,
      message: `AI投稿を生成しました（${AI_PERSONAS.length}体のAI）`,
      posts: totalPosts,
      comments: totalComments,
      reactions: totalReactions,
    };
  }
);

/**
 * レート制限付きの投稿作成（スパム対策）
 */
export const createPostWithRateLimit = onCall(
  {region: "asia-northeast1"},
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
      reactions: {love: 0, praise: 0, cheer: 0, empathy: 0},
      commentCount: 0,
      isVisible: true,
    });

    // ユーザーの投稿数を更新
    await db.collection("users").doc(userId).update({
      totalPosts: admin.firestore.FieldValue.increment(1),
    });

    return {success: true, postId: postRef.id};
  }
);

// ===============================================
// コンテンツモデレーション機能
// ===============================================

/**
 * コンテンツをモデレーションする関数
 * Gemini AIでネガティブ発言を検出
 */
export const moderateContent = onCall(
  {region: "asia-northeast1", secrets: [geminiApiKey]},
  async (request): Promise<ModerationResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {content} = request.data;
    if (!content || typeof content !== "string") {
      throw new HttpsError("invalid-argument", "コンテンツが必要です");
    }

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      console.error("GEMINI_API_KEY is not set");
      // APIキーがない場合はモデレーションをスキップ
      return {
        isNegative: false,
        category: "none",
        confidence: 0,
        reason: "",
        suggestion: "",
      };
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});

    const prompt = `
あなたはSNS「ほめっぷ」のコンテンツモデレーターです。
「ほめっぷ」は「世界一優しいSNS」を目指しており、ネガティブな発言を排除しています。

以下の投稿内容を分析して、ネガティブかどうか判定してください。

【判定基準】
- harassment: 誹謗中傷、人を傷つける発言
- hate_speech: 差別、ヘイトスピーチ
- profanity: 不適切な言葉、暴言、罵倒
- self_harm: 自傷行為の助長
- spam: スパム、宣伝
- none: 問題なし

【重要】
- 「ほめっぷ」はポジティブなSNSなので、軽い愚痴や不満も「ネガティブ」と判定します
- ただし、自分の頑張りや努力を共有する投稿は「none」です
- 他人を批判する内容は「harassment」です
- 判定は厳しめにお願いします

【投稿内容】
${content}

【回答形式】
必ず以下のJSON形式で回答してください。他の文字は含めないでください。
{
  "isNegative": true または false,
  "category": "harassment" | "hate_speech" | "profanity" | "self_harm" | "spam" | "none",
  "confidence": 0から1の数値,
  "reason": "判定理由（ユーザーに見せる優しい説明）",
  "suggestion": "より良い表現の提案"
}
`;

    try {
      const result = await model.generateContent(prompt);
      const responseText = result.response.text().trim();

      // JSONを抽出（マークダウンコードブロックを考慮）
      let jsonText = responseText;
      const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
      if (jsonMatch) {
        jsonText = jsonMatch[1];
      }

      const parsed = JSON.parse(jsonText) as ModerationResult;

      // 結果をログに記録
      console.log("Moderation result:", {
        content: content.substring(0, 50) + "...",
        result: parsed,
      });

      return parsed;
    } catch (error) {
      console.error("Moderation error:", error);
      // エラー時は安全側に倒す（投稿を許可）
      return {
        isNegative: false,
        category: "none",
        confidence: 0,
        reason: "",
        suggestion: "",
      };
    }
  }
);

/**
 * 徳ポイントを減少させる（ネガティブ発言検出時）
 */
async function decreaseVirtue(
  userId: string,
  reason: string,
  amount: number = VIRTUE_CONFIG.lossPerNegative
): Promise<{newVirtue: number; isBanned: boolean}> {
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

  console.log(`Virtue decreased for ${userId}: ${currentVirtue} -> ${newVirtue}, banned: ${isBanned}`);

  return {newVirtue, isBanned};
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
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const {content, userDisplayName, userAvatarIndex, postMode, circleId, mediaItems} = request.data;

    // ユーザーがBANされているかチェック
    const userDoc = await db.collection("users").doc(userId).get();
    if (userDoc.exists && userDoc.data()?.isBanned) {
      throw new HttpsError(
        "permission-denied",
        "申し訳ありませんが、現在投稿できません。運営にお問い合わせください。"
      );
    }

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      console.error("GEMINI_API_KEY is not set");
      // APIキーがない場合はモデレーションをスキップして投稿を許可
    }

    const genAI = apiKey ? new GoogleGenerativeAI(apiKey) : null;
    const model = genAI?.getGenerativeModel({model: "gemini-2.0-flash"});

    // ===============================================
    // 1. テキストモデレーション
    // ===============================================
    if (model && content) {
      const textPrompt = `
あなたはSNS「ほめっぷ」のコンテンツモデレーターです。
「ほめっぷ」は「世界一優しいSNS」を目指しています。

以下の投稿内容を分析して、「他者への攻撃」があるかどうか判定してください。

【ブロック対象（isNegative: true）】
- harassment: 他者への誹謗中傷、人格攻撃、悪口
- hate_speech: 差別、ヘイトスピーチ、特定の属性への攻撃
- profanity: 他者への暴言、罵倒
- self_harm: 自傷行為の助長（※これは安全上ブロック）
- spam: スパム、宣伝

【許可する内容（isNegative: false）】
- 個人の感情表現：「悲しい」「辛い」「落ち込んだ」「疲れた」「しんどい」
- 自分自身への愚痴：「自分ダメだな」「失敗した」「うまくいかない」
- 日常の不満：「雨だ〜」「電車遅れた」「眠い」
- 頑張りや努力の共有
- 共感を求める投稿

【重要な判定基準】
⚠️ 「他者を攻撃しているか」が最重要ポイントです
⚠️ 自分の気持ちを素直に表現することは許可します
⚠️ 誰かを傷つける意図がない限り「none」と判定してください

【投稿内容】
${content}

【回答形式】
必ず以下のJSON形式で回答してください。他の文字は含めないでください。
{
  "isNegative": true または false,
  "category": "harassment" | "hate_speech" | "profanity" | "self_harm" | "spam" | "none",
  "confidence": 0から1の数値,
  "reason": "判定理由（ユーザーに見せる優しい説明）",
  "suggestion": "より良い表現の提案"
}
`;

      try {
        const result = await model.generateContent(textPrompt);
        const responseText = result.response.text().trim();

        let jsonText = responseText;
        const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
        if (jsonMatch) {
          jsonText = jsonMatch[1];
        }

        const modResult = JSON.parse(jsonText) as ModerationResult;

        if (modResult.isNegative && modResult.confidence >= 0.7) {
          // 徳ポイントを減少
          const virtueResult = await decreaseVirtue(
            userId,
            `ネガティブ投稿検出: ${modResult.category}`,
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
            `${modResult.reason}\n\n💡 提案: ${modResult.suggestion}\n\n(徳ポイント: ${virtueResult.newVirtue})`
          );
        }
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }
        console.error("Text moderation error:", error);
        // エラー時は投稿を許可
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
          // 徳ポイントを減少
          const virtueResult = await decreaseVirtue(
            userId,
            `不適切なメディア検出: ${mediaResult.result.category}`,
            VIRTUE_CONFIG.lossPerNegative
          );

          // 記録
          await db.collection("moderatedContent").add({
            userId: userId,
            content: `[メディア] ${mediaResult.failedItem?.fileName || "media"}`,
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

          throw new HttpsError(
            "invalid-argument",
            `添付された${mediaResult.failedItem?.type === "video" ? "動画" : "画像"}に${categoryLabel}が含まれている可能性があります。\n\n別のメディアを選択してください。\n\n(徳ポイント: ${virtueResult.newVirtue})`
          );
        }

        console.log("Media moderation passed");
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }
        console.error("Media moderation error:", error);
        // エラー時は投稿を許可（厳しくしすぎない）
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
      reactions: {love: 0, praise: 0, cheer: 0, empathy: 0},
      commentCount: 0,
      isVisible: true,
    });

    // ユーザーの投稿数を更新
    await db.collection("users").doc(userId).update({
      totalPosts: admin.firestore.FieldValue.increment(1),
    });

    return {success: true, postId: postRef.id};
  }
);

/**
 * モデレーション付きコメント作成
 */
export const createCommentWithModeration = onCall(
  {region: "asia-northeast1", secrets: [geminiApiKey]},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const {postId, content, userDisplayName, userAvatarIndex} = request.data;

    // ユーザーがBANされているかチェック
    const userDoc = await db.collection("users").doc(userId).get();
    if (userDoc.exists && userDoc.data()?.isBanned) {
      throw new HttpsError(
        "permission-denied",
        "申し訳ありませんが、現在コメントできません。"
      );
    }

    // コンテンツモデレーション
    const apiKey = geminiApiKey.value();
    if (apiKey) {
      const genAI = new GoogleGenerativeAI(apiKey);
      const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});

      const prompt = `
あなたはSNS「ほめっぷ」のコンテンツモデレーターです。
以下のコメント内容を分析して、ネガティブかどうか判定してください。

【判定基準】
- harassment: 誹謗中傷
- hate_speech: 差別
- profanity: 暴言
- none: 問題なし

【コメント内容】
${content}

【回答形式】
{
  "isNegative": boolean,
  "category": string,
  "confidence": number,
  "reason": "理由",
  "suggestion": "提案"
}
`;

      try {
        const result = await model.generateContent(prompt);
        const responseText = result.response.text().trim();

        let jsonText = responseText;
        const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
        if (jsonMatch) {
          jsonText = jsonMatch[1];
        }

        const modResult = JSON.parse(jsonText) as ModerationResult;

        if (modResult.isNegative && modResult.confidence >= 0.7) {
          await decreaseVirtue(
            userId,
            `ネガティブコメント検出: ${modResult.category}`,
            VIRTUE_CONFIG.lossPerNegative
          );

          throw new HttpsError(
            "invalid-argument",
            `${modResult.reason}\n\n💡 ${modResult.suggestion}`
          );
        }
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }
        console.error("Moderation error:", error);
      }
    }

    // コメントを作成
    const commentRef = db.collection("comments").doc();
    await commentRef.set({
      postId: postId,
      userId: userId,
      userDisplayName: userDisplayName,
      userAvatarIndex: userAvatarIndex,
      isAI: false,
      content: content,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 投稿のコメント数を更新
    await db.collection("posts").doc(postId).update({
      commentCount: admin.firestore.FieldValue.increment(1),
    });

    return {success: true, commentId: commentRef.id};
  }
);

// ===============================================
// 通報機能
// ===============================================

/**
 * コンテンツを通報する
 */
export const reportContent = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const reporterId = request.auth.uid;
    const {contentId, contentType, reason, targetUserId} = request.data;

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
        batch.update(doc.ref, {status: "reviewed"});
      });
      await batch.commit();

      console.log(`Auto virtue decrease for ${targetUserId}: ${virtueResult.newVirtue}`);
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
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const currentUserId = request.auth.uid;
    const {targetUserId} = request.data;

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

    console.log(`User ${currentUserId} followed ${targetUserId}`);

    return {success: true};
  }
);

/**
 * フォローを解除する
 */
export const unfollowUser = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const currentUserId = request.auth.uid;
    const {targetUserId} = request.data;

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

    console.log(`User ${currentUserId} unfollowed ${targetUserId}`);

    return {success: true};
  }
);

/**
 * フォロー状態を取得する
 */
export const getFollowStatus = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const currentUserId = request.auth.uid;
    const {targetUserId} = request.data;

    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "ユーザーIDが必要です");
    }

    const currentUser = await db.collection("users").doc(currentUserId).get();
    
    if (!currentUser.exists) {
      return {isFollowing: false};
    }

    const following = currentUser.data()?.following || [];
    const isFollowing = following.includes(targetUserId);

    return {isFollowing};
  }
);

/**
 * 徳ポイント履歴を取得
 */
export const getVirtueHistory = onCall(
  {region: "asia-northeast1"},
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
  {region: "asia-northeast1"},
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
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const {content, emoji, type} = request.data;

    if (!content || !type) {
      throw new HttpsError("invalid-argument", "タスク内容とタイプは必須です");
    }

    const taskRef = db.collection("tasks").doc();
    await taskRef.set({
      userId: userId,
      content: content,
      emoji: emoji || "📝",
      type: type, // "daily" | "goal"
      isCompleted: false,
      streak: 0,
      lastCompletedAt: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {success: true, taskId: taskRef.id};
  }
);

/**
 * タスク一覧を取得
 */
export const getTasks = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const {type} = request.data;

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
      };
    });

    return {tasks};
  }
);

/**
 * タスクを完了
 */
export const completeTask = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const {taskId} = request.data;

    if (!taskId) {
      throw new HttpsError("invalid-argument", "タスクIDが必要です");
    }

    const taskRef = db.collection("tasks").doc(taskId);
    const taskDoc = await taskRef.get();

    if (!taskDoc.exists) {
      throw new HttpsError("not-found", "タスクが見つかりません");
    }

    const taskData = taskDoc.data()!;

    if (taskData.userId !== userId) {
      throw new HttpsError("permission-denied", "このタスクを完了する権限がありません");
    }

    // 連続達成の計算
    const now = new Date();
    const lastCompleted = taskData.lastCompletedAt?.toDate();
    let newStreak = 1;

    if (lastCompleted) {
      const diffDays = Math.floor((now.getTime() - lastCompleted.getTime()) / (1000 * 60 * 60 * 24));
      if (diffDays === 1) {
        // 昨日完了していたら連続達成
        newStreak = (taskData.streak || 0) + 1;
      } else if (diffDays === 0) {
        // 今日既に完了していた場合
        newStreak = taskData.streak || 1;
      }
    }

    // 徳ポイント計算（連続ボーナス付き）
    const baseVirtue = 2;
    const streakBonus = Math.min(newStreak - 1, 5); // 最大5ポイントのボーナス
    const virtueGain = baseVirtue + streakBonus;

    // タスクを更新
    await taskRef.update({
      isCompleted: true,
      streak: newStreak,
      lastCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 徳ポイントを増加
    const userRef = db.collection("users").doc(userId);
    await userRef.update({
      virtue: admin.firestore.FieldValue.increment(virtueGain),
    });

    // 徳ポイント履歴を記録
    await db.collection("virtueHistory").add({
      userId: userId,
      change: virtueGain,
      reason: `タスク完了: ${taskData.content}${streakBonus > 0 ? ` (${newStreak}日連続!)` : ""}`,
      newVirtue: 0, // 後で計算
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const userDoc = await userRef.get();
    const newVirtue = userDoc.data()?.virtue || 0;

    return {
      success: true,
      virtueGain,
      newVirtue,
      streak: newStreak,
      streakBonus,
    };
  }
);

/**
 * タスクの完了を取り消し
 */
export const uncompleteTask = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const {taskId} = request.data;

    if (!taskId) {
      throw new HttpsError("invalid-argument", "タスクIDが必要です");
    }

    const taskRef = db.collection("tasks").doc(taskId);
    const taskDoc = await taskRef.get();

    if (!taskDoc.exists) {
      throw new HttpsError("not-found", "タスクが見つかりません");
    }

    const taskData = taskDoc.data()!;

    if (taskData.userId !== userId) {
      throw new HttpsError("permission-denied", "このタスクを操作する権限がありません");
    }

    if (!taskData.isCompleted) {
      return {success: false, message: "このタスクは完了していません"};
    }

    // 徳ポイントを減少（基本2ポイント）
    const virtueLoss = 2;

    await taskRef.update({
      isCompleted: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const userRef = db.collection("users").doc(userId);
    await userRef.update({
      virtue: admin.firestore.FieldValue.increment(-virtueLoss),
    });

    const userDoc = await userRef.get();
    const newVirtue = userDoc.data()?.virtue || 0;

    return {
      success: true,
      virtueLoss,
      newVirtue,
      message: "タスクの完了を取り消しました",
    };
  }
);

/**
 * タスクを削除
 */
export const deleteTask = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const {taskId} = request.data;

    if (!taskId) {
      throw new HttpsError("invalid-argument", "タスクIDが必要です");
    }

    const taskRef = db.collection("tasks").doc(taskId);
    const taskDoc = await taskRef.get();

    if (!taskDoc.exists) {
      throw new HttpsError("not-found", "タスクが見つかりません");
    }

    const taskData = taskDoc.data()!;

    if (taskData.userId !== userId) {
      throw new HttpsError("permission-denied", "このタスクを削除する権限がありません");
    }

    await taskRef.delete();

    return {success: true};
  }
);