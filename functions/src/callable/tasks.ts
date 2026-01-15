/**
 * タスク関連のCallable Functions
 * - createTask: タスクを作成（繰り返し展開対応）
 * - getTasks: タスク一覧を取得
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db, FieldValue, Timestamp } from "../helpers/firebase";
import { LOCATION } from "../config/constants";
import { AUTH_ERRORS, VALIDATION_ERRORS } from "../config/messages";

/**
 * タスクを作成
 * - 単発タスク作成
 * - 繰り返しタスクの展開（daily, weekly, monthly, yearly）
 * - バッチ書き込み（500件ずつ）
 */
export const createTask = onCall(
  { region: LOCATION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", AUTH_ERRORS.UNAUTHENTICATED);
    }

    const userId = request.auth.uid;
    const {
      content,
      emoji,
      type,
      scheduledAt,
      priority,
      googleCalendarEventId,
      subtasks,
      recurrenceInterval,
      recurrenceUnit,
      recurrenceDaysOfWeek,
      recurrenceEndDate,
      categoryId,
    } = request.data;

    if (!content || !type) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.TASK_CONTENT_TYPE_REQUIRED);
    }

    const baseTaskData = {
      userId: userId,
      content: content,
      emoji: emoji || "📝",
      type: type, // "daily" | "goal" | "todo"
      isCompleted: false,
      streak: 0,
      lastCompletedAt: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      priority: priority || 0,
      googleCalendarEventId: googleCalendarEventId || null,
      subtasks: subtasks || [],
      // 展開後の各タスクには繰り返しルールを持たせない（独立したタスクとする）
      recurrenceInterval: null,
      recurrenceUnit: null,
      recurrenceDaysOfWeek: null,
      recurrenceEndDate: null,
      categoryId: categoryId || null,
      recurrenceGroupId: null, // 初期値
    };

    const tasksToCreate: Record<string, unknown>[] = [];
    const startDate = scheduledAt ? new Date(scheduledAt) : new Date();

    // グループID生成（最初のドキュメントIDを使う）
    const firstRef = db.collection("tasks").doc();
    const groupId = recurrenceUnit ? firstRef.id : null;

    if (!recurrenceUnit) {
      // 単発
      tasksToCreate.push({
        ...baseTaskData,
        scheduledAt: scheduledAt ? Timestamp.fromDate(startDate) : null,
      });
    } else {
      // 繰り返し展開
      const interval = recurrenceInterval || 1;
      const currentDate = new Date(startDate);
      const endDate = recurrenceEndDate
        ? new Date(recurrenceEndDate)
        : new Date(startDate);

      if (!recurrenceEndDate) {
        // デフォルト3年
        endDate.setFullYear(endDate.getFullYear() + 3);
      }

      // 無限ループ防止
      let count = 0;
      const MAX_COUNT = 1100; // 約3年分

      while (currentDate <= endDate && count < MAX_COUNT) {
        // 週次の曜日指定がある場合
        let isValidDate = true;
        if (
          recurrenceUnit === "weekly" &&
          recurrenceDaysOfWeek &&
          recurrenceDaysOfWeek.length > 0
        ) {
          // Firestore/JS Day: 0=Sun, 1=Mon...
          // App Day: 1=Mon...7=Sun.
          // Convert App(1-7) to JS(1-6, 0)
          const appDay = recurrenceDaysOfWeek; // Array of 1-7
          const jsDay = currentDate.getDay(); // 0-6
          const appDayConverted = jsDay === 0 ? 7 : jsDay;

          if (!appDay.includes(appDayConverted)) {
            isValidDate = false;
          }
        }

        if (isValidDate) {
          tasksToCreate.push({
            ...baseTaskData,
            scheduledAt: Timestamp.fromDate(new Date(currentDate)),
            recurrenceGroupId: groupId, // リンク用ID
          });
        }

        // 次の日付計算
        if (recurrenceUnit === "daily") {
          currentDate.setDate(currentDate.getDate() + interval);
        } else if (recurrenceUnit === "weekly") {
          // 曜日指定あり -> 1日ずつ進める (interval無視、またはinterval=1前提)
          // 曜日指定なし -> interval週進める
          if (recurrenceDaysOfWeek && recurrenceDaysOfWeek.length > 0) {
            currentDate.setDate(currentDate.getDate() + 1);
          } else {
            currentDate.setDate(currentDate.getDate() + 7 * interval);
          }
        } else if (recurrenceUnit === "monthly") {
          currentDate.setMonth(currentDate.getMonth() + interval);
        } else if (recurrenceUnit === "yearly") {
          currentDate.setFullYear(currentDate.getFullYear() + interval);
        } else {
          // Fallback
          currentDate.setDate(currentDate.getDate() + 1);
        }

        count++;
      }
    }

    // Batch Write (Max 500 per batch)
    const batches = [];
    let currentBatch = db.batch();
    let opCount = 0;
    let firstTaskId = "";

    let isFirst = true;
    for (const taskData of tasksToCreate) {
      let ref;
      if (isFirst) {
        ref = firstRef;
        isFirst = false;
        firstTaskId = ref.id;
      } else {
        ref = db.collection("tasks").doc();
      }

      currentBatch.set(ref, taskData);
      opCount++;

      if (opCount >= 500) {
        batches.push(currentBatch.commit());
        currentBatch = db.batch();
        opCount = 0;
      }
    }
    if (opCount > 0) {
      batches.push(currentBatch.commit());
    }

    await Promise.all(batches);

    return { success: true, taskId: firstTaskId };
  }
);

/**
 * タスク一覧を取得
 * - typeでフィルタリング可能
 * - isCompletedTodayを計算して返却
 */
export const getTasks = onCall(
  { region: LOCATION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", AUTH_ERRORS.UNAUTHENTICATED);
    }

    const userId = request.auth.uid;
    const { type } = request.data;

    let query: FirebaseFirestore.Query<FirebaseFirestore.DocumentData> = db
      .collection("tasks")
      .where("userId", "==", userId);

    if (type) {
      query = query.where("type", "==", type);
    }

    const snapshot = await query.orderBy("createdAt", "desc").get();

    // 今日の開始時刻を計算（日本時間）
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    const tasks = snapshot.docs.map((doc) => {
      const data = doc.data();
      const lastCompletedAt = data.lastCompletedAt?.toDate?.();

      // isCompletedTodayを計算（lastCompletedAtが今日かどうか）
      let isCompletedToday = false;
      if (lastCompletedAt) {
        isCompletedToday = lastCompletedAt >= todayStart;
      }

      return {
        id: doc.id,
        ...data,
        isCompletedToday,
        createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
        updatedAt: data.updatedAt?.toDate?.()?.toISOString() || null,
        lastCompletedAt: lastCompletedAt?.toISOString() || null,
        scheduledAt: data.scheduledAt?.toDate?.()?.toISOString() || null,
        priority: data.priority || 0,
        googleCalendarEventId: data.googleCalendarEventId || null,
        subtasks: data.subtasks || [],
      };
    });

    return { tasks };
  }
);
