/**
 * 通知関連のトリガー関数
 * Phase 6: index.ts から分離
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";

import { db } from "../helpers/firebase";
import { sendPushNotification } from "../helpers/notification";

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
                senderAvatarUrl: "",
            }
        );
    }
);
