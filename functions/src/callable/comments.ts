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
    COMMENT_THANKS_MESSAGES,
    PERMISSION_ERRORS,
    RESOURCE_ERRORS,
    STAMP_SHEET_MESSAGES,
    VALIDATION_ERRORS,
    LABELS,
    MODERATION_MESSAGES,
} from "../config/messages";
import { getTextModerationPrompt } from "../ai/prompts/moderation";
import { ModerationResult } from "../types";

const EPIC_REACTIONS = new Set(["rainbow", "hundred"]);
const EPIC_STAMP_SHEET_REACTIONS = new Set(["rainbow", "hundred", "confetti"]);
const SETTINGS_COLLECTION = "settings";
const VIRTUE_SHOP_SETTINGS_DOC = "virtueShop";
const STAMP_SHEET_CATALOG_DOC = "stampSheetCatalog";

function normalizeRarity(raw: unknown): "common" | "rare" | "epic" {
    if (raw === "rare") return "rare";
    if (raw === "epic") return "epic";
    return "common";
}

function parseStringArray(value: unknown): string[] {
    if (!Array.isArray(value)) return [];
    return value.filter((item): item is string => typeof item === "string");
}

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
            // コメントは拒否のみ（徳ポイントは減点しない）
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
                VALIDATION_ERRORS.reactionLimitExceeded(MAX_REACTIONS_PER_USER)
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

/**
 * 投稿主限定: コメントへのお礼付与
 * - 同一コメントへは1回のみ
 * - 付与されたコメント作成者に対してではなく、付与した投稿主の credits を +1
 */
export const likeCommentAsPostOwner = onCall(
    { region: LOCATION, enforceAppCheck: true },
    async (request) => {
        const userId = requireAuth(request, AUTH_ERRORS.USER_MUST_BE_LOGGED_IN);
        const commentId = request.data?.commentId as string | undefined;

        if (!commentId || typeof commentId !== "string") {
            throw new HttpsError("invalid-argument", COMMENT_THANKS_MESSAGES.COMMENT_ID_REQUIRED);
        }

        const commentRef = db.collection("comments").doc(commentId);

        const result = await db.runTransaction(async (transaction) => {
            const commentSnap = await transaction.get(commentRef);
            if (!commentSnap.exists) {
                throw new HttpsError("not-found", COMMENT_THANKS_MESSAGES.COMMENT_NOT_FOUND);
            }

            const commentData = commentSnap.data() || {};
            const postId = commentData.postId as string | undefined;
            const commentOwnerId = commentData.userId as string | undefined;
            if (!postId) {
                throw new HttpsError("failed-precondition", COMMENT_THANKS_MESSAGES.POST_NOT_FOUND);
            }

            const postRef = db.collection("posts").doc(postId);
            const postSnap = await transaction.get(postRef);
            if (!postSnap.exists) {
                throw new HttpsError("not-found", COMMENT_THANKS_MESSAGES.POST_NOT_FOUND);
            }

            const postOwnerId = postSnap.data()?.userId as string | undefined;
            if (postOwnerId !== userId) {
                throw new HttpsError("permission-denied", COMMENT_THANKS_MESSAGES.POST_OWNER_ONLY);
            }

            if (commentOwnerId === userId) {
                throw new HttpsError("permission-denied", COMMENT_THANKS_MESSAGES.SELF_COMMENT_NOT_ALLOWED);
            }
            if (!commentOwnerId) {
                throw new HttpsError("failed-precondition", RESOURCE_ERRORS.USER_NOT_FOUND);
            }

            const alreadyThanked = commentData.thanksLikedByPostOwner === true;
            const commentOwnerRef = db.collection("users").doc(commentOwnerId);
            const commentOwnerSnap = await transaction.get(commentOwnerRef);
            if (!commentOwnerSnap.exists) {
                throw new HttpsError("not-found", RESOURCE_ERRORS.USER_NOT_FOUND);
            }

            const currentCreditsRaw = Number(commentOwnerSnap.data()?.thanksStampCredits ?? 0);
            const currentCredits = Number.isFinite(currentCreditsRaw) ? Math.max(0, Math.trunc(currentCreditsRaw)) : 0;

            if (alreadyThanked) {
                return {
                    alreadyThanked: true,
                    credits: currentCredits,
                };
            }

            const nextCredits = currentCredits + 1;
            const now = FieldValue.serverTimestamp();

            transaction.update(commentRef, {
                thanksLikedByPostOwner: true,
                thanksLikedAt: now,
                thanksLikedBy: userId,
                updatedAt: now,
            });

            transaction.update(commentOwnerRef, {
                thanksStampCredits: nextCredits,
                updatedAt: now,
            });

            return {
                alreadyThanked: false,
                credits: nextCredits,
            };
        });

        return {
            success: true,
            alreadyThanked: result.alreadyThanked,
            credits: result.credits,
        };
    }
);

/**
 * スタンプシートの表示対象シートを更新
 */
export const setActiveStampSheet = onCall(
    { region: LOCATION, enforceAppCheck: true },
    async (request) => {
        const userId = requireAuth(request, AUTH_ERRORS.USER_MUST_BE_LOGGED_IN);
        const sheetId = request.data?.sheetId as string | undefined;
        if (!sheetId || typeof sheetId !== "string") {
            throw new HttpsError("invalid-argument", STAMP_SHEET_MESSAGES.SHEET_ID_REQUIRED);
        }

        const userRef = db.collection("users").doc(userId);
        const catalogRef = db.collection(SETTINGS_COLLECTION).doc(STAMP_SHEET_CATALOG_DOC);

        await db.runTransaction(async (transaction) => {
            const [userSnap, catalogSnap] = await Promise.all([
                transaction.get(userRef),
                transaction.get(catalogRef),
            ]);
            if (!userSnap.exists) {
                throw new HttpsError("not-found", STAMP_SHEET_MESSAGES.USER_NOT_FOUND);
            }

            const userData = userSnap.data() || {};
            let sheetRarity: "common" | "rare" | "epic" = "common";

            if (catalogSnap.exists) {
                const sheetsRaw = catalogSnap.data()?.sheets;
                const sheets = Array.isArray(sheetsRaw) ? sheetsRaw : [];
                const sheet = sheets.find((item) => item?.id === sheetId && item?.isActive !== false);
                if (!sheet) {
                    throw new HttpsError("not-found", STAMP_SHEET_MESSAGES.SHEET_NOT_FOUND);
                }
                sheetRarity = normalizeRarity(sheet?.rarity);
            } else if (sheetId !== "default") {
                throw new HttpsError("not-found", STAMP_SHEET_MESSAGES.SHEET_NOT_FOUND);
            }

            const unlockedSheets = parseStringArray(userData.unlockedStampSheets);
            const unlockedKey = `sheet_${sheetId}`;
            const isSubscriber = userData.isSubscriber === true;
            const isUnlocked = sheetRarity === "common" ||
                unlockedSheets.includes(unlockedKey) ||
                (sheetRarity === "epic" && isSubscriber);
            if (!isUnlocked) {
                throw new HttpsError("permission-denied", STAMP_SHEET_MESSAGES.SHEET_LOCKED);
            }

            transaction.update(userRef, {
                activeStampSheetId: sheetId,
                updatedAt: FieldValue.serverTimestamp(),
            });
        });

        return { success: true, sheetId };
    }
);

/**
 * スタンプシート枠にスタンプを適用
 * - 空枠に初回押印する場合のみ credits を1消費
 * - 既存押印の上書きは消費なし
 */
export const applyStampToSheetSlot = onCall(
    { region: LOCATION, enforceAppCheck: true },
    async (request) => {
        const userId = requireAuth(request, AUTH_ERRORS.USER_MUST_BE_LOGGED_IN);
        const sheetId = request.data?.sheetId as string | undefined;
        const slotId = request.data?.slotId as string | undefined;
        const stampId = request.data?.stampId as string | undefined;

        if (!sheetId || typeof sheetId !== "string") {
            throw new HttpsError("invalid-argument", STAMP_SHEET_MESSAGES.SHEET_ID_REQUIRED);
        }
        if (!slotId || typeof slotId !== "string") {
            throw new HttpsError("invalid-argument", STAMP_SHEET_MESSAGES.SLOT_ID_REQUIRED);
        }
        if (!stampId || typeof stampId !== "string") {
            throw new HttpsError("invalid-argument", STAMP_SHEET_MESSAGES.STAMP_ID_REQUIRED);
        }

        const userRef = db.collection("users").doc(userId);
        const placementRef = userRef.collection("stampSheet").doc(`${sheetId}_${slotId}`);
        const settingsVirtueShopRef = db.collection(SETTINGS_COLLECTION).doc(VIRTUE_SHOP_SETTINGS_DOC);
        const settingsCatalogRef = db.collection(SETTINGS_COLLECTION).doc(STAMP_SHEET_CATALOG_DOC);

        const result = await db.runTransaction(async (transaction) => {
            const [userSnap, placementSnap, virtueShopSnap, catalogSnap] = await Promise.all([
                transaction.get(userRef),
                transaction.get(placementRef),
                transaction.get(settingsVirtueShopRef),
                transaction.get(settingsCatalogRef),
            ]);

            if (!userSnap.exists) {
                throw new HttpsError("not-found", STAMP_SHEET_MESSAGES.USER_NOT_FOUND);
            }

            const userData = userSnap.data() || {};
            const unlockedReactionStamps = parseStringArray(userData.unlockedReactionStamps);
            const unlockedStampSheets = parseStringArray(userData.unlockedStampSheets);
            const isSubscriber = userData.isSubscriber === true;

            let sheetRarity: "common" | "rare" | "epic" = "common";
            if (catalogSnap.exists) {
                const sheetsRaw = catalogSnap.data()?.sheets;
                const sheets = Array.isArray(sheetsRaw) ? sheetsRaw : [];
                const sheet = sheets.find((item) => item?.id === sheetId && item?.isActive !== false);
                if (!sheet) {
                    throw new HttpsError("not-found", STAMP_SHEET_MESSAGES.SHEET_NOT_FOUND);
                }
                sheetRarity = normalizeRarity(sheet?.rarity);
            } else if (sheetId !== "default") {
                throw new HttpsError("not-found", STAMP_SHEET_MESSAGES.SHEET_NOT_FOUND);
            }

            const sheetUnlocked = sheetRarity === "common" ||
                unlockedStampSheets.includes(`sheet_${sheetId}`) ||
                (sheetRarity === "epic" && isSubscriber);
            if (!sheetUnlocked) {
                throw new HttpsError("permission-denied", STAMP_SHEET_MESSAGES.SHEET_LOCKED);
            }

            const reactionCostsByIdRaw = virtueShopSnap.data()?.reactionCostsById;
            const reactionCostsById = (
                reactionCostsByIdRaw && typeof reactionCostsByIdRaw === "object"
                    ? reactionCostsByIdRaw
                    : {}
            ) as Record<string, unknown>;
            const isRareStamp = Object.prototype.hasOwnProperty.call(reactionCostsById, stampId);
            const isEpicStamp = EPIC_STAMP_SHEET_REACTIONS.has(stampId);
            const isStampUnlocked = isEpicStamp
                ? isSubscriber
                : (isRareStamp ? unlockedReactionStamps.includes(`reaction_${stampId}`) : true);
            if (!isStampUnlocked) {
                throw new HttpsError("permission-denied", STAMP_SHEET_MESSAGES.STAMP_LOCKED);
            }

            const existingStampId = placementSnap.data()?.stampId as string | undefined;
            const shouldConsumeCredit = !(existingStampId && existingStampId.length > 0);

            const creditsRaw = Number(userData.thanksStampCredits ?? 0);
            const currentCredits = Number.isFinite(creditsRaw) ? Math.max(0, Math.trunc(creditsRaw)) : 0;
            const nextCredits = shouldConsumeCredit ? currentCredits - 1 : currentCredits;

            if (shouldConsumeCredit && currentCredits <= 0) {
                throw new HttpsError("failed-precondition", STAMP_SHEET_MESSAGES.CREDIT_NOT_ENOUGH);
            }

            const now = FieldValue.serverTimestamp();
            transaction.set(
                placementRef,
                {
                    sheetId,
                    slotId,
                    stampId,
                    updatedAt: now,
                    createdAt: placementSnap.exists ? placementSnap.data()?.createdAt ?? now : now,
                },
                { merge: true }
            );

            if (shouldConsumeCredit) {
                transaction.update(userRef, {
                    thanksStampCredits: nextCredits,
                    updatedAt: now,
                });
            }

            return {
                consumed: shouldConsumeCredit,
                remainingCredits: nextCredits,
            };
        });

        return {
            success: true,
            consumed: result.consumed,
            remainingCredits: result.remainingCredits,
            sheetId,
            slotId,
            stampId,
        };
    }
);
