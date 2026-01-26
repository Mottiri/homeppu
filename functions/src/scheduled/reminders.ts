/**
 * リマインダー通知関連（Cloud Tasks用HTTP）
 * Phase 7: index.ts から分離
 */

import * as functionsV1 from "firebase-functions/v1";

import { db, FieldValue } from "../helpers/firebase";
import { LOCATION } from "../config/constants";

/**
 * リマインダー通知を実行するCloud Tasks用のHTTPエンドポイント
 */
export const executeTaskReminder = functionsV1.region(LOCATION).runWith({
    timeoutSeconds: 30,
}).https.onRequest(async (request, response) => {
    // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
    const { verifyCloudTasksRequest } = await import("../helpers/cloud-tasks-auth");
    if (!await verifyCloudTasksRequest(request, "executeTaskReminder")) {
        response.status(403).send("Unauthorized");
        return;
    }

    try {
        const { taskId, userId, taskContent, timeLabel, reminderKey, type } = request.body;

        console.log(`[Reminder] Executing reminder: ${taskId} - ${reminderKey}`);

        // タスクがまだ存在し、未完了か確認
        const taskDoc = await db.collection("tasks").doc(taskId).get();
        if (!taskDoc.exists) {
            console.log(`[Reminder] Task ${taskId} not found, skipping`);
            response.status(200).send("Task not found");
            return;
        }

        const taskData = taskDoc.data();
        if (taskData?.isCompleted) {
            console.log(`[Reminder] Task ${taskId} is completed, skipping`);
            response.status(200).send("Task completed");
            return;
        }

        // 送信済みかチェック
        const sentRef = db.collection("sentReminders").doc(`${taskId}_${reminderKey}`);
        const sentDoc = await sentRef.get();
        if (sentDoc.exists) {
            console.log(`[Reminder] Already sent: ${taskId} - ${reminderKey}`);
            response.status(200).send("Already sent");
            return;
        }

        // ユーザーのFCMトークンを取得
        const userDoc = await db.collection("users").doc(userId).get();
        if (!userDoc.exists) {
            console.log(`[Reminder] User ${userId} not found`);
            response.status(200).send("User not found");
            return;
        }

        const fcmToken = userDoc.data()?.fcmToken;
        if (!fcmToken) {
            console.log(`[Reminder] No FCM token for user: ${userId}`);
            response.status(200).send("No FCM token");
            return;
        }

        // 通知を保存 (onNotificationCreatedにより自動でプッシュ通知も送信される)
        const title = type === "on_time" ? "📋 タスクの時間です" : "🔔 タスクリマインダー";
        const body = type === "on_time"
            ? `「${taskContent}」の予定時刻になりました`
            : `「${taskContent}」の${timeLabel}です`;

        await db.collection("users").doc(userId).collection("notifications").add({
            type: "task_reminder",
            title,
            body,
            isRead: false,
            createdAt: FieldValue.serverTimestamp(),
            taskId,
            reminderKey,
            clientType: type,
        });

        console.log(`[Reminder] Notification saved for ${taskId} - ${reminderKey}`);

        // 送信済みとして記録
        await sentRef.set({
            taskId,
            userId,
            reminderKey,
            sentAt: FieldValue.serverTimestamp(),
        });

        console.log(`[Reminder] Sent: ${taskId} - ${reminderKey}`);
        response.status(200).send("Notification sent");
    } catch (error) {
        console.error("[Reminder] Error:", error);
        response.status(500).send("Error");
    }
});
