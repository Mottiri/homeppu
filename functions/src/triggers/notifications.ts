/**
 * 通知関連のトリガー関数
 * Phase 6: index.ts から分離
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";

import { db, FieldValue } from "../helpers/firebase";
import { sendPushNotification, sendPushOnly } from "../helpers/notification";
import { LOCATION } from "../config/constants";

type PushPolicy = "always" | "never" | "bySettings";

function resolvePushPolicy(type: string, pushPolicy?: unknown): PushPolicy {
    if (pushPolicy === "always" || pushPolicy === "never" || pushPolicy === "bySettings") {
        return pushPolicy;
    }
    // 既定: コメント/リアクションのみ設定尊重、それ以外は常に送信
    return type === "comment" || type === "reaction" ? "bySettings" : "always";
}

/**
 * 通知ドキュメント作成時に自動でプッシュ通知を送信
 * - 設定で止めるのは comment / reaction のみ
 * - pushPolicy=never で「通知は作るがpushは送らない」を明示できる
 */
export const onNotificationCreated = onDocumentCreated(
    {
        document: "users/{userId}/notifications/{notificationId}",
        region: LOCATION,
    },
    async (event) => {
        const snap = event.data;
        if (!snap) return;

        const data = snap.data();
        const userId = event.params.userId;
        const notificationId = event.params.notificationId;
        const notificationRef = snap.ref;

        const title = data?.title;
        const body = data?.body;
        const type = String(data?.type ?? "system");
        const pushPolicy = resolvePushPolicy(type, data?.pushPolicy);

        // 送信ステータスを先に記録（運用上の追跡性を上げる）
        await notificationRef.set(
            {
                pushPolicy,
                pushStatus: "pending",
            },
            { merge: true }
        );

        // タイトル/本文がない場合は送信しない
        if (!title || !body) {
            await notificationRef.set(
                {
                    pushStatus: "skipped",
                    pushSkippedReason: "missing_title_or_body",
                },
                { merge: true }
            );
            return;
        }

        // 明示的にpushを送らない
        if (pushPolicy === "never") {
            await notificationRef.set(
                {
                    pushStatus: "skipped",
                    pushSkippedReason: "push_policy_never",
                },
                { merge: true }
            );
            return;
        }

        // 設定尊重が必要な場合のみユーザー設定を確認
        if (pushPolicy === "bySettings") {
            const userDoc = await db.collection("users").doc(userId).get();
            if (!userDoc.exists) {
                await notificationRef.set(
                    {
                        pushStatus: "skipped",
                        pushSkippedReason: "user_not_found",
                    },
                    { merge: true }
                );
                return;
            }

            const settings = userDoc.data()?.notificationSettings ?? {};
            if (type === "comment" && settings.comments === false) {
                await notificationRef.set(
                    {
                        pushStatus: "skipped",
                        pushSkippedReason: "settings_disabled_comments",
                    },
                    { merge: true }
                );
                return;
            }
            if (type === "reaction" && settings.reactions === false) {
                await notificationRef.set(
                    {
                        pushStatus: "skipped",
                        pushSkippedReason: "settings_disabled_reactions",
                    },
                    { merge: true }
                );
                return;
            }
        }

        try {
            await sendPushOnly(userId, String(title), String(body), {
                ...data,
                notificationId,
            });

            await notificationRef.set(
                {
                    pushStatus: "sent",
                    pushSentAt: FieldValue.serverTimestamp(),
                },
                { merge: true }
            );
        } catch (error: unknown) {
            const errorCode =
                error && typeof error === "object" && "code" in error
                    ? String((error as { code?: unknown }).code ?? "unknown")
                    : "unknown";

            await notificationRef.set(
                {
                    pushStatus: "error",
                    pushErrorCode: errorCode,
                },
                { merge: true }
            );
        }
    }
);

/**
 * コメント作成時に投稿者へ通知
 */
export const onCommentCreatedNotify = onDocumentCreated(
    {
        document: "comments/{commentId}",
        region: LOCATION,
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
                senderAvatarUrl: String(commentData.userAvatarIndex ?? ""),
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
        region: LOCATION,
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
                senderAvatarUrl: "",
            }
        );
    }
);
