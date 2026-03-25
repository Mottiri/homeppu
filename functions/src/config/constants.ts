// プロジェクト設定
export const PROJECT_ID = "positive-sns";
export const LOCATION = "asia-northeast1";
export const QUEUE_NAME = "generateAIComment";

// Google Sheets 設定（フォールバック値。Firestore settings/spreadsheet が優先される）
export const SPREADSHEET_ID = "1XsgrEmsdIkc5Cd_y8sIkBXFImshHPbqqxwJu9wWv4BY";

// Cloud Tasks で使用する関数名定数
export const CLOUD_TASK_FUNCTIONS = {
  generateAICommentV1: "generateAICommentV1",
  generateAIReactionV1: "generateAIReactionV1",
  executeAIPostGeneration: "executeAIPostGeneration",
  cleanupDeletedCircle: "cleanupDeletedCircle",
  executeCircleAIPost: "executeCircleAIPost",
} as const;

// サークル参加上限
export const MAX_JOINED_CIRCLES = 100;

// AI モデル設定
export const AI_MODELS = {
  GEMINI_DEFAULT: "gemini-2.5-flash",
  OPENAI_DEFAULT: "gpt-5-mini",
} as const;
