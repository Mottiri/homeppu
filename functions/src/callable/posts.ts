/**
 * 投稿作成関連のCallable関数
 * Phase 5: index.ts から分離
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { GoogleGenerativeAI } from "@google/generative-ai";

import { db, FieldValue } from "../helpers/firebase";
import { requireAuth } from "../helpers/auth";
import { geminiApiKey } from "../config/secrets";
import { isAdmin, getAdminUids } from "../helpers/admin";
import { ModerationResult, MediaItem } from "../types";
import { moderateMedia } from "../helpers/moderation";
import { logAIUsage } from "../helpers/ai-usage";
import { NG_WORDS } from "../helpers/virtue";
import { getVirtuePolicy, grantVirtue, VIRTUE_ROUTE_KEYS } from "../helpers/virtue-policy";
import { LOCATION, AI_MODELS } from "../config/constants";
import {
    AUTH_ERRORS,
    VALIDATION_ERRORS,
    SYSTEM_ERRORS,
    NOTIFICATION_TITLES,
    NOTIFICATION_BODIES,
    LABELS,
    MODERATION_MESSAGES,
    VIRTUE_MESSAGES,
} from "../config/messages";

const POSTS_PER_MINUTE_LIMIT = 2;
const POSTS_DAILY_LIMIT = 15;
const JST_OFFSET_MS = 9 * 60 * 60 * 1000;
const POST_RATE_WINDOW_MS = 60 * 1000;

function getJstDateKey(now: Date = new Date()): string {
    const jstNow = new Date(now.getTime() + JST_OFFSET_MS);
    return jstNow.toISOString().slice(0, 10);
}

async function enforcePostRateLimits(userId: string): Promise<void> {
    const userRef = db.collection("users").doc(userId);
    await db.runTransaction(async (transaction) => {
        const snap = await transaction.get(userRef);
        if (!snap.exists) {
            throw new HttpsError("not-found", AUTH_ERRORS.UNAUTHENTICATED);
        }

        const data = snap.data() || {};
        const nowMs = Date.now();

        const rawWindowStart = Number(data.postRateWindowStartMs ?? 0);
        const rawRateCount = Number(data.postRateCount ?? 0);
        const windowStartMs = Number.isFinite(rawWindowStart) ? Math.max(0, Math.trunc(rawWindowStart)) : 0;
        const rateCount = Number.isFinite(rawRateCount) ? Math.max(0, Math.trunc(rawRateCount)) : 0;
        const withinWindow = nowMs - windowStartMs < POST_RATE_WINDOW_MS;
        const nextWindowStartMs = withinWindow ? windowStartMs : nowMs;
        const nextRateCount = withinWindow ? rateCount : 0;
        const currentDateKey = getJstDateKey();
        const prevDateKey = typeof data.postDailyDateKey === "string" ? data.postDailyDateKey : "";
        const rawDailyCount = Number(data.postDailyCount ?? 0);
        const baseDailyCount = Number.isFinite(rawDailyCount) ? Math.max(0, Math.trunc(rawDailyCount)) : 0;
        const currentDailyCount = prevDateKey === currentDateKey ? baseDailyCount : 0;

        console.log(
            `[POST_RATE] user=${userId} withinWindow=${withinWindow} ` +
            `rateCount=${rateCount} nextRateCount=${nextRateCount} ` +
            `dateKey=${currentDateKey} prevDateKey=${prevDateKey} dailyCount=${currentDailyCount}`
        );

        if (nextRateCount >= POSTS_PER_MINUTE_LIMIT) {
            console.log(`[POST_RATE] blocked minute limit user=${userId}`);
            throw new HttpsError(
                "resource-exhausted",
                VALIDATION_ERRORS.RATE_LIMITED_PER_MINUTE
            );
        }

        if (currentDailyCount >= POSTS_DAILY_LIMIT) {
            console.log(`[POST_RATE] blocked daily limit user=${userId} dailyCount=${currentDailyCount}`);
            throw new HttpsError(
                "resource-exhausted",
                VALIDATION_ERRORS.RATE_LIMITED_DAILY_15
            );
        }

        transaction.update(userRef, {
            postRateWindowStartMs: nextWindowStartMs,
            postRateCount: nextRateCount + 1,
            postDailyDateKey: currentDateKey,
            postDailyCount: currentDailyCount + 1,
            updatedAt: FieldValue.serverTimestamp(),
        });
        console.log(
            `[POST_RATE] updated user=${userId} postRateCount=${nextRateCount + 1} ` +
            `postDailyCount=${currentDailyCount + 1}`
        );
    });
}

/**
 * モデレーション付き投稿作成
 * ネガティブな内容は投稿を拒否し、徳を減少
 */
export const createPostWithModeration = onCall(
    {
        region: LOCATION,
        secrets: [geminiApiKey],
        timeoutSeconds: 120,
        memory: "1GiB",
        enforceAppCheck: true,
    },
    async (request) => {
        console.log("=== createPostWithModeration START ===");

        const userId = requireAuth(request);
        await enforcePostRateLimits(userId);
        const {
            content,
            userDisplayName,
            userAvatarIndex,
            postMode,
            circleId,
            mediaItems,
            grantVirtue: grantVirtueFlag,
        } = request.data;
        const shouldGrantVirtue = grantVirtueFlag !== false;
        console.log(`User: ${userId}, Content: ${content?.substring(0, 30)}...`);

        // ユーザーがBANされているかチェック
        const userDoc = await db.collection("users").doc(userId).get();
        if (userDoc.exists && userDoc.data()?.isBanned) {
            console.log("ERROR: User is banned");
            throw new HttpsError(
                "permission-denied",
                AUTH_ERRORS.BANNED
            );
        }
        console.log("STEP 1: User check passed");

        const apiKey = geminiApiKey.value();

        // Fail Closed: APIキーがない場合はエラー
        if (!apiKey) {
            console.error("ERROR: GEMINI_API_KEY is not set");
            throw new HttpsError("internal", SYSTEM_ERRORS.INTERNAL);
        }
        console.log("STEP 2: API key loaded");

        const genAI = new GoogleGenerativeAI(apiKey);
        const model = genAI.getGenerativeModel({ model: AI_MODELS.GEMINI_DEFAULT });
        console.log("STEP 3: Model initialized");

        // 曖昧コンテンツフラグ用変数
        let needsReview = false;
        let needsReviewReason = "";

        // テスト用: 管理者の添付付き投稿は常にフラグを付ける
        const userIsAdmin = await isAdmin(userId);
        if (userIsAdmin && mediaItems && Array.isArray(mediaItems) && mediaItems.length > 0) {
            needsReview = true;
            needsReviewReason = MODERATION_MESSAGES.TEST_ADMIN_MEDIA;
            console.log(`TEST FLAG: Admin post with media flagged for review`);
        }

        // ===============================================
        // 0. 静的NGワードチェック
        // ===============================================
        if (content) {
            const hasNgWord = NG_WORDS.some((word) => content.includes(word));
            if (hasNgWord) {
                throw new HttpsError(
                    "invalid-argument",
                    MODERATION_MESSAGES.NG_WORD_USED
                );
            }
        }

        // ===============================================
        // 1. テキストモデレーション
        // ===============================================
        console.log("STEP 4: Starting text moderation");
        if (model && content) {
            const textPrompt = `
あなたはSNS「ほめっぷ」のコンテンツモデレーターです。
「ほめっぷ」は「世界一優しいSNS」を目指しています。

以下の投稿内容を分析して、「他者への攻撃」や「暴力的な表現」があるかどうか厳格に判定してください。

【ブロック対象（isNegative: true）】
- harassment: 他者への誹謗中傷、人格攻撃、悪口
- hate_speech: 差別、ヘイトスピーチ
- profanity: 暴言、罵倒、汚い言葉（「死ね」「殺す」などは対象なしでもNG）
- violence: 暴力的な表現、脅迫
- self_harm: 自傷行為の助長
- spam: スパム、宣伝

上記に該当しない場合は isNegative: false としてください。

【重要な判定基準】
⚠️ 暴力的な言葉（殺す、死ね、殴るなど）は、対象が特定されていなくても「profanity」または「violence」としてブロックしてください。
⚠️ 「他者を攻撃しているか」は厳しく見てください。

【投稿内容】
${content}

【回答形式】
必ず以下のJSON形式で回答してください。他の文字は含めないでください。
{"isNegative": true/false, "category": "harassment"|"hate_speech"|"profanity"|"violence"|"self_harm"|"spam"|"none", "confidence": 0-1, "reason": "判定理由", "suggestion": "より良い表現の提案"}
`;

            let rawResponseText = "";
            try {
                const result = await model.generateContent(textPrompt);
                const responseText = result.response.text().trim();
                rawResponseText = responseText;
                logAIUsage("post_text_moderation", result.response, {
                    userId,
                    hasContent: Boolean(content),
                });
                console.log("STEP 5: Got Gemini response, length:", responseText.length);

                // JSONを抽出
                let jsonText = responseText;
                const codeBlockMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
                if (codeBlockMatch && codeBlockMatch[1]) {
                    jsonText = codeBlockMatch[1].trim();
                } else {
                    const firstBrace = responseText.indexOf("{");
                    const lastBrace = responseText.lastIndexOf("}");
                    if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
                        jsonText = responseText.substring(firstBrace, lastBrace + 1);
                    }
                }

                const modResult = JSON.parse(jsonText) as ModerationResult;
                console.log("STEP 5d: Parsed successfully, isNegative:", modResult.isNegative);

                // 曖昧コンテンツ判定 (0.5-0.7) → フラグ付き投稿
                if (modResult.isNegative && modResult.confidence >= 0.5 && modResult.confidence < 0.7) {
                    needsReview = true;
                    needsReviewReason = `テキスト: ${modResult.category} (confidence: ${modResult.confidence})`;
                    console.log(`FLAGGED for review: ${needsReviewReason}`);
                }

                if (modResult.isNegative && modResult.confidence >= 0.7) {
                    await db.collection("moderatedContent").add({
                        userId: userId,
                        content: content,
                        type: "post",
                        category: modResult.category,
                        confidence: modResult.confidence,
                        reason: modResult.reason,
                        createdAt: FieldValue.serverTimestamp(),
                    });

                    throw new HttpsError(
                        "invalid-argument",
                        MODERATION_MESSAGES.suggestionWithReason(
                            modResult.reason,
                            modResult.suggestion
                        )
                    );
                }
            } catch (error) {
                if (error instanceof HttpsError) {
                    throw error;
                }
                console.error("Text moderation error:", error);

                try {
                    await db.collection("moderationErrors").add({
                        userId: userId,
                        content: content?.substring(0, 100) || "",
                        error: String(error),
                        rawResponse: rawResponseText ? rawResponseText.substring(0, 500) : "empty",
                        createdAt: FieldValue.serverTimestamp(),
                    });
                } catch (firestoreError) {
                    console.error("Failed to save moderation error:", firestoreError);
                }

                // Fail Open: AIエラー時は投稿を許可する
                console.log("Moderation failed, allowing post (fail-open)");
            }
        }

        // ===============================================
        // 2. メディアモデレーション
        // ===============================================
        if (apiKey && model && mediaItems && Array.isArray(mediaItems) && mediaItems.length > 0) {
            console.log(`Moderating ${mediaItems.length} media items...`);

            try {
                const mediaResult = await moderateMedia(apiKey, model, mediaItems as MediaItem[]);

                if (!mediaResult.passed && mediaResult.result) {
                    if (mediaResult.result.confidence >= 0.5 && mediaResult.result.confidence < 0.7) {
                        needsReview = true;
                        needsReviewReason = `メディア: ${mediaResult.result.category} (confidence: ${mediaResult.result.confidence})`;
                        console.log(`FLAGGED for review: ${needsReviewReason}`);
                    } else if (mediaResult.result.confidence >= 0.7) {
                        await db.collection("moderatedContent").add({
                            userId: userId,
                            content: `[メディア] ${mediaResult.failedItem?.fileName || "media"} `,
                            type: "media",
                            category: mediaResult.result.category,
                            confidence: mediaResult.result.confidence,
                            reason: mediaResult.result.reason,
                            createdAt: FieldValue.serverTimestamp(),
                        });

                        const categoryLabels: Record<string, string> = {
                            adult: LABELS.CONTENT_ADULT,
                            violence: LABELS.CONTENT_VIOLENCE,
                            hate: LABELS.CONTENT_HATE,
                            dangerous: LABELS.CONTENT_DANGEROUS,
                        };

                        const categoryLabel = categoryLabels[mediaResult.result.category] || LABELS.CONTENT_INAPPROPRIATE;

                        // アップロード済みメディアをStorageから削除
                        console.log(`Deleting ${mediaItems.length} uploaded media files due to moderation failure...`);
                        for (const item of mediaItems as MediaItem[]) {
                            try {
                                const url = new URL(item.url);
                                const pathMatch = url.pathname.match(/\/o\/(.+?)(\?|$)/);
                                if (pathMatch) {
                                    const storagePath = decodeURIComponent(pathMatch[1]);
                                    await admin.storage().bucket().file(storagePath).delete();
                                    console.log(`Deleted: ${storagePath}`);
                                }
                            } catch (deleteError) {
                                console.error(`Failed to delete media: ${item.url}`, deleteError);
                            }
                        }

                        throw new HttpsError(
                            "invalid-argument",
                            MODERATION_MESSAGES.mediaBlockedSimple(
                                mediaResult.failedItem?.type === "video" ? "video" : "image",
                                categoryLabel
                            )
                        );
                    }
                }

                console.log("Media moderation passed");
            } catch (error) {
                if (error instanceof HttpsError) {
                    throw error;
                }
                console.error("Media moderation error:", error);
                throw new HttpsError("internal", SYSTEM_ERRORS.MEDIA_ERROR);
            }
        }

        // ===============================================
        // 3. 投稿を作成
        // ===============================================
        const postRef = db.collection("posts").doc();
        await postRef.set({
            userId: userId,
            userDisplayName: userDisplayName,
            userAvatarIndex: userAvatarIndex,
            content: content,
            mediaItems: mediaItems || [],
            postMode: postMode,
            circleId: circleId || null,
            createdAt: FieldValue.serverTimestamp(),
            reactions: { love: 0, praise: 0, cheer: 0, empathy: 0 },
            commentCount: 0,
            isVisible: true,
            needsReview: needsReview,
            needsReviewReason: needsReviewReason,
        });

        if (needsReview) {
            console.log(`Notifying admin about flagged post: ${postRef.id}`);
            try {
                await db.collection("pendingReviews").doc(postRef.id).set({
                    postId: postRef.id,
                    userId: userId,
                    reason: needsReviewReason,
                    createdAt: FieldValue.serverTimestamp(),
                    reviewed: false,
                });

                const adminUids = await getAdminUids();
                const notifyBody = NOTIFICATION_BODIES.flaggedPost(needsReviewReason);

                for (const adminUid of adminUids) {
                    await db.collection("users").doc(adminUid).collection("notifications").add({
                        type: "review_needed",
                        title: NOTIFICATION_TITLES.REVIEW_NEEDED,
                        body: notifyBody,
                        postId: postRef.id,
                        fromUserId: userId,
                        fromUserName: userDisplayName,
                        createdAt: FieldValue.serverTimestamp(),
                        read: false,
                    });
                }
                console.log("Admin notifications created");
            } catch (notifyError) {
                console.error("Failed to notify admin:", notifyError);
            }
        }

        // ===============================================
        // 5. Storageメディアのメタデータを更新
        // ===============================================
        if (mediaItems && Array.isArray(mediaItems) && mediaItems.length > 0) {
            console.log(`Updating metadata for ${mediaItems.length} media files...`);
            const bucket = admin.storage().bucket();

            for (const item of mediaItems as MediaItem[]) {
                try {
                    const url = new URL(item.url);
                    const pathMatch = url.pathname.match(/\/o\/(.+?)(\?|$)/);
                    if (pathMatch) {
                        const storagePath = decodeURIComponent(pathMatch[1]);
                        const file = bucket.file(storagePath);

                        await file.setMetadata({
                            metadata: {
                                postId: postRef.id,
                            },
                        });
                        console.log(`Updated metadata: ${storagePath} → postId=${postRef.id}`);
                    }
                } catch (metadataError) {
                    console.error(`Failed to update metadata for ${item.url}:`, metadataError);
                }
            }
        }

        if (circleId) {
            try {
                await db.collection("circles").doc(circleId).update({
                    postCount: FieldValue.increment(1),
                    recentActivity: FieldValue.serverTimestamp(),
                    lastHumanPostAt: FieldValue.serverTimestamp(),
                });
            } catch (error) {
                console.error("Failed to update circle counters:", error);
            }
        }

        // ユーザーの投稿数を更新
        await db.collection("users").doc(userId).update({
            totalPosts: FieldValue.increment(1),
        });

        if (shouldGrantVirtue) {
            const virtuePolicy = await getVirtuePolicy();
            await grantVirtue({
                userId,
                routeKey: VIRTUE_ROUTE_KEYS.postCreate,
                points: virtuePolicy.postCreatePoints,
                dailyCap: virtuePolicy.postCreateDailyCap,
                reason: VIRTUE_MESSAGES.POST_CREATE_GRANT_REASON,
                source: "post_create",
                targetId: postRef.id,
            });
        }

        console.log(`=== createPostWithModeration SUCCESS: postId=${postRef.id} ===`);
        return { success: true, postId: postRef.id };
    }
);
