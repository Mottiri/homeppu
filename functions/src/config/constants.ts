// プロジェクト設定
export const PROJECT_ID = "positive-sns";
export const LOCATION = "asia-northeast1";
export const QUEUE_NAME = "generateAIComment";

// Google Sheets 設定
export const SPREADSHEET_ID = "1XsgrEmsdIkc5Cd_y8sIkBXFImshHPbqqxwJu9wWv4BY";

// Cloud Tasks で使用する関数名定数
export const CLOUD_TASK_FUNCTIONS = {
  generateAICommentV1: "generateAICommentV1",
  generateAIReactionV1: "generateAIReactionV1",
  executeAIPostGeneration: "executeAIPostGeneration",
  executeTaskReminder: "executeTaskReminder",
  cleanupDeletedCircle: "cleanupDeletedCircle",
  executeCircleAIPost: "executeCircleAIPost",
} as const;
