/**
 * 目標リマインダー関連のFirestoreトリガー
 * Phase 7: index.ts から分離（復活）
 */

import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { CloudTasksClient } from "@google-cloud/tasks";

import { db, FieldValue, Timestamp as FirestoreTimestamp } from "../helpers/firebase";
import { LOCATION, PROJECT_ID } from "../config/constants";

const GOAL_REMINDER_QUEUE = "task-reminders";

/**
 * 目標リマインダー用時刻計算（期限から逆算）
 */
function calculateGoalReminderTime(
    deadline: Date,
    reminder: { unit: string; value: number }
): Date {
    const ms = deadline.getTime();
    if (reminder.unit === "minutes") {
        return new Date(ms - reminder.value * 60 * 1000);
    } else if (reminder.unit === "hours") {
        return new Date(ms - reminder.value * 60 * 60 * 1000);
    } else if (reminder.unit === "days") {
        return new Date(ms - reminder.value * 24 * 60 * 60 * 1000);
    }
    return new Date(ms);
}

function getGoalReminderLabel(reminder: { unit: string; value: number }): string {
    if (reminder.unit === "minutes") {
        return `${reminder.value}分`;
    }
    if (reminder.unit === "hours") {
        return `${reminder.value}時間`;
    }
    return `${reminder.value}日`;
}

/**
 * 目標作成時にリマインダーをスケジュール
 */
export const scheduleGoalRemindersOnCreate = onDocumentCreated(
    { document: "goals/{goalId}", region: LOCATION },
    async (event) => {
        const goalId = event.params.goalId;
        const data = event.data?.data();

        if (!data) return;

        // 完了済みは無視
        if (data.completedAt) return;

        const deadline = data.deadline && typeof data.deadline.toDate === "function"
            ? data.deadline.toDate()
            : null;
        if (!deadline) {
            console.log(`[GoalReminder] Goal ${goalId} has no deadline`);
            return;
        }

        const reminders = data.reminders as Array<{ unit: string; value: number }> | undefined;
        if (!reminders || reminders.length === 0) {
            console.log(`[GoalReminder] Goal ${goalId} has no reminders`);
            return;
        }

        const userId = data.userId as string;
        const goalTitle = (data.title as string) || "目標";

        console.log(`[GoalReminder] Scheduling reminders for new goal ${goalId}`);

        const tasksClient = new CloudTasksClient();
        const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
        const location = LOCATION;

        const queuePath = tasksClient.queuePath(project, location, GOAL_REMINDER_QUEUE);
        const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeGoalReminder`;
        const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

        const now = new Date();

        for (const reminder of reminders) {
            const reminderTime = calculateGoalReminderTime(deadline, reminder);

            if (reminderTime <= now) {
                console.log(`[GoalReminder] Skipping past reminder: ${reminderTime.toISOString()}`);
                continue;
            }

            const reminderKey = `${reminder.unit}_${reminder.value}`;
            const timeLabel = getGoalReminderLabel(reminder);

            const payload = {
                goalId,
                userId,
                goalTitle,
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
                    goalId,
                    reminderKey,
                    type: "goal_reminder",
                    clientType: "pre_reminder",
                    cloudTaskName: task.name,
                    scheduledFor: FirestoreTimestamp.fromDate(reminderTime),
                    createdAt: FieldValue.serverTimestamp(),
                });

                console.log(`[GoalReminder] Scheduled: ${goalId} - ${reminderKey}`);
            } catch (error) {
                console.error(`[GoalReminder] Failed to schedule: ${reminderKey}`, error);
            }
        }

        // 期限時刻の通知
        if (deadline > now) {
            const payload = {
                goalId,
                userId,
                goalTitle,
                timeLabel: "期限",
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
                        scheduleTime: { seconds: Math.floor(deadline.getTime() / 1000) },
                    },
                });

                await db.collection("scheduledReminders").add({
                    goalId,
                    reminderKey: "on_time",
                    type: "goal_reminder",
                    clientType: "on_time",
                    cloudTaskName: task.name,
                    scheduledFor: FirestoreTimestamp.fromDate(deadline),
                    createdAt: FieldValue.serverTimestamp(),
                });

                console.log(`[GoalReminder] Scheduled on-time: ${goalId}`);
            } catch (error) {
                console.error(`[GoalReminder] Failed to schedule on-time`, error);
            }
        }
    }
);

/**
 * 目標更新時にリマインダーを再スケジュール
 */
export const scheduleGoalReminders = onDocumentUpdated(
    { document: "goals/{goalId}", region: LOCATION },
    async (event) => {
        const goalId = event.params.goalId;
        const beforeData = event.data?.before.data();
        const afterData = event.data?.after.data();

        if (!afterData) return;

        // 完了した目標は無視
        if (afterData.completedAt) {
            console.log(`[GoalReminder] Goal ${goalId} is completed, skipping`);
            return;
        }

        const deadline = afterData.deadline && typeof afterData.deadline.toDate === "function"
            ? afterData.deadline.toDate()
            : null;
        if (!deadline) {
            console.log(`[GoalReminder] Goal ${goalId} has no deadline`);
            return;
        }

        // 期限またはリマインダーが変更されていない場合はスキップ
        const beforeReminders = JSON.stringify(beforeData?.reminders || []);
        const afterReminders = JSON.stringify(afterData.reminders || []);
        if (beforeReminders === afterReminders && beforeData?.deadline?.isEqual(afterData.deadline)) {
            console.log(`[GoalReminder] Goal ${goalId} schedule unchanged`);
            return;
        }

        const userId = afterData.userId as string;
        const goalTitle = (afterData.title as string) || "目標";

        console.log(`[GoalReminder] Rescheduling reminders for goal ${goalId}`);

        const tasksClient = new CloudTasksClient();
        const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
        const location = LOCATION;

        // 既存のリマインダータスクをキャンセル
        const existingReminders = await db.collection("scheduledReminders")
            .where("goalId", "==", goalId)
            .get();

        const batch = db.batch();
        for (const doc of existingReminders.docs) {
            const taskName = doc.data().cloudTaskName;
            if (taskName) {
                try {
                    await tasksClient.deleteTask({ name: taskName });
                    console.log(`[GoalReminder] Cancelled task: ${taskName}`);
                } catch (error) {
                    console.log(`[GoalReminder] Task already gone: ${taskName}`);
                }
            }
            batch.delete(doc.ref);
        }
        await batch.commit();

        const reminders = afterData.reminders as Array<{ unit: string; value: number }> | undefined;
        if (!reminders || reminders.length === 0) {
            console.log(`[GoalReminder] Goal ${goalId} has no reminders after update`);
            return;
        }


        const queuePath = tasksClient.queuePath(project, location, GOAL_REMINDER_QUEUE);
        const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeGoalReminder`;
        const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

        const now = new Date();

        for (const reminder of reminders) {
            const reminderTime = calculateGoalReminderTime(deadline, reminder);

            if (reminderTime <= now) {
                console.log(`[GoalReminder] Skipping past reminder: ${reminderTime.toISOString()}`);
                continue;
            }

            const reminderKey = `${reminder.unit}_${reminder.value}`;
            const timeLabel = getGoalReminderLabel(reminder);

            const payload = {
                goalId,
                userId,
                goalTitle,
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
                    goalId,
                    reminderKey,
                    type: "goal_reminder",
                    clientType: "pre_reminder",
                    cloudTaskName: task.name,
                    scheduledFor: FirestoreTimestamp.fromDate(reminderTime),
                    createdAt: FieldValue.serverTimestamp(),
                });

                console.log(`[GoalReminder] Scheduled: ${goalId} - ${reminderKey}`);
            } catch (error) {
                console.error(`[GoalReminder] Failed to schedule: ${reminderKey}`, error);
            }
        }

        if (deadline > now) {
            const payload = {
                goalId,
                userId,
                goalTitle,
                timeLabel: "期限",
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
                        scheduleTime: { seconds: Math.floor(deadline.getTime() / 1000) },
                    },
                });

                await db.collection("scheduledReminders").add({
                    goalId,
                    reminderKey: "on_time",
                    type: "goal_reminder",
                    clientType: "on_time",
                    cloudTaskName: task.name,
                    scheduledFor: FirestoreTimestamp.fromDate(deadline),
                    createdAt: FieldValue.serverTimestamp(),
                });

                console.log(`[GoalReminder] Scheduled on-time: ${goalId}`);
            } catch (error) {
                console.error(`[GoalReminder] Failed to schedule on-time`, error);
            }
        }
    }
);



