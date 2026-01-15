/**
 * Firestoreコレクション名定数
 * コレクション名の一元管理
 */

// メインコレクション
export const COLLECTIONS = {
    USERS: "users",
    POSTS: "posts",
    COMMENTS: "comments",
    REACTIONS: "reactions",
    CIRCLES: "circles",
    TASKS: "tasks",
    GOALS: "goals",
    REPORTS: "reports",
    INQUIRIES: "inquiries",
    NOTIFICATIONS: "notifications",

    // システム系
    SETTINGS: "settings",
    NAME_PARTS: "nameParts",
    MODERATED_CONTENT: "moderatedContent",
    MODERATION_ERRORS: "moderationErrors",
    PENDING_REVIEWS: "pendingReviews",

    // 履歴・ログ系
    VIRTUE_HISTORY: "virtueHistory",
    CIRCLE_AI_POST_HISTORY: "circleAIPostHistory",
} as const;

// サブコレクション用ヘルパー
export const SUB_COLLECTIONS = {
    userNotifications: (userId: string) => `users/${userId}/notifications`,
    userVirtueHistory: (userId: string) => `users/${userId}/virtueHistory`,
} as const;

// コレクション名の型
export type CollectionName = typeof COLLECTIONS[keyof typeof COLLECTIONS];
