/**
 * 通知送信ヘルパー
 * Phase 6: index.ts から分離
 */

import * as admin from "firebase-admin";
import { db, FieldValue } from "./firebase";

/**
 * 指定ユーザーにプッシュ通知のみを送信（Firestore保存なし）
 */
export async function sendPushOnly(
    userId: string,
    title: string,
    body: string,
    data?: Record<string, unknown>
): Promise<void> {
    try {
        const userDoc = await db.collection("users").doc(userId).get();
        const userData = userDoc.data();
        const fcmToken = userData?.fcmToken;

        if (!fcmToken) {
            console.log(`No FCM token for user ${userId}, skipping push notification`);
            return;
        }

        // チャンネルIDの決定
        let channelId = "default_channel";
        if (data?.type === "task_reminder" || data?.type === "task_due") {
            channelId = "task_reminders";
        }

        // FCM dataペイロードは全て文字列である必要があるため変換
        const stringifiedData: { [key: string]: string } = {};
        if (data) {
            for (const [key, value] of Object.entries(data)) {
                if (value !== undefined && value !== null) {
                    // Timestamp オブジェクトの場合は toDate().toISOString() を使用
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

        await admin.messaging().send(message);
        console.log(`Push notification sent to user ${userId}: ${title} (channel: ${channelId})`);
    } catch (error: unknown) {
        // トークンが無効な場合はトークンを削除
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
            }
        }
        console.error(`Error sending push notification to ${userId}:`, error);
    }
}

/**
 * プッシュ通知を送信（Firestore保存 + FCM送信）
 */
export async function sendPushNotification(
    userId: string,
    title: string,
    body: string,
    data: { [key: string]: string } = {},
    options?: {
        type: "comment" | "reaction" | "system";
        senderId: string;
        senderName: string;
        senderAvatarUrl?: string;
    }
): Promise<void> {
    try {
        // 1. Firestoreに通知ドキュメントを保存 (オプション指定時)
        if (options) {
            await db.collection("users").doc(userId).collection("notifications").add({
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
            });
            console.log(`Notification saved to Firestore for user: ${userId}`);
        }

        // 2. FCMトークン取得
        const userDoc = await db.collection("users").doc(userId).get();
        if (!userDoc.exists) {
            console.log(`User not found: ${userId} `);
            return;
        }

        const userData = userDoc.data();
        const fcmToken = userData?.fcmToken;

        if (!fcmToken) {
            console.log(`No FCM token for user: ${userId} `);
            return;
        }

        // 2.5 通知設定の確認
        if (options && userData?.notificationSettings) {
            const type = options.type;
            // 設定キーへのマッピング (comment -> comments, reaction -> reactions)
            const settingKey = type === "comment" ? "comments" : type === "reaction" ? "reactions" : null;

            if (settingKey && userData.notificationSettings[settingKey] === false) {
                console.log(`Notification skipped due to user setting: ${type} for user ${userId}`);
                return;
            }
        }

        // 3. FCM送信
        const fcmData: { [key: string]: string } = {
            ...data,
        };
        if (options?.type) {
            fcmData.type = options.type;
        }

        const message = {
            token: fcmToken,
            notification: {
                title,
                body,
            },
            data: fcmData,
            android: {
                priority: "high" as const,
                notification: {
                    sound: "default",
                    channelId: "default_channel",
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

        await admin.messaging().send(message);
        console.log(`Push notification sent to ${userId}: ${title} `);
    } catch (error) {
        console.error(`Failed to send push notification to ${userId}: `, error);
    }
}
