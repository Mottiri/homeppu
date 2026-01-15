/**
 * エラーメッセージ定数
 * 一貫性のあるエラーメッセージを提供
 * 将来の多言語対応の基盤
 */

// 認証・認可エラー
export const AUTH_ERRORS = {
    UNAUTHENTICATED: "ログインが必要です",
    ADMIN_REQUIRED: "管理者権限が必要です",
    BANNED: "アカウントが制限されているため、現在この機能は使用できません。マイページ画面から運営へお問い合わせください。",
} as const;

// リソース関連エラー
export const RESOURCE_ERRORS = {
    USER_NOT_FOUND: "ユーザーが見つかりません",
    POST_NOT_FOUND: "投稿が見つかりません",
    CIRCLE_NOT_FOUND: "サークルが見つかりません",
    TASK_NOT_FOUND: "タスクが見つかりません",
} as const;

// 入力検証エラー
export const VALIDATION_ERRORS = {
    INVALID_ARGUMENT: "入力が不正です",
    CONTENT_REQUIRED: "内容を入力してください",
    RATE_LIMITED: "投稿が多すぎるよ！少し待ってからまた投稿してね",
} as const;

// システムエラー
export const SYSTEM_ERRORS = {
    INTERNAL: "システムエラーが発生しました。しばらくしてから再度お試しください。",
    MEDIA_ERROR: "メディアの確認中にエラーが発生しました。",
} as const;

// 全エラーをまとめてエクスポート
export const ERROR_MESSAGES = {
    ...AUTH_ERRORS,
    ...RESOURCE_ERRORS,
    ...VALIDATION_ERRORS,
    ...SYSTEM_ERRORS,
} as const;
