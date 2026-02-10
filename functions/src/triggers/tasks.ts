/**
 * タスク関連のトリガー関数
 * Phase 6: index.ts から分離
 */

import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { scheduleHttpTask } from "../helpers/cloud-tasks";

import { db, FieldValue, Timestamp as FirestoreTimestamp } from "../helpers/firebase";
import { getVirtuePolicy, grantVirtue, resolveTaskStreakRewardPoints, VIRTUE_ROUTE_KEYS } from "../helpers/virtue-policy";
import { LOCATION, PROJECT_ID } from "../config/constants";

const TASK_TRIGGER_REVISION = "tasks-trigger-2026-02-08-b";

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
            const userId = after.userId as string | undefined;
            if (!userId) return;
            const taskId = event.params.taskId;
            const taskRef = db.collection("tasks").doc(taskId);
            const recurrenceGroupId = typeof after.recurrenceGroupId === "string"
                ? after.recurrenceGroupId
                : null;
            const scheduledAt = after.scheduledAt && typeof after.scheduledAt.toDate === "function"
                ? after.scheduledAt.toDate()
                : null;

            console.log(
                `[onTaskUpdated:${TASK_TRIGGER_REVISION}] completion detected taskId=${taskId} userId=${userId} recurrenceGroupId=${recurrenceGroupId ?? "none"}`
            );

            const virtuePolicy = await getVirtuePolicy();
            const userRef = db.collection("users").doc(userId);

            const rewardDecision = await db.runTransaction(async (transaction) => {
                const userDoc = await transaction.get(userRef);
                if (!userDoc.exists) {
                    return { shouldGrant: false, streakReward: 0, newStreak: 0 };
                }

                let newStreak = 1;

                if (recurrenceGroupId && scheduledAt) {
                    const streakWindowQuery = db
                        .collection("tasks")
                        .where("userId", "==", userId)
                        .where("recurrenceGroupId", "==", recurrenceGroupId)
                        .where("scheduledAt", "<=", FirestoreTimestamp.fromDate(scheduledAt))
                        .orderBy("scheduledAt", "desc")
                        .limit(400);

                    const streakWindowSnap = await transaction.get(streakWindowQuery);
                    if (!streakWindowSnap.empty) {
                        let contiguousCompleted = 0;
                        for (const doc of streakWindowSnap.docs) {
                            const data = doc.data();
                            if (data.isCompleted !== true) {
                                break;
                            }
                            contiguousCompleted += 1;
                        }
                        newStreak = Math.max(1, contiguousCompleted);
                    }
                }

                transaction.update(taskRef, {
                    streak: newStreak,
                    lastCompletedAt: FieldValue.serverTimestamp(),
                    updatedAt: FieldValue.serverTimestamp(),
                });

                transaction.update(userRef, {
                    currentStreak: newStreak,
                    lastTaskCompletedAt: FieldValue.serverTimestamp(),
                });

                const streakReward = resolveTaskStreakRewardPoints(virtuePolicy, newStreak);
                console.log(
                    `[onTaskUpdated:${TASK_TRIGGER_REVISION}] streak=${newStreak} reward=${streakReward}`
                );
                if (streakReward <= 0) {
                    return { shouldGrant: false, streakReward: 0, newStreak };
                }

                return { shouldGrant: true, streakReward, newStreak };
            });

            if (rewardDecision.shouldGrant && rewardDecision.streakReward > 0) {
                console.log(
                    `[onTaskUpdated:${TASK_TRIGGER_REVISION}] grant streak reward taskId=${taskId} streak=${rewardDecision.newStreak} points=${rewardDecision.streakReward}`
                );
                await grantVirtue({
                    userId,
                    routeKey: VIRTUE_ROUTE_KEYS.taskStreak,
                    points: rewardDecision.streakReward,
                    reason: `タスクストリーク達成 (${rewardDecision.newStreak}日)`,
                    source: "task_streak",
                    targetId: taskId,
                });
            } else {
                console.log(
                    `[onTaskUpdated:${TASK_TRIGGER_REVISION}] no streak reward taskId=${taskId} streak=${rewardDecision.newStreak}`
                );
            }
        }

        // 2. 完了取り消し (true -> false)
        if (before.isCompleted && !after.isCompleted) {
            // 合意仕様: タスク完了取消による徳ポイント減算は行わない
            return;
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

        const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
        const location = LOCATION;

        const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeTaskReminder`;

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
                    const taskName = await scheduleHttpTask({
                        queue: TASK_REMINDER_QUEUE,
                        url: targetUrl,
                        payload,
                        scheduleTime: reminderTime,
                        projectId: project,
                        location,
                    });

                    if (!taskName) {
                        console.error(`[Reminder] Failed to schedule: ${reminderKey}`);
                        continue;
                    }

                    await db.collection("scheduledReminders").add({
                        taskId,
                        reminderKey,
                        cloudTaskName: taskName,
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
                const taskName = await scheduleHttpTask({
                    queue: TASK_REMINDER_QUEUE,
                    url: targetUrl,
                    payload,
                    scheduleTime: scheduledAt,
                    projectId: project,
                    location,
                });

                if (!taskName) {
                    console.error(`[Reminder] Failed to schedule on-time: ${taskId}`);
                } else {
                    await db.collection("scheduledReminders").add({
                        taskId,
                        reminderKey: "on_time",
                        cloudTaskName: taskName,
                        scheduledFor: FirestoreTimestamp.fromDate(scheduledAt),
                        createdAt: FieldValue.serverTimestamp(),
                    });

                    console.log(`[Reminder] Scheduled on-time: ${taskId} at ${scheduledAt.toISOString()}`);
                }
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

        const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
        const location = LOCATION;

        const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeTaskReminder`;

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
                    const taskName = await scheduleHttpTask({
                        queue: TASK_REMINDER_QUEUE,
                        url: targetUrl,
                        payload,
                        scheduleTime: reminderTime,
                        projectId: project,
                        location,
                    });

                    if (!taskName) {
                        console.error(`[Reminder] Failed to schedule: ${reminderKey}`);
                        continue;
                    }

                    await db.collection("scheduledReminders").add({
                        taskId,
                        reminderKey,
                        cloudTaskName: taskName,
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
                const taskName = await scheduleHttpTask({
                    queue: TASK_REMINDER_QUEUE,
                    url: targetUrl,
                    payload,
                    scheduleTime: scheduledAt,
                    projectId: project,
                    location,
                });

                if (!taskName) {
                    console.error(`[Reminder] Failed to schedule on-time: ${taskId}`);
                } else {
                    await db.collection("scheduledReminders").add({
                        taskId,
                        reminderKey: "on_time",
                        cloudTaskName: taskName,
                        scheduledFor: FirestoreTimestamp.fromDate(scheduledAt),
                        createdAt: FieldValue.serverTimestamp(),
                    });

                    console.log(`[Reminder] Scheduled on-time: ${taskId}`);
                }
            } catch (error) {
                console.error(`[Reminder] Failed to schedule on-time`, error);
            }
        }
    }
);
