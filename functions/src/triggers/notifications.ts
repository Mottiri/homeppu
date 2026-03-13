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
 * skip判定を集約する関数
 * 送信不要な理由がある場合はその理由文字列を返す。送信すべき場合はnullを返す。
 */
function getSkipReason(
    userData: FirebaseFirestore.DocumentData | undefined,
    data: FirebaseFirestore.DocumentData,
    pushPolicy: PushPolicy
): string | null {
    const title = data?.title;
    const body = data?.body;
    const type = String(data?.type ?? "system");

    // タイトル/本文がない場合は送信しない
    if (!title || !body) {
        return "missing_title_or_body";
    }

    // 明示的にpushを送らない
    if (pushPolicy === "never") {
        return "push_policy_never";
    }

    // 設定尊重が必要な場合のみユーザー設定を確認
    if (pushPolicy === "bySettings") {
        if (!userData) {
            return "user_not_found";
        }

        const settings = userData.notificationSettings ?? {};
        if (type === "comment" && settings.comments === false) {
            return "comment_notification_disabled";
        }
        if (type === "reaction" && settings.reactions === false) {
            return "reaction_notification_disabled";
        }
    }

    return null;
}

/**
 * 通知ドキュメント作成時に自動でプッシュ通知を送信
 * - 設定で止めるのは comment / reaction のみ
 * - pushPolicy=never で「通知は作るがpushは送らない」を明示できる
 * - pushStatus 5状態管理 + CAS で重複FCM送信を防止
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
        const notifRef = snap.ref;

        const title = data?.title;
        const body = data?.body;
        const type = String(data?.type ?? "system");
        const pushPolicy = resolvePushPolicy(type, data?.pushPolicy);

        // ユーザードキュメントを取得（skip判定に使用）
        const userDoc = await db.collection("users").doc(userId).get();
        const userData = userDoc.data();

        const skipReason = getSkipReason(userData, data, pushPolicy);

        // === 単一トランザクションで初期化+skipped判定+CASを原子的に実行 ===
        const acquired = await db.runTransaction(async (tx) => {
            const freshSnap = await tx.get(notifRef);
            const freshData = freshSnap.data();
            if (!freshData) return false;

            const currentStatus = freshData.pushStatus;

            // 既に終端状態（sent/failed/skipped/sending）→ 何もしない（巻き戻し防止）
            // pushStatus未設定（undefined）= 初期状態 = pendingと同等に扱う
            if (currentStatus && currentStatus !== "pending") {
                return false;
            }

            // skipped 判定（CAS取得前）
            if (skipReason) {
                tx.update(notifRef, {
                    pushPolicy,
                    pushStatus: "skipped",
                    pushSkippedReason: skipReason,
                    pushStatusUpdatedAt: FieldValue.serverTimestamp(),
                });
                return false; // skipped は送信しない
            }

            // CAS: pending（または未設定）→ sending に遷移
            tx.update(notifRef, {
                pushPolicy,
                pushStatus: "sending",
            });
            return true;
        });

        if (!acquired) return; // 送信権を獲得できなかった or skipped

        // FCM送信（送信権を獲得した1実行のみがここに到達）
        const pushData = {
            ...data,
            notificationId,
        };
        const result = await sendPushOnly(userId, String(title), String(body), pushData);

        // 送信結果に応じてステータス更新
        if (result.outcome === "skipped") {
            await notifRef.update({
                pushStatus: "skipped",
                pushSkippedReason: result.skippedReason ?? "unknown",
                pushStatusUpdatedAt: FieldValue.serverTimestamp(),
            });
        } else {
            await notifRef.update({
                pushStatus: result.outcome, // "sent" or "failed"
                pushStatusUpdatedAt: FieldValue.serverTimestamp(),
            });
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
        const commentId = event.params.commentId;
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

        // 通知を送信（sourceIdにcommentIdを使用）
        await sendPushNotification(
            postOwnerId,
            "comment",
            commentId,
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
        const reactionId = event.params.reactionId;
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

        // 通知を送信（sourceIdにreactionIdを使用）
        await sendPushNotification(
            postOwnerId,
            "reaction",
            reactionId,
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
