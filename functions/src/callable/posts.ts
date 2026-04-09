/**
 * 投稿作成関連のCallable関数
 * Phase 5: index.ts から分離
 */

import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";

import { admin, db, FieldValue, Timestamp } from "../helpers/firebase";
import { requireAuth, requireAdmin } from "../helpers/auth";
import { geminiApiKey, openaiApiKey } from "../config/secrets";
import { isAdmin, getAdminUids } from "../helpers/admin";
import { MediaItem } from "../types";
import { moderateMedia } from "../helpers/moderation";
import { moderateText } from "../helpers/text-moderation";
import { getVirtuePolicy, grantVirtue, VIRTUE_ROUTE_KEYS } from "../helpers/virtue-policy";
import {
    deletePendingMediaByStoragePaths,
    getMediaStoragePath,
    getMediaStoragePaths,
} from "../helpers/pending-media";
import { deleteStorageFileByPath } from "../helpers/storage";
import { schedulePublishedPostSideEffects } from "../helpers/post-publish";
import { scheduleHttpTask } from "../helpers/cloud-tasks";
import {
    computeNextGhostCheckAt,
} from "../helpers/circle-scheduling";
import { verifyCloudTasksRequest } from "../helpers/cloud-tasks-auth";
import { LOCATION, PROJECT_ID, QUEUE_NAME, CLOUD_TASK_FUNCTIONS } from "../config/constants";
import { createAIProviderFactory } from "../ai/provider";
import {
    AUTH_ERRORS,
    PERMISSION_ERRORS,
    VALIDATION_ERRORS,
    SYSTEM_ERRORS,
    NOTIFICATION_TITLES,
    NOTIFICATION_BODIES,
    LABELS,
    MODERATION_MESSAGES,
    POST_MODERATION_NOTIFICATION_MESSAGES,
    RESOURCE_ERRORS,
    VIRTUE_MESSAGES,
} from "../config/messages";
import { sendPushNotification } from "../helpers/notification";

const POSTS_PER_MINUTE_LIMIT = 2;
const POSTS_DAILY_LIMIT = 15;
const JST_OFFSET_MS = 9 * 60 * 60 * 1000;
const POST_RATE_WINDOW_MS = 60 * 1000;
const POST_REQUEST_STALE_MS = 2 * 60 * 1000;
const POST_REJECTED_TTL_MS = 24 * 60 * 60 * 1000;
const POST_MODERATION_TIMEOUT_MS = 15 * 60 * 1000;
const POST_MODERATION_STATUS_PROCESSING = "processing";
const POST_MODERATION_STATUS_APPROVED = "approved";
const POST_MODERATION_STATUS_REJECTED = "rejected";
const POST_MODERATION_STATUS_REVIEW_NEEDED = "review_needed";
const POST_MODERATION_SIDE_EFFECT_KIND_REJECTED = "rejected";
const POST_MODERATION_SIDE_EFFECT_KIND_REVIEW_NEEDED = "review_needed";
const TERMINAL_POST_REQUEST_ERROR_CODES = new Set([
    "invalid-argument",
    "permission-denied",
    "resource-exhausted",
    "not-found",
]);

type PostRequestBeginResult =
    | { kind: "continue"; ref: FirebaseFirestore.DocumentReference }
    | { kind: "succeeded"; postId: string }
    | { kind: "rejected"; code: string; message: string }
    | { kind: "processing" };

function getPostRequestRef(
    userId: string,
    clientRequestId: string
): FirebaseFirestore.DocumentReference {
    return db.collection("users").doc(userId).collection("postRequests").doc(clientRequestId);
}

async function beginPostRequest(
    userId: string,
    clientRequestId: string
): Promise<PostRequestBeginResult> {
    const existingPostSnapshot = await db.collection("posts")
        .where("clientRequestId", "==", clientRequestId)
        .limit(1)
        .get();
    if (!existingPostSnapshot.empty) {
        return {
            kind: "succeeded",
            postId: existingPostSnapshot.docs[0].id,
        };
    }

    const requestRef = getPostRequestRef(userId, clientRequestId);
    const now = admin.firestore.Timestamp.now();

    return db.runTransaction(async (transaction): Promise<PostRequestBeginResult> => {
        const requestSnap = await transaction.get(requestRef);
        if (requestSnap.exists) {
            const requestData = requestSnap.data() || {};
            const status = typeof requestData.status === "string" ? requestData.status : "";
            const storedPostId = typeof requestData.postId === "string" ? requestData.postId : "";
            const storedErrorCode = typeof requestData.errorCode === "string" ? requestData.errorCode : "";
            const storedErrorMessage = typeof requestData.errorMessage === "string" ? requestData.errorMessage : "";
            const updatedAt = requestData.updatedAt instanceof admin.firestore.Timestamp ?
                requestData.updatedAt.toMillis() :
                0;

            if (status === "succeeded" && storedPostId) {
                return {
                    kind: "succeeded",
                    postId: storedPostId,
                };
            }

            if (status === "rejected" && storedErrorCode && storedErrorMessage) {
                return {
                    kind: "rejected",
                    code: storedErrorCode,
                    message: storedErrorMessage,
                };
            }

            if (status === "processing" && now.toMillis() - updatedAt < POST_REQUEST_STALE_MS) {
                return { kind: "processing" };
            }
        }

        transaction.set(requestRef, {
            status: "processing",
            updatedAt: now,
            createdAt: requestSnap.exists ? requestSnap.data()?.createdAt ?? now : now,
            postId: FieldValue.delete(),
            errorCode: FieldValue.delete(),
            errorMessage: FieldValue.delete(),
        }, { merge: true });

        return {
            kind: "continue",
            ref: requestRef,
        };
    });
}

async function markPostRequestSucceeded(
    requestRef: FirebaseFirestore.DocumentReference,
    postId: string
): Promise<void> {
    await requestRef.set({
        status: "succeeded",
        postId,
        updatedAt: FieldValue.serverTimestamp(),
        errorCode: FieldValue.delete(),
        errorMessage: FieldValue.delete(),
    }, { merge: true });
}

async function markPostRequestRejected(
    requestRef: FirebaseFirestore.DocumentReference,
    code: string,
    message: string
): Promise<void> {
    await requestRef.set({
        status: "rejected",
        errorCode: code,
        errorMessage: message,
        updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
}

async function clearPostRequest(
    requestRef: FirebaseFirestore.DocumentReference
): Promise<void> {
    try {
        await requestRef.delete();
    } catch (error) {
        console.warn("Failed to clear post request lock:", error);
    }
}

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

function toStoredMediaItem(item: MediaItem): Omit<MediaItem, "storagePath"> {
    return {
        url: item.url,
        type: item.type,
        ...(item.fileName ? { fileName: item.fileName } : {}),
        ...(item.mimeType ? { mimeType: item.mimeType } : {}),
        ...(item.fileSize !== undefined ? { fileSize: item.fileSize } : {}),
        ...(item.thumbnailUrl ? { thumbnailUrl: item.thumbnailUrl } : {}),
    };
}

function buildPostModerationTargetUrl(functionName: string): string {
    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    return `https://${LOCATION}-${project}.cloudfunctions.net/${functionName}`;
}

function buildModerationAttemptId(clientRequestId: string): string {
    return clientRequestId || db.collection("_postModerationAttempts").doc().id;
}

async function schedulePostModerationTask(postId: string, moderationAttemptId: string): Promise<void> {
    await scheduleHttpTask({
        queue: QUEUE_NAME,
        url: buildPostModerationTargetUrl(CLOUD_TASK_FUNCTIONS.executePostModeration),
        payload: { postId, moderationAttemptId },
        location: LOCATION,
        projectId: process.env.GCLOUD_PROJECT || PROJECT_ID,
        taskId: `post-moderation-${postId}-${moderationAttemptId}`,
    });
}

async function schedulePostModerationTimeoutTask(postId: string, moderationAttemptId: string): Promise<void> {
    await scheduleHttpTask({
        queue: QUEUE_NAME,
        url: buildPostModerationTargetUrl(CLOUD_TASK_FUNCTIONS.checkPostModerationTimeout),
        payload: { postId, moderationAttemptId },
        scheduleTime: new Date(Date.now() + POST_MODERATION_TIMEOUT_MS),
        location: LOCATION,
        projectId: process.env.GCLOUD_PROJECT || PROJECT_ID,
        taskId: `post-moderation-timeout-${postId}-${moderationAttemptId}`,
    });
}

async function scheduleRejectedPostCleanupTask(postId: string, ownerVisibleUntil: Date): Promise<void> {
    await scheduleHttpTask({
        queue: QUEUE_NAME,
        url: buildPostModerationTargetUrl(CLOUD_TASK_FUNCTIONS.cleanupRejectedPost),
        payload: { postId },
        scheduleTime: ownerVisibleUntil,
        location: LOCATION,
        projectId: process.env.GCLOUD_PROJECT || PROJECT_ID,
        taskId: `cleanup-rejected-${postId}-${ownerVisibleUntil.getTime()}`,
    });
}

async function deleteUploadedMedia(mediaItems: MediaItem[]): Promise<void> {
    const storagePaths = getMediaStoragePaths(mediaItems);

    await Promise.all(storagePaths.map((storagePath) => deleteStorageFileByPath(storagePath)));

    await deletePendingMediaByStoragePaths(storagePaths);
}

async function deleteStoragePathsBestEffort(storagePaths: string[]): Promise<void> {
    const uniquePaths = [...new Set(storagePaths.filter((path) => typeof path === "string" && path.length > 0))];
    if (uniquePaths.length === 0) {
        return;
    }

    await Promise.all(uniquePaths.map(async (storagePath) => {
        try {
            await deleteStorageFileByPath(storagePath);
        } catch (error) {
            console.error(`Failed to delete storage file during repost cleanup: ${storagePath}`, error);
        }
    }));

    try {
        await deletePendingMediaByStoragePaths(uniquePaths);
    } catch (error) {
        console.error("Failed to delete pending media during repost cleanup:", error);
    }
}

function parseStoredMediaItems(
    rawMediaItems: unknown,
    rawStoragePaths: unknown
): MediaItem[] {
    if (!Array.isArray(rawMediaItems)) {
        return [];
    }

    const storagePaths = Array.isArray(rawStoragePaths) ?
        rawStoragePaths.filter((path): path is string => typeof path === "string") :
        [];

    return rawMediaItems.map((item, index) => {
        const data = item && typeof item === "object" ? item as Record<string, unknown> : {};
        return {
            url: typeof data.url === "string" ? data.url : "",
            type: data.type === "video" || data.type === "file" ? data.type : "image",
            ...(typeof data.fileName === "string" ? { fileName: data.fileName } : {}),
            ...(typeof data.mimeType === "string" ? { mimeType: data.mimeType } : {}),
            ...(typeof data.fileSize === "number" ? { fileSize: data.fileSize } : {}),
            ...(typeof data.thumbnailUrl === "string" ? { thumbnailUrl: data.thumbnailUrl } : {}),
            ...(typeof data.storagePath === "string" ?
                { storagePath: data.storagePath } :
                (typeof storagePaths[index] === "string" ? { storagePath: storagePaths[index] } : {})),
        };
    });
}

async function createPendingReviewAndNotifyAdmins(params: {
    postId: string;
    userId: string;
    userDisplayName: string;
    reason: string;
    idempotencyKey?: string;
}): Promise<void> {
    await db.collection("pendingReviews").doc(params.postId).set({
        postId: params.postId,
        userId: params.userId,
        reason: params.reason,
        createdAt: FieldValue.serverTimestamp(),
        reviewed: false,
    });

    const adminUids = await getAdminUids();
    const notifyBody = NOTIFICATION_BODIES.flaggedPost(params.reason);

    await Promise.all(adminUids.map(async (adminUid) => {
        await sendPushNotification(
            adminUid,
            "review_needed",
            params.postId,
            NOTIFICATION_TITLES.REVIEW_NEEDED,
            notifyBody,
            { postId: params.postId },
            {
                type: "review_needed",
                senderId: params.userId,
                senderName: params.userDisplayName,
                senderAvatarUrl: "",
                idempotencyKey: params.idempotencyKey,
                throwOnError: true,
            }
        );
    }));
}

async function notifyRejectedPostOwner(params: {
    postId: string;
    userId: string;
    idempotencyKey?: string;
}): Promise<void> {
    await sendPushNotification(
        params.userId,
        "post_rejected",
        params.postId,
        POST_MODERATION_NOTIFICATION_MESSAGES.REJECTED_TITLE,
        POST_MODERATION_NOTIFICATION_MESSAGES.REJECTED_BODY,
        { postId: params.postId },
        {
            type: "post_rejected",
            senderId: "system",
            senderName: LABELS.ADMIN_TEAM,
            senderAvatarUrl: "",
            idempotencyKey: params.idempotencyKey,
            throwOnError: true,
        }
    );
}

async function markPostRejected(params: {
    postRef: FirebaseFirestore.DocumentReference;
    reason: string;
}): Promise<void> {
    const ownerVisibleUntil = new Date(Date.now() + POST_REJECTED_TTL_MS);

    await params.postRef.update({
        moderationStatus: POST_MODERATION_STATUS_REJECTED,
        moderationReason: params.reason,
        moderationCompletedAt: FieldValue.serverTimestamp(),
        ownerVisibleUntil: Timestamp.fromDate(ownerVisibleUntil),
        isVisible: false,
        needsReview: false,
        needsReviewReason: "",
        publishSideEffectsPending: false,
        grantVirtueOnPublish: false,
        moderationSideEffectsPending: true,
        moderationSideEffectsKind: POST_MODERATION_SIDE_EFFECT_KIND_REJECTED,
    });
}

async function markPostReviewNeeded(params: {
    postRef: FirebaseFirestore.DocumentReference;
    reason: string;
}): Promise<void> {
    await params.postRef.update({
        moderationStatus: POST_MODERATION_STATUS_REVIEW_NEEDED,
        moderationReason: params.reason,
        moderationCompletedAt: FieldValue.serverTimestamp(),
        ownerVisibleUntil: FieldValue.delete(),
        isVisible: false,
        needsReview: true,
        needsReviewReason: params.reason,
        publishSideEffectsPending: false,
        grantVirtueOnPublish: false,
        moderationSideEffectsPending: true,
        moderationSideEffectsKind: POST_MODERATION_SIDE_EFFECT_KIND_REVIEW_NEEDED,
    });
}

async function approvePostAndApplyCounters(params: {
    postRef: FirebaseFirestore.DocumentReference;
    userId: string;
    circleId?: string | null;
    allowedStatuses?: string[];
}): Promise<void> {
    const approvalDate = new Date();
    const allowedStatuses = params.allowedStatuses ?? [
        POST_MODERATION_STATUS_PROCESSING,
    ];

    await db.runTransaction(async (transaction) => {
        const postSnap = await transaction.get(params.postRef);
        if (!postSnap.exists) {
            return;
        }

        const postData = postSnap.data() || {};
        if (!allowedStatuses.includes(postData.moderationStatus)) {
            return;
        }

        transaction.update(params.postRef, {
            moderationStatus: POST_MODERATION_STATUS_APPROVED,
            moderationReason: "",
            moderationCompletedAt: FieldValue.serverTimestamp(),
            ownerVisibleUntil: FieldValue.delete(),
            isVisible: true,
            needsReview: false,
            needsReviewReason: "",
            publishSideEffectsPending: true,
            moderationSideEffectsPending: false,
            moderationSideEffectsKind: FieldValue.delete(),
        });

        transaction.update(db.collection("users").doc(params.userId), {
            totalPosts: FieldValue.increment(1),
        });

        if (params.circleId) {
            transaction.update(db.collection("circles").doc(params.circleId), {
                postCount: FieldValue.increment(1),
                recentActivity: FieldValue.serverTimestamp(),
                lastHumanPostAt: FieldValue.serverTimestamp(),
                ghostWarningNotifiedAt: FieldValue.delete(),
                nextGhostCheckAt: Timestamp.fromDate(computeNextGhostCheckAt({
                    createdAt: approvalDate,
                    lastHumanPostAt: approvalDate,
                    ghostWarningNotifiedAt: null,
                })),
            });
        }
    });
}

async function grantPostCreateVirtueOnce(params: {
    userId: string;
    postId: string;
}): Promise<void> {
    const virtuePolicy = await getVirtuePolicy();
    const requestedPoints = Math.max(0, Math.trunc(virtuePolicy.postCreatePoints));
    const dailyCap = Math.max(0, Math.trunc(virtuePolicy.postCreateDailyCap));
    if (requestedPoints <= 0) {
        return;
    }

    const historyRef = db.collection("virtueHistory").doc(`post-create-${params.postId}`);
    const userRef = db.collection("users").doc(params.userId);
    const dateKey = getJstDateKey();
    const dailyRef = userRef.collection("virtueDaily").doc(dateKey);

    await db.runTransaction(async (transaction) => {
        const [historyDoc, userDoc, dailyDoc] = await Promise.all([
            transaction.get(historyRef),
            transaction.get(userRef),
            transaction.get(dailyRef),
        ]);

        if (historyDoc.exists || !userDoc.exists) {
            return;
        }

        const routePoints = dailyDoc.data()?.routePoints as Record<string, unknown> | undefined;
        const usedTodayRaw = Number(routePoints?.[VIRTUE_ROUTE_KEYS.postCreate] ?? 0);
        const usedToday = Number.isFinite(usedTodayRaw) ? Math.max(0, Math.trunc(usedTodayRaw)) : 0;
        const granted = Math.min(requestedPoints, Math.max(0, dailyCap - usedToday));
        if (granted <= 0) {
            return;
        }

        const currentVirtueRaw = Number(userDoc.data()?.virtue ?? 100);
        const currentVirtue = Number.isFinite(currentVirtueRaw) ? currentVirtueRaw : 100;
        const newVirtue = currentVirtue + granted;

        transaction.update(userRef, {
            virtue: newVirtue,
            updatedAt: FieldValue.serverTimestamp(),
        });
        transaction.set(dailyRef, {
            dateKey,
            routePoints: {
                [VIRTUE_ROUTE_KEYS.postCreate]: usedToday + granted,
            },
            updatedAt: FieldValue.serverTimestamp(),
            createdAt: FieldValue.serverTimestamp(),
        }, { merge: true });
        transaction.set(historyRef, {
            userId: params.userId,
            change: granted,
            reason: VIRTUE_MESSAGES.POST_CREATE_GRANT_REASON,
            source: "post_create",
            routeKey: VIRTUE_ROUTE_KEYS.postCreate,
            targetId: params.postId,
            newVirtue,
            createdAt: FieldValue.serverTimestamp(),
        });
    });
}

async function finalizeApprovedPost(params: {
    postRef: FirebaseFirestore.DocumentReference;
    postId: string;
}): Promise<void> {
    const postSnap = await params.postRef.get();
    if (!postSnap.exists) {
        return;
    }

    const postData = postSnap.data() || {};
    if (postData.moderationStatus !== POST_MODERATION_STATUS_APPROVED ||
        postData.publishSideEffectsPending !== true) {
        return;
    }

    const mediaItems = parseStoredMediaItems(postData.mediaItems, postData.mediaStoragePaths);
    const mediaStoragePaths = getMediaStoragePaths(mediaItems);

    if (mediaStoragePaths.length > 0) {
        const bucket = admin.storage().bucket();
        await Promise.all(mediaStoragePaths.map(async (storagePath) => {
            try {
                const file = bucket.file(storagePath);
                await file.setMetadata({
                    metadata: {
                        postId: params.postId,
                    },
                });
            } catch (error) {
                console.error(`Failed to update metadata for ${storagePath}:`, error);
            }
        }));
    }

    await deletePendingMediaByStoragePaths(mediaStoragePaths);

    if (postData.grantVirtueOnPublish === true && typeof postData.userId === "string") {
        await grantPostCreateVirtueOnce({
            userId: postData.userId,
            postId: params.postId,
        });
    }

    await schedulePublishedPostSideEffects({
        postId: params.postId,
        postData,
    });

    await params.postRef.update({
        publishSideEffectsPending: false,
        grantVirtueOnPublish: false,
        moderationSideEffectsPending: false,
        moderationSideEffectsKind: FieldValue.delete(),
    });
}

async function finalizeRejectedPost(params: {
    postRef: FirebaseFirestore.DocumentReference;
    postId: string;
}): Promise<void> {
    const postSnap = await params.postRef.get();
    if (!postSnap.exists) {
        return;
    }

    const postData = postSnap.data() || {};
    if (postData.moderationStatus !== POST_MODERATION_STATUS_REJECTED ||
        postData.moderationSideEffectsPending !== true) {
        return;
    }

    const mediaItems = parseStoredMediaItems(postData.mediaItems, postData.mediaStoragePaths);
    const mediaStoragePaths = getMediaStoragePaths(mediaItems);
    const userId = typeof postData.userId === "string" ? postData.userId : "";
    const ownerVisibleUntil = postData.ownerVisibleUntil instanceof Timestamp ?
        postData.ownerVisibleUntil.toDate() :
        new Date(Date.now() + POST_REJECTED_TTL_MS);
    const moderationCompletedAt = postData.moderationCompletedAt instanceof Timestamp ?
        postData.moderationCompletedAt.toMillis().toString() :
        undefined;

    await deletePendingMediaByStoragePaths(mediaStoragePaths);

    if (userId) {
        await notifyRejectedPostOwner({
            postId: params.postId,
            userId,
            idempotencyKey: moderationCompletedAt,
        });
    }

    await scheduleRejectedPostCleanupTask(params.postId, ownerVisibleUntil);

    await params.postRef.update({
        moderationSideEffectsPending: false,
        moderationSideEffectsKind: FieldValue.delete(),
    });
}

async function finalizeReviewNeededPost(params: {
    postRef: FirebaseFirestore.DocumentReference;
    postId: string;
}): Promise<void> {
    const postSnap = await params.postRef.get();
    if (!postSnap.exists) {
        return;
    }

    const postData = postSnap.data() || {};
    if (postData.moderationStatus !== POST_MODERATION_STATUS_REVIEW_NEEDED ||
        postData.moderationSideEffectsPending !== true) {
        return;
    }

    const mediaItems = parseStoredMediaItems(postData.mediaItems, postData.mediaStoragePaths);
    const mediaStoragePaths = getMediaStoragePaths(mediaItems);
    const userId = typeof postData.userId === "string" ? postData.userId : "";
    const userDisplayName = typeof postData.userDisplayName === "string" ?
        postData.userDisplayName :
        LABELS.ADMIN_TEAM;
    const reason = typeof postData.needsReviewReason === "string" && postData.needsReviewReason ?
        postData.needsReviewReason :
        (typeof postData.moderationReason === "string" ? postData.moderationReason : "");
    const moderationCompletedAt = postData.moderationCompletedAt instanceof Timestamp ?
        postData.moderationCompletedAt.toMillis().toString() :
        undefined;

    await deletePendingMediaByStoragePaths(mediaStoragePaths);
    await createPendingReviewAndNotifyAdmins({
        postId: params.postId,
        userId,
        userDisplayName,
        reason,
        idempotencyKey: moderationCompletedAt,
    });

    await params.postRef.update({
        moderationSideEffectsPending: false,
        moderationSideEffectsKind: FieldValue.delete(),
    });
}

async function cleanupRejectedPostDocument(
    postId: string,
    options?: { ignoreOwnerVisibleUntil?: boolean }
): Promise<void> {
    const postRef = db.collection("posts").doc(postId);
    const postSnap = await postRef.get();
    if (!postSnap.exists) {
        return;
    }

    const postData = postSnap.data() || {};
    if (postData.moderationStatus !== POST_MODERATION_STATUS_REJECTED) {
        return;
    }

    const ownerVisibleUntil = postData.ownerVisibleUntil instanceof Timestamp ?
        postData.ownerVisibleUntil.toDate() :
        null;
    if (!options?.ignoreOwnerVisibleUntil &&
        ownerVisibleUntil &&
        ownerVisibleUntil.getTime() > Date.now()) {
        return;
    }

    const mediaItems = parseStoredMediaItems(postData.mediaItems, postData.mediaStoragePaths);
    const storagePaths = [...new Set(getMediaStoragePaths(mediaItems))];

    for (const storagePath of storagePaths) {
        const references = await db.collection("posts")
            .where("mediaStoragePaths", "array-contains", storagePath)
            .limit(10)
            .get();
        const isReferencedElsewhere = references.docs.some((doc) => doc.id !== postId);
        if (!isReferencedElsewhere) {
            await deleteStorageFileByPath(storagePath);
        }
    }

    await deletePendingMediaByStoragePaths(storagePaths);
    await postRef.delete();
}

export const deleteRejectedPost = onCall(
    {
        region: LOCATION,
        timeoutSeconds: 60,
        memory: "512MiB",
        enforceAppCheck: true,
    },
    async (request) => {
        const userId = await requireAuth(request);
        const { postId } = request.data || {};

        if (!postId || typeof postId !== "string") {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.MISSING_REQUIRED);
        }

        const postRef = db.collection("posts").doc(postId);
        const postSnap = await postRef.get();
        if (!postSnap.exists) {
            throw new HttpsError("not-found", RESOURCE_ERRORS.POST_NOT_FOUND);
        }

        const postData = postSnap.data() || {};
        const ownerId = typeof postData.userId === "string" ? postData.userId : "";
        if (!ownerId) {
            throw new HttpsError("not-found", RESOURCE_ERRORS.POST_NOT_FOUND);
        }

        const requesterIsAdmin = await isAdmin(userId);
        if (ownerId !== userId && !requesterIsAdmin) {
            throw new HttpsError("permission-denied", PERMISSION_ERRORS.POST_DELETE_PERMISSION_DENIED);
        }

        if (postData.moderationStatus !== POST_MODERATION_STATUS_REJECTED) {
            throw new HttpsError("failed-precondition", VALIDATION_ERRORS.POST_NOT_REJECTED);
        }

        await cleanupRejectedPostDocument(postId, {
            ignoreOwnerVisibleUntil: true,
        });

        return { success: true, postId };
    }
);

/**
 * モデレーション付き投稿作成
 * ネガティブな内容は投稿を拒否し、徳を減少
 */
const createPostWithModerationSyncLegacy = onCall(
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
        const {
            content,
            userDisplayName,
            userAvatarIndex,
            postMode,
            circleId,
            mediaItems,
            clientRequestId,
            grantVirtue: grantVirtueFlag,
        } = request.data;
        const normalizedClientRequestId =
            typeof clientRequestId === "string" ? clientRequestId.trim() : "";
        const requestMediaItems = Array.isArray(mediaItems) ? mediaItems as MediaItem[] : [];
        const mediaStoragePaths = getMediaStoragePaths(requestMediaItems);
        const storedMediaItems = requestMediaItems.map((item) => toStoredMediaItem(item));
        const shouldGrantVirtue = grantVirtueFlag !== false;
        let postRequestRef: FirebaseFirestore.DocumentReference | null = null;
        console.log(`User: ${userId}, Content: ${content?.substring(0, 30)}...`);

        if (normalizedClientRequestId) {
            const postRequest = await beginPostRequest(userId, normalizedClientRequestId);
            switch (postRequest.kind) {
            case "succeeded":
                console.log(`Returning existing post for clientRequestId=${normalizedClientRequestId}`);
                return { success: true, postId: postRequest.postId };
            case "rejected":
                throw new HttpsError(
                    postRequest.code as ConstructorParameters<typeof HttpsError>[0],
                    postRequest.message
                );
            case "processing":
                throw new HttpsError("aborted", VALIDATION_ERRORS.POST_REQUEST_IN_PROGRESS);
            case "continue":
                postRequestRef = postRequest.ref;
                break;
            }
        }

        try {
            await enforcePostRateLimits(userId);

            // 投稿文字数の上限チェック（Unicodeコードポイント数で判定、絵文字を考慮し余裕を持たせる）
            if (typeof content === "string" && [...content].length > 220) {
                throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
            }

            // 動画メディアの拒否（動画添付は廃止済み）
            if (requestMediaItems.some((item: { type?: string; mimeType?: string }) =>
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
            if (userIsAdmin && requestMediaItems.length > 0) {
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
            if (requestMediaItems.length > 0) {
                console.log(`Moderating ${requestMediaItems.length} media items...`);

                try {
                    const mediaResult = await moderateMedia(aiFactory, requestMediaItems);

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
                            console.log(`Deleting ${requestMediaItems.length} uploaded media files due to moderation failure...`);
                            await deleteUploadedMedia(requestMediaItems);

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
                mediaItems: storedMediaItems,
                mediaStoragePaths: mediaStoragePaths,
                postMode: postMode,
                circleId: circleId || null,
                ...(normalizedClientRequestId ? { clientRequestId: normalizedClientRequestId } : {}),
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
            if (requestMediaItems.length > 0) {
                console.log(`Updating metadata for ${requestMediaItems.length} media files...`);
                const bucket = admin.storage().bucket();

                await Promise.all(requestMediaItems.map(async (item) => {
                    try {
                        const storagePath = getMediaStoragePath(item);
                        if (!storagePath) return;
                        const file = bucket.file(storagePath);

                        await file.setMetadata({
                            metadata: {
                                postId: postRef.id,
                            },
                        });
                        console.log(`Updated metadata: ${storagePath} → postId=${postRef.id}`);
                    } catch (metadataError) {
                        console.error(`Failed to update metadata for ${item.url}:`, metadataError);
                    }
                }));
                await deletePendingMediaByStoragePaths(mediaStoragePaths);
            }

            if (circleId) {
                try {
                    const now = new Date();
                    await db.collection("circles").doc(circleId).update({
                        postCount: FieldValue.increment(1),
                        recentActivity: FieldValue.serverTimestamp(),
                        lastHumanPostAt: FieldValue.serverTimestamp(),
                        ghostWarningNotifiedAt: FieldValue.delete(),
                        nextGhostCheckAt: Timestamp.fromDate(computeNextGhostCheckAt({
                            createdAt: now,
                            lastHumanPostAt: now,
                            ghostWarningNotifiedAt: null,
                        })),
                    });
                } catch (error) {
                    console.error("Failed to update circle counters:", error);
                }
            }

            // ユーザーの投稿数を更新
            try {
                await db.collection("users").doc(userId).update({
                    totalPosts: FieldValue.increment(1),
                });
            } catch (error) {
                console.error("Failed to update user post count:", error);
            }

            if (shouldGrantVirtue) {
                try {
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
                } catch (error) {
                    console.error("Failed to grant post virtue:", error);
                }
            }

            if (postRequestRef) {
                await markPostRequestSucceeded(postRequestRef, postRef.id);
            }

            console.log(`=== createPostWithModeration SUCCESS: postId=${postRef.id} ===`);
            return { success: true, postId: postRef.id };
        } catch (error) {
            if (error instanceof HttpsError &&
                TERMINAL_POST_REQUEST_ERROR_CODES.has(error.code) &&
                requestMediaItems.length > 0) {
                await deleteUploadedMedia(requestMediaItems);
            }

            if (postRequestRef) {
                if (error instanceof HttpsError &&
                    TERMINAL_POST_REQUEST_ERROR_CODES.has(error.code)) {
                    await markPostRequestRejected(
                        postRequestRef,
                        error.code,
                        error.message || SYSTEM_ERRORS.INTERNAL
                    );
                } else {
                    await clearPostRequest(postRequestRef);
                }
            }
            throw error;
        }
    }
);

export const createPostWithModeration = onCall(
    {
        region: LOCATION,
        secrets: [geminiApiKey, openaiApiKey],
        timeoutSeconds: 60,
        memory: "1GiB",
        enforceAppCheck: true,
    },
    async (request) => {
        console.log("=== createPostWithModeration START ===");

        const userId = requireAuth(request);
        const {
            content,
            userDisplayName,
            userAvatarIndex,
            postMode,
            circleId,
            mediaItems,
            clientRequestId,
            sourcePostId,
            grantVirtue: grantVirtueFlag,
        } = request.data;
        const normalizedClientRequestId =
            typeof clientRequestId === "string" ? clientRequestId.trim() : "";
        const normalizedSourcePostId =
            typeof sourcePostId === "string" ? sourcePostId.trim() : "";
        const requestMediaItems = Array.isArray(mediaItems) ? mediaItems as MediaItem[] : [];
        const mediaStoragePaths = getMediaStoragePaths(requestMediaItems);
        const storedMediaItems = requestMediaItems.map((item) => toStoredMediaItem(item));
        const shouldGrantVirtue = grantVirtueFlag !== false;
        const moderationAttemptId = buildModerationAttemptId(normalizedClientRequestId);
        let postRequestRef: FirebaseFirestore.DocumentReference | null = null;
        let createdPostRef: FirebaseFirestore.DocumentReference | null = null;
        let reusedRejectedPostRef: FirebaseFirestore.DocumentReference | null = null;
        let reusedRejectedPostPreviousData: FirebaseFirestore.DocumentData | null = null;
        let removedRejectedMediaStoragePaths: string[] = [];
        let newUploadedStoragePathsForReuse: string[] = [];
        let updatedExistingRejectedPost = false;
        let moderationTasksScheduled = false;

        if (normalizedClientRequestId) {
            const postRequest = await beginPostRequest(userId, normalizedClientRequestId);
            switch (postRequest.kind) {
            case "succeeded":
                return { success: true, postId: postRequest.postId };
            case "rejected":
                throw new HttpsError(
                    postRequest.code as ConstructorParameters<typeof HttpsError>[0],
                    postRequest.message
                );
            case "processing":
                throw new HttpsError("aborted", VALIDATION_ERRORS.POST_REQUEST_IN_PROGRESS);
            case "continue":
                postRequestRef = postRequest.ref;
                break;
            }
        }

        try {
            await enforcePostRateLimits(userId);

            if (typeof content === "string" && [...content].length > 220) {
                throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
            }

            if (requestMediaItems.some((item: { type?: string; mimeType?: string }) =>
                item.type === "video" || (typeof item.mimeType === "string" && item.mimeType.startsWith("video/"))
            )) {
                throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
            }

            const userDoc = await db.collection("users").doc(userId).get();
            if (userDoc.exists && userDoc.data()?.isBanned) {
                throw new HttpsError("permission-denied", AUTH_ERRORS.BANNED);
            }

            const geminiKey = geminiApiKey.value() || "";
            const openaiKey = openaiApiKey.value() || "";
            if (!geminiKey && !openaiKey) {
                throw new HttpsError("internal", SYSTEM_ERRORS.INTERNAL);
            }

            let processingPostRef: FirebaseFirestore.DocumentReference;

            if (normalizedSourcePostId) {
                const sourcePostRef = db.collection("posts").doc(normalizedSourcePostId);
                const sourcePostSnap = await sourcePostRef.get();
                if (!sourcePostSnap.exists) {
                    throw new HttpsError("not-found", RESOURCE_ERRORS.POST_NOT_FOUND);
                }

                const sourcePostData = sourcePostSnap.data() || {};
                if (sourcePostData.userId !== userId) {
                    throw new HttpsError("permission-denied", VALIDATION_ERRORS.INVALID_ARGUMENT);
                }
                if (sourcePostData.moderationStatus !== POST_MODERATION_STATUS_REJECTED) {
                    throw new HttpsError("failed-precondition", VALIDATION_ERRORS.INVALID_ARGUMENT);
                }

                const previousMediaItems = parseStoredMediaItems(
                    sourcePostData.mediaItems,
                    sourcePostData.mediaStoragePaths
                );
                const previousStoragePaths = getMediaStoragePaths(previousMediaItems);
                const previousStoragePathSet = new Set(previousStoragePaths);
                const nextStoragePathSet = new Set(mediaStoragePaths);

                removedRejectedMediaStoragePaths = previousStoragePaths
                    .filter((storagePath) => !nextStoragePathSet.has(storagePath));
                newUploadedStoragePathsForReuse = mediaStoragePaths
                    .filter((storagePath) => !previousStoragePathSet.has(storagePath));

                reusedRejectedPostRef = sourcePostRef;
                reusedRejectedPostPreviousData = sourcePostData;
                createdPostRef = sourcePostRef;

                await sourcePostRef.update({
                    userId,
                    userDisplayName,
                    userAvatarIndex,
                    content,
                    mediaItems: storedMediaItems,
                    mediaStoragePaths,
                    postMode,
                    circleId: circleId || null,
                    ...(normalizedClientRequestId ?
                        { clientRequestId: normalizedClientRequestId } :
                        { clientRequestId: FieldValue.delete() }),
                    createdAt: FieldValue.serverTimestamp(),
                    reactions: { love: 0, praise: 0, cheer: 0, empathy: 0 },
                    commentCount: 0,
                    isPinned: false,
                    isPinnedTop: false,
                    isVisible: false,
                    moderationStatus: POST_MODERATION_STATUS_PROCESSING,
                    moderationReason: "",
                    moderationCompletedAt: null,
                    moderationAttemptId,
                    ownerVisibleUntil: null,
                    needsReview: false,
                    needsReviewReason: "",
                    publishSideEffectsPending: false,
                    moderationSideEffectsPending: false,
                    moderationSideEffectsKind: null,
                    grantVirtueOnPublish: shouldGrantVirtue,
                });
                updatedExistingRejectedPost = true;
                processingPostRef = sourcePostRef;
            } else {
                createdPostRef = db.collection("posts").doc();
                await createdPostRef.set({
                    userId,
                    userDisplayName,
                    userAvatarIndex,
                    content,
                    mediaItems: storedMediaItems,
                    mediaStoragePaths,
                    postMode,
                    circleId: circleId || null,
                    ...(normalizedClientRequestId ? { clientRequestId: normalizedClientRequestId } : {}),
                    createdAt: FieldValue.serverTimestamp(),
                    reactions: { love: 0, praise: 0, cheer: 0, empathy: 0 },
                    commentCount: 0,
                    isVisible: false,
                    moderationStatus: POST_MODERATION_STATUS_PROCESSING,
                    moderationReason: "",
                    moderationCompletedAt: null,
                    moderationAttemptId,
                    ownerVisibleUntil: null,
                    needsReview: false,
                    needsReviewReason: "",
                    publishSideEffectsPending: false,
                    moderationSideEffectsPending: false,
                    moderationSideEffectsKind: null,
                    grantVirtueOnPublish: shouldGrantVirtue,
                });
                processingPostRef = createdPostRef;
            }

            try {
                await schedulePostModerationTask(processingPostRef.id, moderationAttemptId);
                await schedulePostModerationTimeoutTask(processingPostRef.id, moderationAttemptId);
                moderationTasksScheduled = true;
            } catch (taskError) {
                console.error(`Failed to schedule post moderation task: postId=${processingPostRef.id}`, taskError);
                if (reusedRejectedPostRef && reusedRejectedPostPreviousData && updatedExistingRejectedPost) {
                    await reusedRejectedPostRef.set(reusedRejectedPostPreviousData).catch((restoreError) => {
                        console.error(`Failed to restore rejected post after task enqueue failure: ${processingPostRef.id}`, restoreError);
                    });
                    updatedExistingRejectedPost = false;
                } else {
                    await processingPostRef.delete().catch((deleteError) => {
                        console.error(`Failed to delete processing post after task enqueue failure: ${processingPostRef.id}`, deleteError);
                    });
                    createdPostRef = null;
                }
                if (newUploadedStoragePathsForReuse.length > 0) {
                    await deleteStoragePathsBestEffort(newUploadedStoragePathsForReuse);
                } else if (requestMediaItems.length > 0) {
                    await deleteUploadedMedia(requestMediaItems);
                }
                throw new HttpsError("internal", SYSTEM_ERRORS.INTERNAL);
            }

            if (removedRejectedMediaStoragePaths.length > 0) {
                await deleteStoragePathsBestEffort(removedRejectedMediaStoragePaths);
            }

            if (postRequestRef) {
                await markPostRequestSucceeded(postRequestRef, processingPostRef.id);
            }

            console.log(`=== createPostWithModeration ACCEPTED: postId=${processingPostRef.id} ===`);
            return { success: true, postId: processingPostRef.id };
        } catch (error) {
            if (!moderationTasksScheduled &&
                updatedExistingRejectedPost &&
                reusedRejectedPostRef &&
                reusedRejectedPostPreviousData) {
                await reusedRejectedPostRef.set(reusedRejectedPostPreviousData).catch((restoreError) => {
                    console.error(`Failed to restore rejected post after createPostWithModeration error: ${reusedRejectedPostRef?.id}`, restoreError);
                });
                updatedExistingRejectedPost = false;
                if (newUploadedStoragePathsForReuse.length > 0) {
                    await deleteStoragePathsBestEffort(newUploadedStoragePathsForReuse);
                }
            } else if (error instanceof HttpsError &&
                TERMINAL_POST_REQUEST_ERROR_CODES.has(error.code) &&
                requestMediaItems.length > 0 &&
                !reusedRejectedPostRef) {
                await deleteUploadedMedia(requestMediaItems);
            }

            if (!(error instanceof HttpsError) && createdPostRef && !reusedRejectedPostRef) {
                const postRefToDelete = createdPostRef;
                await postRefToDelete.delete().catch((deleteError) => {
                    console.error(`Failed to delete processing post after unexpected error: ${postRefToDelete.id}`, deleteError);
                });
            }

            if (postRequestRef) {
                if (error instanceof HttpsError &&
                    TERMINAL_POST_REQUEST_ERROR_CODES.has(error.code)) {
                    await markPostRequestRejected(
                        postRequestRef,
                        error.code,
                        error.message || SYSTEM_ERRORS.INTERNAL
                    );
                } else {
                    await clearPostRequest(postRequestRef);
                }
            }

            throw error;
        }
    }
);

export const executePostModeration = onRequest(
    {
        region: LOCATION,
        secrets: [geminiApiKey, openaiApiKey],
        timeoutSeconds: 120,
        memory: "1GiB",
    },
    async (request, response) => {
        if (request.method !== "POST") {
            response.status(405).json({ success: false, error: "Method Not Allowed" });
            return;
        }

        const isAuthorized = await verifyCloudTasksRequest(
            request,
            CLOUD_TASK_FUNCTIONS.executePostModeration
        );
        if (!isAuthorized) {
            response.status(401).json({ success: false, error: "Unauthorized" });
            return;
        }

        const postId = typeof request.body?.postId === "string" ? request.body.postId : "";
        const moderationAttemptId =
            typeof request.body?.moderationAttemptId === "string" ? request.body.moderationAttemptId : "";
        if (!postId || !moderationAttemptId) {
            response.status(400).json({ success: false, error: "postId and moderationAttemptId are required" });
            return;
        }

        try {
            const postRef = db.collection("posts").doc(postId);
            const postSnap = await postRef.get();
            if (!postSnap.exists) {
                response.status(200).json({ success: true, status: "missing" });
                return;
            }

            const postData = postSnap.data() || {};
            const currentAttemptId = typeof postData.moderationAttemptId === "string" ?
                postData.moderationAttemptId :
                "";
            if (currentAttemptId && currentAttemptId !== moderationAttemptId) {
                response.status(200).json({ success: true, status: "stale_attempt" });
                return;
            }
            const moderationStatus = typeof postData.moderationStatus === "string" ?
                postData.moderationStatus :
                POST_MODERATION_STATUS_APPROVED;

            if (moderationStatus === POST_MODERATION_STATUS_APPROVED) {
                if (postData.publishSideEffectsPending === true) {
                    await finalizeApprovedPost({ postRef, postId });
                    response.status(200).json({ success: true, status: "approved_finalized" });
                    return;
                }
                response.status(200).json({ success: true, status: "already_approved" });
                return;
            }

            if (moderationStatus === POST_MODERATION_STATUS_REJECTED) {
                if (postData.moderationSideEffectsPending === true) {
                    await finalizeRejectedPost({ postRef, postId });
                    response.status(200).json({ success: true, status: "rejected_finalized" });
                    return;
                }
                response.status(200).json({ success: true, status: moderationStatus });
                return;
            }

            if (moderationStatus === POST_MODERATION_STATUS_REVIEW_NEEDED) {
                if (postData.moderationSideEffectsPending === true) {
                    await finalizeReviewNeededPost({ postRef, postId });
                    response.status(200).json({ success: true, status: "review_needed_finalized" });
                    return;
                }
                response.status(200).json({ success: true, status: moderationStatus });
                return;
            }

            const userId = typeof postData.userId === "string" ? postData.userId : "";
            if (!userId) {
                throw new Error(`Post ${postId} is missing userId`);
            }

            const postCircleId = typeof postData.circleId === "string" ? postData.circleId : null;
            const contentBody = typeof postData.content === "string" ? postData.content : "";
            const mediaItems = parseStoredMediaItems(postData.mediaItems, postData.mediaStoragePaths);

            let needsReview = false;
            let needsReviewReason = "";

            const userIsAdmin = await isAdmin(userId);
            if (userIsAdmin && mediaItems.length > 0) {
                needsReview = true;
                needsReviewReason = MODERATION_MESSAGES.TEST_ADMIN_MEDIA;
            }

            if (!needsReview && contentBody) {
                try {
                    const textOutcome = await moderateText({
                        type: "post",
                        userId,
                        contentDescription: "投稿内容",
                        contentBody,
                    });
                    if (textOutcome.flagged) {
                        needsReview = true;
                        needsReviewReason = textOutcome.flagReason || "";
                    }
                } catch (error) {
                    if (error instanceof HttpsError && error.code === "invalid-argument") {
                        await markPostRejected({
                            postRef,
                            reason: error.message,
                        });
                        await finalizeRejectedPost({ postRef, postId });
                        response.status(200).json({ success: true, status: POST_MODERATION_STATUS_REJECTED });
                        return;
                    }
                    throw error;
                }
            }

            if (needsReview) {
                await markPostReviewNeeded({
                    postRef,
                    reason: needsReviewReason,
                });
                await finalizeReviewNeededPost({ postRef, postId });
                response.status(200).json({ success: true, status: POST_MODERATION_STATUS_REVIEW_NEEDED });
                return;
            }

            if (mediaItems.length > 0) {
                const aiFactory = createAIProviderFactory();
                const mediaResult = await moderateMedia(aiFactory, mediaItems);
                if (!mediaResult.passed && mediaResult.result) {
                    if (mediaResult.result.confidence >= 0.7) {
                        const categoryLabels: Record<string, string> = {
                            adult: LABELS.CONTENT_ADULT,
                            violence: LABELS.CONTENT_VIOLENCE,
                            hate: LABELS.CONTENT_HATE,
                            dangerous: LABELS.CONTENT_DANGEROUS,
                        };
                        const categoryLabel =
                            categoryLabels[mediaResult.result.category] || LABELS.CONTENT_INAPPROPRIATE;
                        await markPostRejected({
                            postRef,
                            reason: MODERATION_MESSAGES.mediaBlockedSimple("image", categoryLabel),
                        });
                        await finalizeRejectedPost({ postRef, postId });
                        response.status(200).json({ success: true, status: POST_MODERATION_STATUS_REJECTED });
                        return;
                    }

                    await markPostReviewNeeded({
                        postRef,
                        reason: `メディア: ${mediaResult.result.category} (confidence: ${mediaResult.result.confidence})`,
                    });
                    await finalizeReviewNeededPost({ postRef, postId });
                    response.status(200).json({ success: true, status: POST_MODERATION_STATUS_REVIEW_NEEDED });
                    return;
                }
            }

            await approvePostAndApplyCounters({
                postRef,
                userId,
                circleId: postCircleId,
            });
            await finalizeApprovedPost({ postRef, postId });

            response.status(200).json({ success: true, status: POST_MODERATION_STATUS_APPROVED });
        } catch (error) {
            console.error(`executePostModeration failed: postId=${postId}, attempt=${moderationAttemptId}`, error);
            response.status(500).json({ success: false, error: SYSTEM_ERRORS.INTERNAL });
        }
    }
);

export const checkPostModerationTimeout = onRequest(
    {
        region: LOCATION,
        timeoutSeconds: 60,
        memory: "512MiB",
    },
    async (request, response) => {
        if (request.method !== "POST") {
            response.status(405).json({ success: false, error: "Method Not Allowed" });
            return;
        }

        const isAuthorized = await verifyCloudTasksRequest(
            request,
            CLOUD_TASK_FUNCTIONS.checkPostModerationTimeout
        );
        if (!isAuthorized) {
            response.status(401).json({ success: false, error: "Unauthorized" });
            return;
        }

        const postId = typeof request.body?.postId === "string" ? request.body.postId : "";
        const moderationAttemptId =
            typeof request.body?.moderationAttemptId === "string" ? request.body.moderationAttemptId : "";
        if (!postId || !moderationAttemptId) {
            response.status(400).json({ success: false, error: "postId and moderationAttemptId are required" });
            return;
        }

        try {
            const postRef = db.collection("posts").doc(postId);
            const postSnap = await postRef.get();
            if (!postSnap.exists) {
                response.status(200).json({ success: true, status: "missing" });
                return;
            }

            const postData = postSnap.data() || {};
            const currentAttemptId = typeof postData.moderationAttemptId === "string" ?
                postData.moderationAttemptId :
                "";
            if (currentAttemptId && currentAttemptId !== moderationAttemptId) {
                response.status(200).json({ success: true, status: "stale_attempt" });
                return;
            }
            const moderationStatus = typeof postData.moderationStatus === "string" ?
                postData.moderationStatus :
                POST_MODERATION_STATUS_APPROVED;
            if (moderationStatus === POST_MODERATION_STATUS_REVIEW_NEEDED &&
                postData.moderationSideEffectsPending === true) {
                await finalizeReviewNeededPost({ postRef, postId });
                response.status(200).json({ success: true, status: "review_needed_finalized" });
                return;
            }
            if (moderationStatus !== POST_MODERATION_STATUS_PROCESSING) {
                response.status(200).json({ success: true, status: moderationStatus });
                return;
            }

            const createdAt = postData.createdAt instanceof Timestamp ?
                postData.createdAt.toDate() :
                null;
            if (createdAt && createdAt.getTime() > Date.now() - POST_MODERATION_TIMEOUT_MS) {
                response.status(200).json({ success: true, status: "processing_recent" });
                return;
            }

            await markPostReviewNeeded({
                postRef,
                reason: MODERATION_MESSAGES.POST_REVIEW_TIMEOUT,
            });
            await finalizeReviewNeededPost({ postRef, postId });

            response.status(200).json({ success: true, status: POST_MODERATION_STATUS_REVIEW_NEEDED });
        } catch (error) {
            console.error(`checkPostModerationTimeout failed: postId=${postId}, attempt=${moderationAttemptId}`, error);
            response.status(500).json({ success: false, error: SYSTEM_ERRORS.INTERNAL });
        }
    }
);

export const cleanupRejectedPost = onRequest(
    {
        region: LOCATION,
        timeoutSeconds: 120,
        memory: "512MiB",
    },
    async (request, response) => {
        if (request.method !== "POST") {
            response.status(405).json({ success: false, error: "Method Not Allowed" });
            return;
        }

        const isAuthorized = await verifyCloudTasksRequest(
            request,
            CLOUD_TASK_FUNCTIONS.cleanupRejectedPost
        );
        if (!isAuthorized) {
            response.status(401).json({ success: false, error: "Unauthorized" });
            return;
        }

        const postId = typeof request.body?.postId === "string" ? request.body.postId : "";
        if (!postId) {
            response.status(400).json({ success: false, error: "postId is required" });
            return;
        }

        try {
            await cleanupRejectedPostDocument(postId);
            response.status(200).json({ success: true });
        } catch (error) {
            console.error(`cleanupRejectedPost failed: postId=${postId}`, error);
            response.status(500).json({ success: false, error: SYSTEM_ERRORS.INTERNAL });
        }
    }
);

export const approveReviewedPost = onCall(
    {
        region: LOCATION,
        timeoutSeconds: 60,
        memory: "512MiB",
        enforceAppCheck: true,
    },
    async (request) => {
        const adminId = await requireAdmin(request);
        const { postId, reviewId } = request.data || {};

        if (!postId || typeof postId !== "string" || !reviewId || typeof reviewId !== "string") {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.MISSING_REQUIRED);
        }

        const postRef = db.collection("posts").doc(postId);
        const postSnap = await postRef.get();
        if (!postSnap.exists) {
            throw new HttpsError("not-found", VALIDATION_ERRORS.INVALID_ARGUMENT);
        }

        const postData = postSnap.data() || {};
        const userId = typeof postData.userId === "string" ? postData.userId : "";
        if (!userId) {
            throw new HttpsError("failed-precondition", SYSTEM_ERRORS.PROCESSING_ERROR);
        }

        await approvePostAndApplyCounters({
            postRef,
            userId,
            circleId: typeof postData.circleId === "string" ? postData.circleId : null,
            allowedStatuses: [
                POST_MODERATION_STATUS_PROCESSING,
                POST_MODERATION_STATUS_REVIEW_NEEDED,
            ],
        });
        await finalizeApprovedPost({ postRef, postId });

        await db.collection("pendingReviews").doc(reviewId).set({
            reviewed: true,
            reviewedAt: FieldValue.serverTimestamp(),
            action: "approved",
            reviewedBy: adminId,
        }, { merge: true });

        return { success: true, postId };
    }
);
