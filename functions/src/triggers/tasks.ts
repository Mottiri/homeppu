/**
 * タスク関連のトリガー関数
 * Phase 6: index.ts から分離
 */

import * as admin from "firebase-admin";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";

import { db } from "../helpers/firebase";

/**
 * タスクが更新された時の処理
 * - 完了状態になった場合: 徳ポイントとストリークの計算
 */
export const onTaskUpdated = onDocumentUpdated("tasks/{taskId}", async (event) => {
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
                virtue: admin.firestore.FieldValue.increment(virtueGain),
                currentStreak: newStreak,
                lastTaskCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // 履歴記録
            const historyRef = db.collection("virtueHistory").doc();
            transaction.set(historyRef, {
                userId: userId,
                change: virtueGain,
                reason: `タスク完了: ${after.content} ${newStreak > 1 ? `(${newStreak}連!)` : ''}`,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
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
                virtue: admin.firestore.FieldValue.increment(-2), // 最低限引く
            });

            // 履歴
            const historyRef = db.collection("virtueHistory").doc();
            transaction.set(historyRef, {
                userId: userId,
                change: -2,
                reason: `タスク完了取消: ${after.content}`,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        });
    }
});
