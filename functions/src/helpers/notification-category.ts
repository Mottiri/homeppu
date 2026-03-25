/**
 * 通知タイプからカテゴリへのマッピング
 * S6: 通知未読カウントの非正規化で使用
 */

export type NotificationCategory = "timeline" | "circle" | "support";

const TYPE_TO_CATEGORY: Record<string, NotificationCategory> = {
    comment: "timeline",
    reaction: "timeline",
    system: "timeline",
    join_request_received: "circle",
    join_request_approved: "circle",
    join_request_rejected: "circle",
    circle_deleted: "circle",
    circle_settings_changed: "circle",
    circle_ghost_warning: "circle",
    circle_ghost_deleted: "circle",
    sub_owner_appointed: "circle",
    sub_owner_removed: "circle",
    inquiry_reply: "support",
    inquiry_status_changed: "support",
    inquiry_received: "support",
    inquiry_user_reply: "support",
    inquiry_deletion_warning: "support",
    admin_report: "support",
    review_needed: "support",
    post_deleted: "support",
    post_hidden: "support",
    user_banned: "support",
    user_unbanned: "support",
};

export function getNotificationCategory(type: string): NotificationCategory {
    return TYPE_TO_CATEGORY[type] ?? "timeline";
}

export function getCategoryCountField(category: NotificationCategory): string {
    switch (category) {
        case "timeline": return "unreadTimelineCount";
        case "circle": return "unreadCircleCount";
        case "support": return "unreadSupportCount";
    }
}
