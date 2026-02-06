/**
 * コメント・リアクション関連のCallable関数
 * Phase 5: index.ts から分離
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { GoogleGenerativeAI } from "@google/generative-ai";

import { db, FieldValue, Timestamp } from "../helpers/firebase";
import { requireAuth } from "../helpers/auth";
import { geminiApiKey } from "../config/secrets";
import { AI_MODELS, LOCATION } from "../config/constants";
import {
    AUTH_ERRORS,
    PERMISSION_ERRORS,
    RESOURCE_ERRORS,
    VALIDATION_ERRORS,
    LABELS,
    MODERATION_MESSAGES,
} from "../config/messages";
import { VIRTUE_CONFIG } from "../helpers/virtue";
import { getTextModerationPrompt } from "../ai/prompts/moderation";
import { ModerationResult } from "../types";

const EPIC_REACTIONS = new Set(["rainbow", "hundred"]);

/**
 * テキストのモデレーション判定 (Gemini)
 */
async function moderateText(
    text: string,
    postContent: string = ""
): Promise<ModerationResult> {
    // 短すぎる場合はスキップ
    if (!text || text.length < 2) {
        return { isNegative: false, category: "none", confidence: 0, reason: "", suggestion: "" };
    }

    const apiKey = geminiApiKey.value();
    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: AI_MODELS.GEMINI_DEFAULT });

    const prompt = getTextModerationPrompt(text, postContent);

    try {
        const result = await model.generateContent(prompt);
        const responseText = result.response.text();
        // JSONブロックを取り出す
        const jsonMatch = responseText.match(/\{[\s\S]*\}/);
        if (!jsonMatch) {
            console.warn("Moderation JSON parse failed", responseText);
            return { isNegative: false, category: "none", confidence: 0, reason: "", suggestion: "" };
        }
        const data = JSON.parse(jsonMatch[0]) as ModerationResult;
        return data;
    } catch (error) {
        console.error("Moderation AI Error:", error);
        // エラー時は安全側に倒してスルー（または厳しくするか要検討）
        return { isNegative: false, category: "none", confidence: 0, reason: "", suggestion: "" };
    }
}

/**
 * 徳ポイントの更新（減少処理）
 */
async function penalizeUser(userId: string, penalty: number, reason: string) {
    const userRef = db.collection("users").doc(userId);

    await db.runTransaction(async (transaction) => {
        const doc = await transaction.get(userRef);
        if (!doc.exists) return;

        const currentVirtue = doc.data()?.virtue || 100;
        const newVirtue = Math.max(0, currentVirtue - penalty);

        transaction.update(userRef, { virtue: newVirtue });

        // 履歴追加
        const historyRef = db.collection("virtueHistory").doc();
        transaction.set(historyRef, {
            userId,
            change: -penalty,
            reason,
            newVirtue,
            createdAt: FieldValue.serverTimestamp(),
        });
    });
}

/**
 * モデレーション付きコメント作成
 */
export const createCommentWithModeration = onCall(
    {
        region: LOCATION,
        enforceAppCheck: true,
        secrets: [geminiApiKey],
    },
    async (request) => {
        // 認証チェック
        const { postId, content, userDisplayName, userAvatarIndex } = request.data;
        const userId = requireAuth(request, AUTH_ERRORS.USER_MUST_BE_LOGGED_IN);

        if (!postId || !content) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.MISSING_POST_ID_CONTENT);
        }

        // ユーザーがBANされているかチェック
        const userDoc = await db.collection("users").doc(userId).get();
        if (userDoc.exists && userDoc.data()?.isBanned) {
            throw new HttpsError("permission-denied", AUTH_ERRORS.BANNED);
        }

        // 投稿のコンテキストを取得
        let postContentText = "";
        try {
            const postDoc = await db.collection("posts").doc(postId).get();
            if (postDoc.exists) {
                postContentText = postDoc.data()?.content || "";
            }
        } catch (error) {
            console.warn(`Failed to fetch post context for moderation: ${postId}`, error);
        }

        // 1. モデレーション実行（コンテキスト付き）
        const moderation = await moderateText(content, postContentText);
        if (moderation.isNegative && moderation.confidence > 0.7) {
            // 徳ポイント減少
            await penalizeUser(
                userId,
                VIRTUE_CONFIG.lossPerNegative,
                `不適切な発言: ${moderation.category}`
            );

            throw new HttpsError(
                "invalid-argument",
                moderation.reason || MODERATION_MESSAGES.INAPPROPRIATE_CONTENT_DETECTED,
                { suggestion: moderation.suggestion }
            );
        }

        // 2. コメント保存
        const commentRef = db.collection("comments").doc();
        await commentRef.set({
            postId,
            userId,
            userDisplayName: userDisplayName || "Unknown",
            userAvatarIndex: userAvatarIndex || 0,
            content,
            isAI: false,
            createdAt: FieldValue.serverTimestamp(),
            isVisibleNow: true, // 即時表示
        });

        // 3. 投稿のコメント数を更新
        await db.collection("posts").doc(postId).update({
            commentCount: FieldValue.increment(1),
        });

        return { commentId: commentRef.id };
    }
);

/**
 * ユーザーリアクション追加関数
 * 1人あたり1投稿に対して最大5回までの制限あり
 */
export const addUserReaction = onCall(
    { region: LOCATION, enforceAppCheck: true },
    async (request) => {
        const { postId, reactionType } = request.data;
        const userId = requireAuth(request);

        if (!postId || !reactionType) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.POST_ID_REACTION_REQUIRED);
        }

        const MAX_REACTIONS_PER_USER = 5;

        // 既存リアクション数をカウント
        const existingReactions = await db.collection("reactions")
            .where("postId", "==", postId)
            .where("userId", "==", userId)
            .get();

        if (existingReactions.size >= MAX_REACTIONS_PER_USER) {
            throw new HttpsError(
                "resource-exhausted",
                `1つの投稿に対するリアクションは${MAX_REACTIONS_PER_USER}回までです`
            );
        }

        // ユーザー情報を取得
        const reactionRef = db.collection("reactions").doc();
        const postRef = db.collection("posts").doc(postId);
        const userRef = db.collection("users").doc(userId);
        let displayName = LABELS.USER;

        await db.runTransaction(async (transaction) => {
            const userSnap = await transaction.get(userRef);
            if (!userSnap.exists) {
                throw new HttpsError("not-found", RESOURCE_ERRORS.USER_NOT_FOUND);
            }
            const userData = userSnap.data() || {};

            // BANユーザーチェック
            if (userData.isBanned === true || (userData.banStatus && userData.banStatus !== "none")) {
                throw new HttpsError("permission-denied", AUTH_ERRORS.BANNED);
            }

            displayName = userData.displayName || LABELS.USER;

            const isEpicReaction = EPIC_REACTIONS.has(reactionType);
            const isSubscriber = userData.isSubscriber === true;

            if (isEpicReaction && !isSubscriber) {
                const unlocks = userData.rewardedReactionUnlocks || {};
                const unlock = unlocks[reactionType];
                const remaining = Number(unlock?.remaining ?? 0);
                const rawExpiresAt = unlock?.expiresAt;
                const parsedExpiresAt =
                    rawExpiresAt?.toDate?.() ??
                    (rawExpiresAt ? new Date(rawExpiresAt) : null);

                if (
                    !parsedExpiresAt ||
                    Number.isNaN(parsedExpiresAt.getTime()) ||
                    remaining <= 0 ||
                    parsedExpiresAt.getTime() <= Date.now()
                ) {
                    throw new HttpsError(
                        "permission-denied",
                        PERMISSION_ERRORS.EPIC_REACTION_REQUIRES_SUBSCRIPTION
                    );
                }

                const nextRemaining = remaining - 1;
                if (nextRemaining <= 0) {
                    transaction.update(userRef, {
                        [`rewardedReactionUnlocks.${reactionType}`]: FieldValue.delete(),
                    });
                } else {
                    transaction.update(userRef, {
                        [`rewardedReactionUnlocks.${reactionType}.remaining`]: nextRemaining,
                        [`rewardedReactionUnlocks.${reactionType}.expiresAt`]:
                            Timestamp.fromDate(parsedExpiresAt),
                    });
                }
            }

            // 1. リアクション保存
            transaction.set(reactionRef, {
                postId: postId,
                userId: userId,
                userDisplayName: displayName,
                reactionType: reactionType,
                createdAt: FieldValue.serverTimestamp(),
            });

            // 2. 投稿のリアクションカウント更新
            transaction.update(postRef, {
                [`reactions.${reactionType}`]: FieldValue.increment(1),
            });
        });

        console.log(`User reaction added: ${displayName} -> ${reactionType} on ${postId}`);
        return {
            success: true,
            remainingReactions: MAX_REACTIONS_PER_USER - existingReactions.size - 1,
        };
    }
);

export const removeUserReaction = onCall(
    { region: LOCATION, enforceAppCheck: true },
    async (request) => {
        const { postId, reactionType } = request.data;
        const userId = requireAuth(request);

        if (!postId || !reactionType) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.POST_ID_REACTION_REQUIRED);
        }

        const reactionSnapshot = await db.collection("reactions")
            .where("postId", "==", postId)
            .where("userId", "==", userId)
            .where("reactionType", "==", reactionType)
            .limit(1)
            .get();

        if (reactionSnapshot.empty) {
            return { success: true, removed: false };
        }

        const reactionRef = reactionSnapshot.docs[0].ref;
        const postRef = db.collection("posts").doc(postId);

        await db.runTransaction(async (transaction) => {
            const postSnap = await transaction.get(postRef);
            const reactions = postSnap.data()?.reactions ?? {};
            const currentCount = Number(reactions[reactionType] ?? 0);

            if (currentCount > 0) {
                transaction.update(postRef, {
                    [`reactions.${reactionType}`]: FieldValue.increment(-1),
                });
            }

            transaction.delete(reactionRef);
        });

        return { success: true, removed: true };
    }
);
