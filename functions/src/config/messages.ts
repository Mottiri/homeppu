/**
 * メッセージ定義
 * Functions 内で利用する文言を集約
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
    BANNED: "アカウントが制限されているため、この機能は利用できません。異議申し立て画面から運営へお問い合わせください。",
} as const;

// ===============================================
// 権限エラー (PERMISSION_ERRORS)
// ===============================================
export const PERMISSION_ERRORS = {
    CIRCLE_DELETE_OWNER_ONLY: "サークル削除はオーナーまたは管理者のみ可能です",
    CIRCLE_APPROVE_OWNER_ONLY: "オーナー、サブオーナー、または管理者のみ承認できます",
    CIRCLE_REJECT_OWNER_ONLY: "オーナー、サブオーナー、または管理者のみ拒否できます",
    INQUIRY_ACCESS_DENIED: "この問い合わせにはアクセスできません",
    PARTS_NOT_UNLOCKED: "アンロックしていないパーツは使用できません",
    EPIC_REACTION_REQUIRES_SUBSCRIPTION: "サブスクまたは一時解除が必要です",
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
    INVALID_ARGUMENT: "入力が不正です",
    MISSING_REQUIRED: "必要な情報が不足しています",
    MISSING_PARAMS: "必要なパラメータがありません",
    INVALID_STATUS: "不正なステータスです",

    SELF_FOLLOW_NOT_ALLOWED: "自分自身をフォローすることはできません",
    SELF_REPORT_NOT_ALLOWED: "自分自身を通報することはできません",
    SELF_ADMIN_REMOVE_NOT_ALLOWED: "自分自身の管理者権限は削除できません",
    SELF_BAN_NOT_ALLOWED: "自分自身をBANすることはできません",

    ALREADY_REPORTED: "既にこの内容を通報しています",
    ALREADY_APPLIED: "既に申請済みです",

    FOLLOW_TARGET_REQUIRED: "フォロー対象のユーザーIDが必要です",
    UNFOLLOW_TARGET_REQUIRED: "フォロー解除対象のユーザーIDが必要です",
    USER_ID_REQUIRED: "ユーザーIDが必要です",
    TARGET_USER_ID_REQUIRED: "対象ユーザーIDが必要です",
    USER_ID_AND_REASON_REQUIRED: "userId と reason は必須です",
    USER_ID_ONLY_REQUIRED: "userId は必須です",
    TASK_CONTENT_TYPE_REQUIRED: "タスク内容とタイプは必須です",
    INQUIRY_FIELDS_REQUIRED: "カテゴリ、件名、本文は必須です",
    INQUIRY_ID_CONTENT_REQUIRED: "問い合わせIDと本文は必須です",
    INQUIRY_ID_STATUS_REQUIRED: "問い合わせIDとステータスは必須です",
    CIRCLE_ID_REQUIRED: "circleId が必要です",
    CIRCLE_ID_REQUIRED_ALT: "サークルIDが必要です",
    PARTS_ID_REQUIRED: "パーツIDが必要です",
    POST_ID_REACTION_REQUIRED: "postId と reactionType が必要です",
    IMAGE_BASE64_REQUIRED: "imageBase64 is required",
    MISSING_POST_ID_CONTENT: "Missing postId or content",

    RATE_LIMITED: "投稿が多すぎます。少し待ってから再度投稿してください",
    RATE_LIMITED_PER_MINUTE: "短時間での投稿が多すぎます。少し待ってから再度投稿してください",
    RATE_LIMITED_DAILY_15: "1日に投稿できる回数は15回までです。明日また投稿してください",
    COMMENT_RATE_LIMITED_PER_MINUTE: "コメントは60秒で2回までです。少し待ってから再度送信してください",

    reactionLimitExceeded: (max: number) => `1つの投稿に対するリアクションは${max}回までです`,
} as const;

// ===============================================
// システムエラー (SYSTEM_ERRORS)
// ===============================================
export const SYSTEM_ERRORS = {
    INTERNAL: "システムエラーが発生しました。しばらくしてから再度お試しください。",
    PROCESSING_ERROR: "処理中にエラーが発生しました",
    DELETE_ERROR: "削除処理中にエラーが発生しました",
    MEDIA_ERROR: "メディアの処理中にエラーが発生しました",
    INQUIRY_CREATE_FAILED: "問い合わせの作成に失敗しました",
    MESSAGE_SEND_FAILED: "メッセージの送信に失敗しました",
    REPLY_SEND_FAILED: "返信の送信に失敗しました",
    STATUS_CHANGE_FAILED: "ステータスの変更に失敗しました",
    ADMIN_SET_FAILED: "管理者設定に失敗しました",
    ADMIN_REMOVE_FAILED: "管理者削除に失敗しました",
    API_KEY_MISSING: "GEMINI_API_KEY is not set",
} as const;

// ===============================================
// 通知タイトル (NOTIFICATION_TITLES)
// ===============================================
export const NOTIFICATION_TITLES = {
    ACCOUNT_SUSPENDED: "アカウントが一時停止されました",
    ACCOUNT_PERMANENTLY_BANNED: "アカウントが永久停止されました",
    ACCOUNT_RESTRICTION_LIFTED: "アカウント制限が解除されました",

    CIRCLE_DELETED: "サークルを削除しました",
    CIRCLE_UPDATED: "サークルが更新されました",
    CIRCLE_DELETE_WARNING: "サークル削除予定のお知らせ",
    CIRCLE_AUTO_DELETED: "サークルが自動削除されました",
    JOIN_APPROVED: "参加が承認されました",
    JOIN_REJECTED: "参加申請が拒否されました",
    JOIN_REQUEST_RECEIVED: "参加申請が届きました",

    NEW_INQUIRY: "新しい問い合わせ",
    INQUIRY_REPLY: "問い合わせに返信",
    INQUIRY_REPLY_RECEIVED: "問い合わせに返信がありました",
    INQUIRY_STATUS_CHANGED: "問い合わせステータス変更",
    INQUIRY_DELETE_WARNING: "問い合わせ削除予定",

    POST_HIDDEN: "投稿が非表示になりました",
    POST_DELETED_BY_ADMIN: "投稿が削除されました",
    NEW_REPORT: "新しい通報を受信",
    REVIEW_NEEDED: "要審査投稿",

    COMMENT: "コメント",
    REACTION: "リアクション",
} as const;

// ===============================================
// 通知本文 (NOTIFICATION_BODIES)
// ===============================================
export const NOTIFICATION_BODIES = {
    POST_HIDDEN_BY_REPORTS: "複数の通報があったため、投稿を一時的に非表示にしました。内容をご確認ください。",
    POST_DELETED_BY_ADMIN: "運営による確認の結果、投稿が削除されました。",
    COMMENT_THANKED: "あなたのコメントがいいね！されました。",
    REPORT_SUBMITTED: "通報内容を運営チームで確認します。ご協力ありがとうございます。",
    flaggedPost: (reason: string) => `フラグ付き投稿があります: ${reason}`,
} as const;

// ===============================================
// ラベル・表示文言 (LABELS)
// ===============================================
export const LABELS = {
    OWNER: "オーナー",
    USER: "ユーザー",
    ANONYMOUS_USER: "匿名ユーザー",
    POSTER: "投稿者",
    SOMEONE: "誰か",
    CIRCLE: "サークル",
    ADMIN_TEAM: "運営チーム",
    NO_TEXT: "(テキストなし)",

    STATUS_OPEN: "未対応",
    STATUS_IN_PROGRESS: "対応中",
    STATUS_RESOLVED: "解決済み",

    CATEGORY_BUG: "バグ報告",
    CATEGORY_FEATURE: "機能要望",
    CATEGORY_ACCOUNT: "アカウント関連",
    CATEGORY_OTHER: "その他",

    CONTENT_ADULT: "成人向けコンテンツ",
    CONTENT_VIOLENCE: "暴力的コンテンツ",
    CONTENT_HATE: "差別的コンテンツ",
    CONTENT_DANGEROUS: "危険なコンテンツ",
    CONTENT_INAPPROPRIATE: "不適切なコンテンツ",

    MODE_AI: "AIモード",
    MODE_MIX: "MIXモード",
    MODE_HUMAN: "人間モード",

    HIDDEN_BY_REPORTS: "通報多数のため自動非表示",
    DELETE_REASON_GHOST: "1年間人間の投稿がなかったため自動削除",
    DELETE_REASON_ABANDONED: "投稿がなく放置されたため自動削除",

    WARNING_GHOST: "1年間人間の投稿がありません",
    WARNING_ABANDONED: "開始から1週間経過しても投稿がありません",

    WARNING_TYPE_GHOST: "ゴースト",
    WARNING_TYPE_ABANDONED: "放置",

    CHANGE_DESCRIPTION: "説明が変更されました",
    CHANGE_GOAL: "目標が変更されました",
    CHANGE_RULES: "ルールが変更されました",
    CHANGE_PUBLIC: "公開に変更",
    CHANGE_PRIVATE: "非公開に変更",
    CHANGE_INVITE_ONLY: "招待制に変更",
    CHANGE_INVITE_DISABLED: "招待制を解除",
} as const;

// ===============================================
// 成功メッセージ
// ===============================================
export const SUCCESS_MESSAGES = {
    NAME_PARTS_INITIALIZED: "名前パーツを初期化しました",
    NO_AI_USERS: "AIユーザーはいませんでした",

    nameChanged: (name: string) => `名前を「${name}」に変更しました`,
    itemDeleted: (name: string) => `${name}を削除しました`,
    adminSet: (uid: string) => `ユーザー ${uid} を管理者に設定しました`,
    adminRemoved: (uid: string) => `ユーザー ${uid} の管理者権限を削除しました`,
    usersUpdated: (count: number) => `${count}件のユーザーを更新しました`,
    aiUsersDeleted: (count: number) => `AIユーザー${count}人と関連データを削除しました`,
    orphanAIsDeleted: (deleted: number, notifications: number) =>
        `過去サークルAIを${deleted}件削除しました（通知${notifications}件）`,
    aiAccountsCreated: (count: number) =>
        `AIアカウントを作成/更新しました（Gemini API で bio 生成: ${count} 件）`,
    aiPostsScheduled: (count: number) =>
        `AI投稿タスクを${count}件スケジュールしました。`,
    circleAIPostsCreated: (count: number, max: number) =>
        `サークルAI投稿を${count}件作成しました（最大${max}件実行）`,
    circleAIsEvolved: (count: number) => `${count}件のサークルAIを進化しました`,
    joinApproved: (circleName: string) => `${circleName || "サークル"}への参加を承認しました`,
    joinRejected: (circleName: string) => `${circleName || "サークル"}への参加申請を拒否しました`,
} as const;

// ===============================================
// モデレーション関連
// ===============================================
export const MODERATION_MESSAGES = {
    NG_WORD_USED: "NGワードが含まれているため投稿できません",
    INAPPROPRIATE_CONTENT_DETECTED: "不適切な内容が検出されました",
    TEST_ADMIN_MEDIA: "【テスト】管理者の添付付き投稿",

    suggestionWithReason: (reason: string, suggestion: string) => `${reason}\n\n提案: ${suggestion}`,
    mediaBlockedSimple: (type: "video" | "image", category: string) =>
        `添付された${type === "video" ? "動画" : "画像"}に${category}が含まれている可能性があります。\n\n別のメディアを選択してください。`,
    mediaBlocked: (type: "video" | "image", category: string, virtue: number) =>
        `添付された${type === "video" ? "動画" : "画像"}に${category}が含まれている可能性があります。\n\n別のメディアを選択してください。\n\n(徳ポイント: ${virtue})`,
} as const;

// ===============================================
// 徳ポイント関連メッセージ
// ===============================================
export const VIRTUE_MESSAGES = {
    POST_CREATE_GRANT_REASON: "投稿作成による徳ポイント加算",
    COMMENT_THANKS_GIVEN_GRANT_REASON: "コメントにいいね！した",
    COMMENT_THANKS_RECEIVED_GRANT_REASON: "コメントがいいね！された",
    ADMIN_DELETE_POST_PENALTY_REASON: "運営削除（通報対応）",
} as const;

// ===============================================
// エラーメッセージ統合
// ===============================================
export const ERROR_MESSAGES = {
    ...AUTH_ERRORS,
    ...PERMISSION_ERRORS,
    ...RESOURCE_ERRORS,
    ...VALIDATION_ERRORS,
    ...SYSTEM_ERRORS,
} as const;
// ===============================================
// Comment Thanks Stamp
// ===============================================
export const COMMENT_THANKS_MESSAGES = {
    COMMENT_ID_REQUIRED: "commentId is required",
    COMMENT_NOT_FOUND: "comment not found",
    POST_NOT_FOUND: "post not found",
    POST_OWNER_ONLY: "only post owner can perform this action",
    SELF_COMMENT_NOT_ALLOWED: "cannot thank your own comment",
    ALREADY_THANKED: "comment already thanked",
} as const;

// ===============================================
// Stamp Sheet
// ===============================================
export const STAMP_SHEET_MESSAGES = {
    OP_ID_REQUIRED: "opId is required",
    BASE_VERSION_REQUIRED: "baseVersion is required",
    ENTRIES_REQUIRED: "entries is required",
    CREDITS_INVALID: "credits is invalid",
    SHEET_ID_REQUIRED: "sheetId is required",
    SLOT_ID_REQUIRED: "slotId is required",
    STAMP_ID_REQUIRED: "stampId is required",
    USER_NOT_FOUND: "user not found",
    STAMP_LOCKED: "stamp is locked",
    CREDIT_NOT_ENOUGH: "not enough thanks stamp credits",
    SHEET_NOT_FOUND: "stamp sheet not found",
    SHEET_LOCKED: "stamp sheet is locked",
    PAGE_INDEX_OUT_OF_RANGE: "pageIndex out of range",
    INVALID_SLOT_ID: "invalid slotId for this sheet",
    SNAPSHOT_CONFLICT: "snapshot version conflict",
    SLOT_IDS_NOT_CONFIGURED: "validSlotIds not configured for this sheet",
    SHEET_FULL: "sheet is full",
    NO_STAMP_TO_UNDO: "no stamp to undo",
    CURRENT_SHEET_ID_REQUIRED: "currentSheetId is required",
    NEXT_SHEET_ID_REQUIRED: "nextSheetId is required",
    CURRENT_SHEET_NOT_FULL: "current sheet is not full",
} as const;
