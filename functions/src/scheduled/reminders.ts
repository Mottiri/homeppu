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

/**
 * 目標リマインダー通知を実行するCloud Tasks用のHTTPエンドポイント
 */
export const executeGoalReminder = functionsV1.region(LOCATION).runWith({
    timeoutSeconds: 30,
}).https.onRequest(async (request, response) => {
    // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
    const { verifyCloudTasksRequest } = await import("../helpers/cloud-tasks-auth");
    if (!await verifyCloudTasksRequest(request, "executeGoalReminder")) {
        response.status(403).send("Unauthorized");
        return;
    }

    try {
        const { goalId, userId, goalTitle, timeLabel, reminderKey, type } = request.body ?? {};

        if (!goalId || !userId) {
            response.status(400).send("Missing required fields");
            return;
        }

        const clientType = type === "on_time" ? "on_time" : "pre_reminder";
        const normalizedReminderKey = reminderKey || clientType;

        // 重複チェック
        const sentKey = `goal_${goalId}_${clientType}_${normalizedReminderKey}`;
        const sentDoc = await db.collection("sentReminders").doc(sentKey).get();
        if (sentDoc.exists) {
            console.log(`[GoalReminder] Already sent: ${sentKey}`);
            response.status(200).send("Already sent");
            return;
        }

        // 目標がまだ存在し、未完了か確認
        const goalDoc = await db.collection("goals").doc(goalId).get();
        if (!goalDoc.exists) {
            console.log(`[GoalReminder] Goal ${goalId} not found`);
            response.status(200).send("Goal not found");
            return;
        }

        const goalData = goalDoc.data();
        if (goalData?.completedAt) {
            console.log(`[GoalReminder] Goal ${goalId} is already completed`);
            response.status(200).send("Goal completed");
            return;
        }

        // ユーザーのFCMトークン取得
        const userDoc = await db.collection("users").doc(userId).get();
        if (!userDoc.exists) {
            console.log(`[GoalReminder] User ${userId} not found`);
            response.status(200).send("User not found");
            return;
        }

        const fcmToken = userDoc.data()?.fcmToken;
        if (!fcmToken) {
            console.log(`[GoalReminder] User ${userId} has no FCM token`);
            response.status(200).send("No FCM token");
            return;
        }

        const safeGoalTitle = goalTitle || goalData?.title || "目標";
        const title = clientType === "on_time" ? "🚩 目標の期限です！" : "🚩 目標リマインダー";
        const body = clientType === "on_time"
            ? `「${safeGoalTitle}」の期限になりました。達成状況を確認しましょう！`
            : `「${safeGoalTitle}」の期限まで${timeLabel || "まもなく"}です`;

        // 通知を保存 (onNotificationCreatedにより自動でプッシュ通知も送信される)
        await db.collection("users").doc(userId).collection("notifications").add({
            type: "goal_reminder",
            title,
            body,
            isRead: false,
            createdAt: FieldValue.serverTimestamp(),
            goalId,
            reminderKey: normalizedReminderKey,
            clientType,
        });

        // 送信済みとして記録
        await db.collection("sentReminders").doc(sentKey).set({
            goalId,
            userId,
            type: clientType,
            reminderKey: normalizedReminderKey,
            sentAt: FieldValue.serverTimestamp(),
        });

        console.log(`[GoalReminder] Notification saved for ${goalId} - ${clientType}`);
        response.status(200).send("Notification saved");
    } catch (error) {
        console.error("[GoalReminder] Error:", error);
        response.status(500).send("Error");
    }
});

