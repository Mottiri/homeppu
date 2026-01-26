/**
 * タスク関連のトリガー関数
 * Phase 6: index.ts から分離
 */

import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { CloudTasksClient } from "@google-cloud/tasks";

import { db, FieldValue, Timestamp as FirestoreTimestamp } from "../helpers/firebase";
import { LOCATION, PROJECT_ID } from "../config/constants";

/**
 * タスクが更新された時の処理
 * - 完了状態になった場合: 徳ポイントとストリークの計算
 */
export const onTaskUpdated = onDocumentUpdated(
    {
        document: "tasks/{taskId}",
        region: LOCATION,
    },
    async (event) => {
        const before = event.data?.before.data();
        const after = event.data?.after.data();

        if (!before || !after) return;

        // 1. 完了状態への変化を検知 (false -> true)
        if (!before.isCompleted && after.isCompleted) {
            const userId = after.userId;

            // ストリーク計算のための前回完了日時取得
            // 折衷案: ユーザーデータに `lastTaskCompletedAt` と `currentStreak` を持たせる。

            const userRef = db.collection("users").doc(userId);

            await db.runTransaction(async (transaction) => {
                const userDoc = await transaction.get(userRef);
                if (!userDoc.exists) return; // ユーザーがいない

                const userData = userDoc.data()!;
                const now = new Date();
                const lastCompleted = userData.lastTaskCompletedAt?.toDate();

                let newStreak = 1;
                let streakBonus = 0;

                if (lastCompleted) {
                    // 日付の差分計算 (JST考慮が必要だが、UTCベースの日付差分で簡易判定)
                    const diffTime = now.getTime() - lastCompleted.getTime();
                    const diffDays = diffTime / (1000 * 3600 * 24);

                    if (diffDays < 1.5 && now.getDate() !== lastCompleted.getDate()) {
                        // "昨日"完了している（大体36時間以内かつ日付が違う）
                        newStreak = (userData.currentStreak || 0) + 1;
                    } else if (now.getDate() === lastCompleted.getDate()) {
                        // 今日すでに完了している -> ストリーク維持
                        newStreak = userData.currentStreak || 1;
                    } else {
                        // 途切れた
                        newStreak = 1;
                    }
                }

                // ポイント計算
                const baseVirtue = 2;
                streakBonus = Math.min(newStreak - 1, 5);
                const virtueGain = baseVirtue + streakBonus;

                // User更新
                transaction.update(userRef, {
                    virtue: FieldValue.increment(virtueGain),
                    currentStreak: newStreak,
                    lastTaskCompletedAt: FieldValue.serverTimestamp(),
                });

                // 履歴記録
                const historyRef = db.collection("virtueHistory").doc();
                transaction.set(historyRef, {
                    userId: userId,
                    change: virtueGain,
                    reason: `タスク完了: ${after.content} ${newStreak > 1 ? `(${newStreak}連!)` : ""}`,
                    createdAt: FieldValue.serverTimestamp(),
                });
            });
        }

        // 2. 完了取り消し (true -> false)
        if (before.isCompleted && !after.isCompleted) {
            // ポイント減算
            const userId = after.userId;

            await db.runTransaction(async (transaction) => {
                const userRef = db.collection("users").doc(userId);
                transaction.update(userRef, {
                    virtue: FieldValue.increment(-2), // 最低限引く
                });

                // 履歴
                const historyRef = db.collection("virtueHistory").doc();
                transaction.set(historyRef, {
                    userId: userId,
                    change: -2,
                    reason: `タスク完了取消: ${after.content}`,
                    createdAt: FieldValue.serverTimestamp(),
                });
            });
        }
    }
);

// ===============================================
// タスクリマインダー通知（イベント駆動方式）
// タスク作成/更新時にCloud Tasksにリマインダーを登録
// ===============================================

const TASK_REMINDER_QUEUE = "task-reminders";

/**
 * リマインダー時刻を計算
 */
function calculateReminderTime(
    scheduledAt: Date,
    reminder: { unit: string; value: number }
): Date {
    const ms = scheduledAt.getTime();
    if (reminder.unit === "minutes") {
        return new Date(ms - reminder.value * 60 * 1000);
    } else if (reminder.unit === "hours") {
        return new Date(ms - reminder.value * 60 * 60 * 1000);
    } else if (reminder.unit === "days") {
        return new Date(ms - reminder.value * 24 * 60 * 60 * 1000);
    }
    return new Date(ms);
}

/**
 * タスク作成/更新時にリマインダーをスケジュール
 */
export const scheduleTaskReminders = onDocumentUpdated(
    { document: "tasks/{taskId}", region: LOCATION },
    async (event) => {
        const taskId = event.params.taskId;
        const beforeData = event.data?.before.data();
        const afterData = event.data?.after.data();

        if (!afterData) return;

        // 完了したタスクは無視
        if (afterData.isCompleted) {
            console.log(`[Reminder] Task ${taskId} is completed, skipping`);
            return;
        }

        const scheduledAt = afterData.scheduledAt && typeof afterData.scheduledAt.toDate === "function"
            ? afterData.scheduledAt.toDate()
            : null;
        if (!scheduledAt) {
            console.log(`[Reminder] Task ${taskId} has no scheduledAt`);
            return;
        }

        // リマインダーが変更されていない場合はスキップ
        const beforeReminders = JSON.stringify(beforeData?.reminders || []);
        const afterReminders = JSON.stringify(afterData.reminders || []);
        if (beforeReminders === afterReminders && beforeData?.scheduledAt?.isEqual(afterData.scheduledAt)) {
            console.log(`[Reminder] No changes in reminders for ${taskId}`);
            return;
        }

        const userId = afterData.userId as string;
        const taskContent = (afterData.content as string) || "タスク";
        const reminders = afterData.reminders as Array<{ unit: string; value: number }> | undefined;

        console.log(`[Reminder] Scheduling reminders for task ${taskId}`);

        const tasksClient = new CloudTasksClient();
        const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
        const location = LOCATION;

        const queuePath = tasksClient.queuePath(project, location, TASK_REMINDER_QUEUE);
        const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeTaskReminder`;
        const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

        const now = new Date();

        // 1. 事前リマインダー
        if (reminders && reminders.length > 0) {
            for (const reminder of reminders) {
                const reminderTime = calculateReminderTime(scheduledAt, reminder);

                if (reminderTime <= now) {
                    console.log(`[Reminder] Skipping past reminder: ${reminderTime.toISOString()}`);
                    continue;
                }

                const reminderKey = `${reminder.unit}_${reminder.value}`;
                const timeLabel = reminder.unit === "minutes"
                    ? `${reminder.value}分前`
                    : reminder.unit === "hours"
                        ? `${reminder.value}時間前`
                        : `${reminder.value}日前`;

                const payload = {
                    taskId,
                    userId,
                    taskContent,
                    timeLabel,
                    reminderKey,
                    type: "pre_reminder",
                };

                try {
                    const [task] = await tasksClient.createTask({
                        parent: queuePath,
                        task: {
                            httpRequest: {
                                httpMethod: "POST",
                                url: targetUrl,
                                body: Buffer.from(JSON.stringify(payload)).toString("base64"),
                                headers: { "Content-Type": "application/json" },
                                oidcToken: { serviceAccountEmail },
                            },
                            scheduleTime: { seconds: Math.floor(reminderTime.getTime() / 1000) },
                        },
                    });

                    await db.collection("scheduledReminders").add({
                        taskId,
                        reminderKey,
                        cloudTaskName: task.name,
                        scheduledFor: FirestoreTimestamp.fromDate(reminderTime),
                        createdAt: FieldValue.serverTimestamp(),
                    });

                    console.log(`[Reminder] Scheduled: ${taskId} - ${reminderKey} at ${reminderTime.toISOString()}`);
                } catch (error) {
                    console.error(`[Reminder] Failed to schedule: ${reminderKey}`, error);
                }
            }
        }

        // 2. 予定時刻ちょうどの通知
        if (scheduledAt > now) {
            const payload = {
                taskId,
                userId,
                taskContent,
                timeLabel: "予定時刻",
                reminderKey: "on_time",
                type: "on_time",
            };

            try {
                const [task] = await tasksClient.createTask({
                    parent: queuePath,
                    task: {
                        httpRequest: {
                            httpMethod: "POST",
                            url: targetUrl,
                            body: Buffer.from(JSON.stringify(payload)).toString("base64"),
                            headers: { "Content-Type": "application/json" },
                            oidcToken: { serviceAccountEmail },
                        },
                        scheduleTime: { seconds: Math.floor(scheduledAt.getTime() / 1000) },
                    },
                });

                await db.collection("scheduledReminders").add({
                    taskId,
                    reminderKey: "on_time",
                    cloudTaskName: task.name,
                    scheduledFor: FirestoreTimestamp.fromDate(scheduledAt),
                    createdAt: FieldValue.serverTimestamp(),
                });

                console.log(`[Reminder] Scheduled on-time: ${taskId} at ${scheduledAt.toISOString()}`);
            } catch (error) {
                console.error(`[Reminder] Failed to schedule on-time`, error);
            }
        }
    }
);

/**
 * タスク作成時にリマインダーをスケジュール
 */
export const scheduleTaskRemindersOnCreate = onDocumentCreated(
    { document: "tasks/{taskId}", region: LOCATION },
    async (event) => {
        const taskId = event.params.taskId;
        const data = event.data?.data();

        if (!data) return;

        // 完了したタスクは無視
        if (data.isCompleted) return;

        const scheduledAt = data.scheduledAt && typeof data.scheduledAt.toDate === "function"
            ? data.scheduledAt.toDate()
            : null;
        if (!scheduledAt) return;

        const userId = data.userId as string;
        const taskContent = (data.content as string) || "タスク";
        const reminders = data.reminders as Array<{ unit: string; value: number }> | undefined;

        console.log(`[Reminder] Scheduling reminders for new task ${taskId}`);

        const tasksClient = new CloudTasksClient();
        const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
        const location = LOCATION;

        const queuePath = tasksClient.queuePath(project, location, TASK_REMINDER_QUEUE);
        const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeTaskReminder`;
        const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

        const now = new Date();

        // 1. 事前リマインダー
        if (reminders && reminders.length > 0) {
            for (const reminder of reminders) {
                const reminderTime = calculateReminderTime(scheduledAt, reminder);

                if (reminderTime <= now) continue;

                const reminderKey = `${reminder.unit}_${reminder.value}`;
                const timeLabel = reminder.unit === "minutes"
                    ? `${reminder.value}分前`
                    : reminder.unit === "hours"
                        ? `${reminder.value}時間前`
                        : `${reminder.value}日前`;

                const payload = {
                    taskId,
                    userId,
                    taskContent,
                    timeLabel,
                    reminderKey,
                    type: "pre_reminder",
                };

                try {
                    const [task] = await tasksClient.createTask({
                        parent: queuePath,
                        task: {
                            httpRequest: {
                                httpMethod: "POST",
                                url: targetUrl,
                                body: Buffer.from(JSON.stringify(payload)).toString("base64"),
                                headers: { "Content-Type": "application/json" },
                                oidcToken: { serviceAccountEmail },
                            },
                            scheduleTime: { seconds: Math.floor(reminderTime.getTime() / 1000) },
                        },
                    });

                    await db.collection("scheduledReminders").add({
                        taskId,
                        reminderKey,
                        cloudTaskName: task.name,
                        scheduledFor: FirestoreTimestamp.fromDate(reminderTime),
                        createdAt: FieldValue.serverTimestamp(),
                    });

                    console.log(`[Reminder] Scheduled: ${taskId} - ${reminderKey}`);
                } catch (error) {
                    console.error(`[Reminder] Failed to schedule: ${reminderKey}`, error);
                }
            }
        }

        // 2. 予定時刻ちょうどの通知
        if (scheduledAt > now) {
            const payload = {
                taskId,
                userId,
                taskContent,
                timeLabel: "予定時刻",
                reminderKey: "on_time",
                type: "on_time",
            };

            try {
                const [task] = await tasksClient.createTask({
                    parent: queuePath,
                    task: {
                        httpRequest: {
                            httpMethod: "POST",
                            url: targetUrl,
                            body: Buffer.from(JSON.stringify(payload)).toString("base64"),
                            headers: { "Content-Type": "application/json" },
                            oidcToken: { serviceAccountEmail },
                        },
                        scheduleTime: { seconds: Math.floor(scheduledAt.getTime() / 1000) },
                    },
                });

                await db.collection("scheduledReminders").add({
                    taskId,
                    reminderKey: "on_time",
                    cloudTaskName: task.name,
                    scheduledFor: FirestoreTimestamp.fromDate(scheduledAt),
                    createdAt: FieldValue.serverTimestamp(),
                });

                console.log(`[Reminder] Scheduled on-time: ${taskId}`);
            } catch (error) {
                console.error(`[Reminder] Failed to schedule on-time`, error);
            }
        }
    }
);
