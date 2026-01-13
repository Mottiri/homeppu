/**
 * 徳システム関連のヘルパー関数
 * Phase 5: index.ts から分離
 */

import { db, FieldValue } from "./firebase";

// ===============================================
// 徳システム設定
// ===============================================
export const VIRTUE_CONFIG = {
    initial: 100,           // 初期徳ポイント
    maxDaily: 50,           // 1日の最大獲得量
    banThreshold: 0,        // BAN閾値
    lossPerNegative: 15,    // ネガティブ発言1回あたりの減少
    lossPerReport: 20,      // 通報1回あたりの減少
    gainPerPraise: 5,       // 称賛1回あたりの増加
    warningThreshold: 30,   // 警告表示閾値
};

// ===============================================
// NGワード設定 (静的フィルタ)
// ===============================================
export const NG_WORDS = ["殺す", "殺し", "死ね", "死にたい", "消えたい", "暴力", "レイプ", "自殺"];

/**
 * 徳ポイントを減少させる（ネガティブ発言検出時）
 */
export async function decreaseVirtue(
    userId: string,
    reason: string,
    amount: number = VIRTUE_CONFIG.lossPerNegative
): Promise<{ newVirtue: number; isBanned: boolean }> {
    const userRef = db.collection("users").doc(userId);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
        throw new Error("User not found");
    }

    const userData = userDoc.data()!;
    const currentVirtue = userData.virtue || VIRTUE_CONFIG.initial;
    const newVirtue = Math.max(0, currentVirtue - amount);
    const isBanned = newVirtue <= VIRTUE_CONFIG.banThreshold;

    // 徳ポイントを更新
    await userRef.update({
        virtue: newVirtue,
        isBanned: isBanned,
        updatedAt: FieldValue.serverTimestamp(),
    });

    // 徳ポイント変動履歴を記録
    await db.collection("virtueHistory").add({
        userId: userId,
        change: -amount,
        reason: reason,
        newVirtue: newVirtue,
        createdAt: FieldValue.serverTimestamp(),
    });

    console.log(`Virtue decreased for ${userId}: ${currentVirtue} -> ${newVirtue}, banned: ${isBanned} `);

    return { newVirtue, isBanned };
}
