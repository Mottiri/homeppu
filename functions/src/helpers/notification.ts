/**
 * Notification helper utilities.
 */

import * as admin from "firebase-admin";
import { db, FieldValue } from "./firebase";

/**
 * Sends push notification only (does not write Firestore notification docs).
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

        await admin.messaging().send(message);
        console.log(`Push notification sent to user ${userId}: ${title} (channel: ${channelId})`);
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
            }
        }
        console.error(`Error sending push notification to ${userId}:`, error);
    }
}

/**
 * Writes in-app notification to Firestore.
 * Push delivery is handled by the onNotificationCreated trigger.
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
            console.log(`Notification saved to Firestore for user: ${userId} (FCM will be sent by onNotificationCreated)`);
        } else {
            console.warn(`sendPushNotification called without options - notification will NOT be created for user: ${userId}`);
        }
    } catch (error) {
        console.error(`Failed to save notification for ${userId}: `, error);
    }
}
