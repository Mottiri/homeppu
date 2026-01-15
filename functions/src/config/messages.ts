/**
 * メッセージ定数
 * 一貫性のあるメッセージを提供
 * 将来の多言語対応の基盤
 */

// ===============================================
// 認証エラー (AUTH_ERRORS)
// ===============================================
export const AUTH_ERRORS = {
    UNAUTHENTICATED: "ログインが必要です",
    UNAUTHENTICATED_ALT: "認証が必要です",
    UNAUTHENTICATED_EN: "Authentication required",
    USER_MUST_BE_LOGGED_IN: "User must be logged in",
    ADMIN_REQUIRED: "管理者権限が必要です",
    BANNED: "アカウントが制限されているため、現在この機能は使用できません。マイページ画面から運営へお問い合わせください。",
} as const;

// ===============================================
// 権限エラー (PERMISSION_ERRORS)
// ===============================================
export const PERMISSION_ERRORS = {
    CIRCLE_DELETE_OWNER_ONLY: "サークル削除はオーナーまたは管理者のみ可能です",
    CIRCLE_APPROVE_OWNER_ONLY: "オーナー、副オーナー、または管理者のみ承認できます",
    CIRCLE_REJECT_OWNER_ONLY: "オーナー、副オーナー、または管理者のみ拒否できます",
    INQUIRY_ACCESS_DENIED: "この問い合わせにはアクセスできません",
    PARTS_NOT_UNLOCKED: "アンロックしていないパーツは使用できません",
} as const;

// ===============================================
// リソースエラー (RESOURCE_ERRORS)
// ===============================================
export const RESOURCE_ERRORS = {
    USER_NOT_FOUND: "ユーザーが見つかりません",
    POST_NOT_FOUND: "投稿が見つかりません",
    CIRCLE_NOT_FOUND: "サークルが見つかりません",
    TASK_NOT_FOUND: "タスクが見つかりません",
    INQUIRY_NOT_FOUND: "問い合わせが見つかりません",
    APPLICATION_NOT_FOUND: "申請が見つかりません",
    PARTS_NOT_FOUND: "パーツが見つかりません",
} as const;

// ===============================================
// 入力検証エラー (VALIDATION_ERRORS)
// ===============================================
export const VALIDATION_ERRORS = {
    // 汎用
    INVALID_ARGUMENT: "入力が不正です",
    MISSING_REQUIRED: "必要な情報が不足しています",
    MISSING_PARAMS: "必要なパラメータがありません",
    INVALID_STATUS: "無効なステータスです",

    // 自己操作禁止
    SELF_FOLLOW_NOT_ALLOWED: "自分自身をフォローすることはできません",
    SELF_REPORT_NOT_ALLOWED: "自分自身を通報することはできません",
    SELF_ADMIN_REMOVE_NOT_ALLOWED: "自分自身の管理者権限は削除できません",
    SELF_BAN_NOT_ALLOWED: "自分自身をBANすることはできません",

    // 重複
    ALREADY_REPORTED: "既にこの内容を通報しています",
    ALREADY_APPLIED: "既に申請中です",

    // 個別
    FOLLOW_TARGET_REQUIRED: "フォロー対象のユーザーIDが必要です",
    UNFOLLOW_TARGET_REQUIRED: "フォロー解除対象のユーザーIDが必要です",
    USER_ID_REQUIRED: "ユーザーIDが必要です",
    TARGET_USER_ID_REQUIRED: "対象ユーザーIDが必要です",
    USER_ID_AND_REASON_REQUIRED: "userIdとreasonは必須です",
    USER_ID_ONLY_REQUIRED: "userIdは必須です",
    TASK_CONTENT_TYPE_REQUIRED: "タスク内容とタイプは必須です",
    INQUIRY_FIELDS_REQUIRED: "カテゴリ、件名、内容は必須です",
    INQUIRY_ID_CONTENT_REQUIRED: "問い合わせIDと内容は必須です",
    INQUIRY_ID_STATUS_REQUIRED: "問い合わせIDとステータスは必須です",
    CIRCLE_ID_REQUIRED: "circleIdが必要です",
    CIRCLE_ID_REQUIRED_ALT: "サークルIDが必要です",
    PARTS_ID_REQUIRED: "パーツIDが必要です",
    POST_ID_REACTION_REQUIRED: "postIdとreactionTypeが必要です",
    IMAGE_BASE64_REQUIRED: "imageBase64 is required",
    MISSING_POST_ID_CONTENT: "Missing postId or content",

    // レート制限
    RATE_LIMITED: "投稿が多すぎるよ！少し待ってからまた投稿してね",
} as const;

// ===============================================
// システムエラー (SYSTEM_ERRORS)
// ===============================================
export const SYSTEM_ERRORS = {
    INTERNAL: "システムエラーが発生しました。しばらくしてから再度お試しください。",
    PROCESSING_ERROR: "処理中にエラーが発生しました",
    DELETE_ERROR: "削除処理中にエラーが発生しました",
    MEDIA_ERROR: "メディアの確認中にエラーが発生しました。",
    INQUIRY_CREATE_FAILED: "問い合わせの作成に失敗しました",
    MESSAGE_SEND_FAILED: "メッセージの送信に失敗しました",
    REPLY_SEND_FAILED: "返信の送信に失敗しました",
    STATUS_CHANGE_FAILED: "ステータスの変更に失敗しました",
    ADMIN_SET_FAILED: "管理者権限の設定に失敗しました",
    ADMIN_REMOVE_FAILED: "管理者権限の削除に失敗しました",
    API_KEY_MISSING: "GEMINI_API_KEY is not set",
} as const;

// ===============================================
// 通知タイトル (NOTIFICATION_TITLES)
// ===============================================
export const NOTIFICATION_TITLES = {
    // アカウント関連
    ACCOUNT_SUSPENDED: "アカウントが一時停止されました",
    ACCOUNT_PERMANENTLY_BANNED: "アカウントが永久停止されました",
    ACCOUNT_RESTRICTION_LIFTED: "アカウント制限が解除されました",

    // サークル関連
    CIRCLE_DELETED: "サークルを削除しました",
    CIRCLE_UPDATED: "サークルが更新されました",
    CIRCLE_DELETE_WARNING: "⚠️ サークル削除予定のお知らせ",
    CIRCLE_AUTO_DELETED: "🗑️ サークルが削除されました",
    JOIN_APPROVED: "参加を承認しました",
    JOIN_REJECTED: "参加申請が拒否されました",
    JOIN_REQUEST_RECEIVED: "参加申請が届きました",

    // 問い合わせ関連
    NEW_INQUIRY: "新規問い合わせ",
    INQUIRY_REPLY: "問い合わせに返信",
    INQUIRY_REPLY_RECEIVED: "問い合わせに返信がありました",
    INQUIRY_STATUS_CHANGED: "問い合わせステータス変更",
    INQUIRY_DELETE_WARNING: "問い合わせ削除予告",

    // 投稿関連
    POST_HIDDEN: "投稿が非表示になりました",
    NEW_REPORT: "新規通報を受信",
    REVIEW_NEEDED: "要審査投稿",

    // 通知タイプ
    COMMENT: "コメント",
    REACTION: "リアクション",
} as const;

// ===============================================
// 通知本文 (NOTIFICATION_BODIES)
// ===============================================
export const NOTIFICATION_BODIES = {
    POST_HIDDEN_BY_REPORTS: "複数の通報があったため、投稿が一時的に非表示になりました。運営が確認します。",
    REPORT_SUBMITTED: "通報内容を運営チームで審査します。ご協力ありがとうございました！",
} as const;

// ===============================================
// ラベル・表示文字列 (LABELS)
// ===============================================
export const LABELS = {
    // デフォルト名
    OWNER: "オーナー",
    USER: "ユーザー",
    ANONYMOUS_USER: "匿名ユーザー",
    POSTER: "投稿者",
    SOMEONE: "誰か",
    CIRCLE: "サークル",
    ADMIN_TEAM: "運営チーム",
    NO_TEXT: "(テキストなし)",

    // ステータス
    STATUS_OPEN: "未対応",
    STATUS_IN_PROGRESS: "対応中",
    STATUS_RESOLVED: "解決済み",

    // カテゴリ（問い合わせ）
    CATEGORY_BUG: "バグ報告",
    CATEGORY_FEATURE: "機能要望",
    CATEGORY_ACCOUNT: "アカウント関連",
    CATEGORY_OTHER: "その他",

    // カテゴリ（モデレーション）
    CONTENT_ADULT: "成人向けコンテンツ",
    CONTENT_VIOLENCE: "暴力的なコンテンツ",
    CONTENT_HATE: "差別的なコンテンツ",
    CONTENT_DANGEROUS: "危険なコンテンツ",
    CONTENT_INAPPROPRIATE: "不適切なコンテンツ",

    // モード
    MODE_AI: "AIモード",
    MODE_MIX: "MIXモード",
    MODE_HUMAN: "人間モード",

    // 削除理由
    HIDDEN_BY_REPORTS: "通報多数のため自動非表示",
    DELETE_REASON_GHOST: "1年以上人間の投稿がないため自動削除",
    DELETE_REASON_ABANDONED: "投稿がなく放置されていたため自動削除",

    // サークル警告理由
    WARNING_GHOST: "1年以上人間の投稿がない",
    WARNING_ABANDONED: "作成から1ヶ月以上経過しても投稿がない",

    // 警告タイプ
    WARNING_TYPE_GHOST: "ゴースト",
    WARNING_TYPE_ABANDONED: "放置",

    // 変更通知
    CHANGE_DESCRIPTION: "説明が変更されました",
    CHANGE_GOAL: "目標が変更されました",
    CHANGE_RULES: "ルールが変更されました",
    CHANGE_PUBLIC: "公開に変更",
    CHANGE_PRIVATE: "非公開に変更",
    CHANGE_INVITE_ONLY: "招待制に変更",
    CHANGE_INVITE_DISABLED: "招待制を解除",
} as const;

// ===============================================
// 成功メッセージ (テンプレート関数)
// ===============================================
export const SUCCESS_MESSAGES = {
    // 静的メッセージ
    NAME_PARTS_INITIALIZED: "名前パーツを初期化しました",
    NO_AI_USERS: "AIユーザーはいませんでした",

    // 動的メッセージ（関数）
    nameChanged: (name: string) => `名前を「${name}」に変更しました！`,
    itemDeleted: (name: string) => `${name}を削除しました`,
    adminSet: (uid: string) => `ユーザー ${uid} を管理者に設定しました`,
    adminRemoved: (uid: string) => `ユーザー ${uid} の管理者権限を削除しました`,
    usersUpdated: (count: number) => `${count}件のユーザーを更新しました`,
    aiUsersDeleted: (count: number) => `AIユーザー${count}人とそのデータを削除しました`,
    orphanAIsDeleted: (deleted: number, notifications: number) =>
        `孤児サークルAIを${deleted}件削除しました（通知${notifications}件）`,
    aiAccountsCreated: (count: number) =>
        `AIアカウントを作成 / 更新しました（Gemini APIでbio生成: ${count} 体）`,
    aiPostsScheduled: (count: number) =>
        `AI投稿タスクを${count}件スケジュールしました。\nすべて完了するまでに1分〜10分ほどかかります。`,
    circleAIPostsCreated: (count: number, max: number) =>
        `サークルAI投稿を${count}件作成しました（最大${max}件処理）`,
    circleAIsEvolved: (count: number) => `${count}体のサークルAIが成長しました`,
    joinApproved: (circleName: string) => `${circleName || "サークル"}への参加が承認されました！`,
    joinRejected: (circleName: string) => `${circleName || "サークル"}への参加申請は承認されませんでした`,
} as const;

// ===============================================
// モデレーション関連
// ===============================================
export const MODERATION_MESSAGES = {
    NG_WORD_USED: "NGワード使用",
    INAPPROPRIATE_CONTENT_DETECTED: "不適切な内容が含まれています",
    TEST_ADMIN_MEDIA: "【テスト】管理者の添付付き投稿",

    // 動的メッセージ
    mediaBlocked: (type: "video" | "image", category: string, virtue: number) =>
        `添付された${type === "video" ? "動画" : "画像"}に${category} が含まれている可能性があります。\n\n別のメディアを選択してください。\n\n(徳ポイント: ${virtue})`,
} as const;

// ===============================================
// 全エラーをまとめてエクスポート
// ===============================================
export const ERROR_MESSAGES = {
    ...AUTH_ERRORS,
    ...PERMISSION_ERRORS,
    ...RESOURCE_ERRORS,
    ...VALIDATION_ERRORS,
    ...SYSTEM_ERRORS,
} as const;
