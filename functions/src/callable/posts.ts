/**
 * 投稿作成関連のCallable関数
 * Phase 5: index.ts から分離
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

import { db, FieldValue } from "../helpers/firebase";
import { requireAuth } from "../helpers/auth";
import { geminiApiKey, openaiApiKey } from "../config/secrets";
import { isAdmin, getAdminUids } from "../helpers/admin";
import { MediaItem } from "../types";
import { moderateMedia } from "../helpers/moderation";
import { moderateText } from "../helpers/text-moderation";
import { getVirtuePolicy, grantVirtue, VIRTUE_ROUTE_KEYS } from "../helpers/virtue-policy";
import { LOCATION } from "../config/constants";
import { createAIProviderFactory } from "../ai/provider";
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
        secrets: [geminiApiKey, openaiApiKey],
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

        // 投稿文字数の上限チェック（Unicodeコードポイント数で判定、絵文字を考慮し余裕を持たせる）
        if (typeof content === "string" && [...content].length > 220) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
        }

        // 動画メディアの拒否（動画添付は廃止済み）
        if (Array.isArray(mediaItems) && mediaItems.some((item: { type?: string; mimeType?: string }) =>
            item.type === "video" || (typeof item.mimeType === "string" && item.mimeType.startsWith("video/"))
        )) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
        }

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

        // Fail Closed: APIキーが1つも利用できない場合はエラー
        const geminiKey = geminiApiKey.value() || "";
        const openaiKey = openaiApiKey.value() || "";
        if (!geminiKey && !openaiKey) {
            console.error("ERROR: No AI API key available (both GEMINI and OPENAI are empty)");
            throw new HttpsError("internal", SYSTEM_ERRORS.INTERNAL);
        }
        const aiFactory = createAIProviderFactory();
        console.log("STEP 2: AI factory initialized");

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
        // 0-1. テキストモデレーション（NGワード + AIモデレーション）
        // ===============================================
        console.log("STEP 4: Starting text moderation");
        if (content) {
            const modOutcome = await moderateText({
                type: "post",
                userId,
                contentDescription: "投稿内容",
                contentBody: content,
            });
            if (modOutcome.flagged) {
                needsReview = true;
                needsReviewReason = modOutcome.flagReason || "";
                console.log(`FLAGGED for review: ${needsReviewReason}`);
            }
        }

        // ===============================================
        // 2. メディアモデレーション
        // ===============================================
        if (mediaItems && Array.isArray(mediaItems) && mediaItems.length > 0) {
            console.log(`Moderating ${mediaItems.length} media items...`);

            try {
                const mediaResult = await moderateMedia(aiFactory, mediaItems as MediaItem[]);

                if (!mediaResult.passed && mediaResult.result) {
                    if (mediaResult.result.confidence >= 0.5 && mediaResult.result.confidence < 0.7) {
                        needsReview = true;
                        needsReviewReason = `メディア: ${mediaResult.result.category} (confidence: ${mediaResult.result.confidence})`;
                        console.log(`FLAGGED for review: ${needsReviewReason}`);
                    } else if (mediaResult.result.confidence >= 0.7) {
                        console.warn("[MODERATION NG] post media rejected:", JSON.stringify({
                            category: mediaResult.result.category,
                            confidence: mediaResult.result.confidence,
                            reason: mediaResult.result.reason,
                            fileName: mediaResult.failedItem?.fileName,
                        }));
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
                                "image",
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
