/**
 * Notification helper utilities.
 */

import * as admin from "firebase-admin";
import { db, FieldValue } from "./firebase";

export type SendPushResult =
    | { outcome: "sent" }
    | { outcome: "skipped"; skippedReason: string }
    | { outcome: "failed" };

/**
 * Sends push notification only (does not write Firestore notification docs).
 * 戻り値で送信結果を返す（sent/skipped/failed）。
 */
export async function sendPushOnly(
    userId: string,
    title: string,
    body: string,
    data?: Record<string, unknown>
): Promise<SendPushResult> {
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;

    if (!fcmToken) {
        console.info(`No FCM token for user ${userId}, skipping push`);
        return { outcome: "skipped", skippedReason: "missing_fcm_token" };
    }

    const channelId = "default_channel";

    // FCM data payload accepts only string values.
    const stringifiedData: { [key: string]: string } = {};
    if (data) {
        for (const [key, value] of Object.entries(data)) {
            if (value !== undefined && value !== null) {
                if (typeof value === "object" && "toDate" in value && typeof value.toDate === "function") {
                    stringifiedData[key] = value.toDate().toISOString();
                } else {
                    stringifiedData[key] = String(value);
                }
            }
        }
    }

    const message: admin.messaging.Message = {
        token: fcmToken,
        notification: {
            title,
            body,
        },
        data: stringifiedData,
        android: {
            priority: "high",
            notification: {
                channelId,
            },
        },
        apns: {
            payload: {
                aps: {
                    sound: "default",
                    badge: 1,
                },
            },
        },
    };

    try {
        await admin.messaging().send(message);
        console.log(`Push notification sent to user ${userId}: ${title} (channel: ${channelId})`);
        return { outcome: "sent" };
    } catch (error: unknown) {
        if (error && typeof error === "object" && "code" in error) {
            const firebaseError = error as { code: string };
            if (
                firebaseError.code === "messaging/invalid-registration-token" ||
                firebaseError.code === "messaging/registration-token-not-registered"
            ) {
                console.log(`Removing invalid FCM token for user ${userId}`);
                await db.collection("users").doc(userId).update({
                    fcmToken: FieldValue.delete(),
                });
                return { outcome: "skipped", skippedReason: "invalid_fcm_token" };
            }
        }
        console.error(`Error sending push notification to ${userId}:`, error);
        return { outcome: "failed" };
    }
}

/**
 * Writes in-app notification to Firestore with deterministic ID.
 * Push delivery is handled by the onNotificationCreated trigger.
 * create-only: 既存ドキュメントがあれば何もしない（pushStatusの巻き戻し防止）。
 */
export async function sendPushNotification(
    userId: string,
    type: string,
    sourceId: string,
    title: string,
    body: string,
    data: { [key: string]: string } = {},
    options?: {
        type: string;
        senderId: string;
        senderName: string;
        senderAvatarUrl?: string;
        idempotencyKey?: string;
        throwOnError?: boolean;
    }
): Promise<void> {
    try {
        if (options) {
            // deterministic通知ID: {type}-{sourceId}-{recipientId}
            const notificationIdSuffix = options.idempotencyKey ?
                `-${options.idempotencyKey}` :
                "";
            const notificationId = `${type}-${sourceId}-${userId}${notificationIdSuffix}`;
            const notifRef = db.collection("users").doc(userId)
                .collection("notifications").doc(notificationId);

            // create-only: 既存ドキュメントがある場合は何もしない（pushStatusの巻き戻し防止）
            const existing = await notifRef.get();
            if (existing.exists) return;

            await notifRef.set({
                userId: userId,
                senderId: options.senderId,
                senderName: options.senderName,
                senderAvatarUrl: options.senderAvatarUrl || "",
                type: options.type,
                title: title,
                body: body,
                postId: data.postId || null,
                isRead: false,
                createdAt: FieldValue.serverTimestamp(),
                canonicalIdempotencyKey: options.idempotencyKey ?? null,
            });
            console.log(`Notification saved to Firestore for user: ${userId} (FCM will be sent by onNotificationCreated)`);
        } else {
            const message = `sendPushNotification called without options - notification will NOT be created for user: ${userId}`;
            console.warn(message);
        }
    } catch (error) {
        console.error(`Failed to save notification for ${userId}: `, error);
        if (options?.throwOnError) {
            throw error;
        }
    }
}
