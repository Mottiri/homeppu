/**
 * 管理者関連関数
 * Phase 7: index.ts から分離
 */

import * as admin from "firebase-admin";
import * as functionsV1 from "firebase-functions/v1";
import { onCall, HttpsError } from "firebase-functions/v2/https";

import { db } from "../helpers/firebase";
import { isAdmin } from "../helpers/admin";
import { LOCATION } from "../config/constants";
import {
    AUTH_ERRORS,
    RESOURCE_ERRORS,
    VALIDATION_ERRORS,
    SYSTEM_ERRORS,
    NOTIFICATION_TITLES,
    SUCCESS_MESSAGES,
} from "../config/messages";

/**
 * 管理用: 全ユーザーのフォローリストを掃除する
 */
export const cleanUpUserFollows = onCall(
    { region: LOCATION, timeoutSeconds: 540 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", AUTH_ERRORS.UNAUTHENTICATED);
        }
        const userIsAdmin = await isAdmin(request.auth.uid);
        if (!userIsAdmin) {
            throw new HttpsError("permission-denied", AUTH_ERRORS.ADMIN_REQUIRED);
        }

        try {
            const usersSnapshot = await db.collection("users").get();
            let updatedCount = 0;

            for (const userDoc of usersSnapshot.docs) {
                const userData = userDoc.data();
                const following = userData.following || [];

                if (following.length === 0) continue;

                const validFollowing: string[] = [];
                const invalidFollowing: string[] = [];

                for (const followedId of following) {
                    if (followedId.trim() !== followedId) {
                        invalidFollowing.push(followedId);
                        continue;
                    }

                    const followedUserDoc = await db.collection("users").doc(followedId).get();
                    if (followedUserDoc.exists) {
                        validFollowing.push(followedId);
                    } else {
                        invalidFollowing.push(followedId);
                    }
                }

                if (invalidFollowing.length > 0) {
                    await userDoc.ref.update({
                        following: validFollowing,
                        followingCount: validFollowing.length
                    });
                    updatedCount++;
                    console.log(`Cleaned up user ${userDoc.id}: Removed ${invalidFollowing.length} invalid follows.`);
                }
            }

            console.log(`cleanUpUserFollows completed by admin ${request.auth.uid}. Updated ${updatedCount} users.`);
            return { success: true, updatedCount, message: SUCCESS_MESSAGES.usersUpdated(updatedCount) };

        } catch (error) {
            console.error("Error cleaning up follows:", error);
            throw new HttpsError("internal", SYSTEM_ERRORS.PROCESSING_ERROR);
        }
    }
);

/**
 * 管理用: 全てのAIユーザーを削除する (v1)
 */
export const deleteAllAIUsers = functionsV1.region(LOCATION).runWith({
    timeoutSeconds: 540,
    memory: "1GB"
}).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functionsV1.https.HttpsError("unauthenticated", AUTH_ERRORS.UNAUTHENTICATED);
    }

    const userIsAdmin = await isAdmin(context.auth.uid);
    if (!userIsAdmin) {
        throw new functionsV1.https.HttpsError("permission-denied", AUTH_ERRORS.ADMIN_REQUIRED);
    }

    try {
        console.log("Starting deletion of all AI users...");
        const batchSize = 400;
        let batch = db.batch();
        let operationCount = 0;

        const aiUsersSnapshot = await db.collection("users").where("isAI", "==", true).get();
        console.log(`Found ${aiUsersSnapshot.size} AI users to delete.`);

        if (aiUsersSnapshot.empty) {
            return { success: true, message: SUCCESS_MESSAGES.NO_AI_USERS };
        }

        const aiUserIds = aiUsersSnapshot.docs.map(doc => doc.id);

        const commitBatchIfNeeded = async () => {
            if (operationCount >= batchSize) {
                await batch.commit();
                batch = db.batch();
                operationCount = 0;
            }
        };

        const deleteCollectionByUserId = async (collectionName: string) => {
            const chunkSize = 10;
            for (let i = 0; i < aiUserIds.length; i += chunkSize) {
                const chunk = aiUserIds.slice(i, i + chunkSize);
                const snapshot = await db.collection(collectionName).where("userId", "in", chunk).get();

                for (const doc of snapshot.docs) {
                    batch.delete(doc.ref);
                    operationCount++;
                    await commitBatchIfNeeded();
                }
            }
        };

        console.log("Deleting AI posts...");
        await deleteCollectionByUserId("posts");

        console.log("Deleting AI comments...");
        await deleteCollectionByUserId("comments");

        console.log("Deleting AI reactions...");
        await deleteCollectionByUserId("reactions");

        console.log("Deleting AI user profiles and subcollections...");
        for (const doc of aiUsersSnapshot.docs) {
            const notificationsSnapshot = await doc.ref.collection("notifications").get();
            for (const notifDoc of notificationsSnapshot.docs) {
                batch.delete(notifDoc.ref);
                operationCount++;
                await commitBatchIfNeeded();
            }

            batch.delete(doc.ref);
            operationCount++;
            await commitBatchIfNeeded();
        }

        if (operationCount > 0) {
            await batch.commit();
        }

        console.log("Successfully deleted all AI data.");
        return { success: true, message: SUCCESS_MESSAGES.aiUsersDeleted(aiUsersSnapshot.size) };

    } catch (error) {
        console.error("Error deleting AI users:", error);
        throw new functionsV1.https.HttpsError("internal", SYSTEM_ERRORS.DELETE_ERROR);
    }
});

/**
 * 孤児サークルAI（サブコレクションのみ残っている状態）を一括削除
 */
export const cleanupOrphanedCircleAIs = onCall(
    { region: LOCATION, timeoutSeconds: 300 },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", AUTH_ERRORS.UNAUTHENTICATED);
        }
        const userIsAdmin = await isAdmin(request.auth.uid);
        if (!userIsAdmin) {
            throw new HttpsError("permission-denied", AUTH_ERRORS.ADMIN_REQUIRED);
        }

        console.log("=== cleanupOrphanedCircleAIs START ===");

        const circleAIsSnapshot = await db.collection("users")
            .where("__name__", ">=", "circle_ai_")
            .where("__name__", "<", "circle_ai_\uf8ff")
            .get();

        let deletedCount = 0;
        let notificationCount = 0;

        for (const doc of circleAIsSnapshot.docs) {
            const userId = doc.id;
            const userRef = db.collection("users").doc(userId);

            const notificationsSnapshot = await userRef.collection("notifications").get();
            if (!notificationsSnapshot.empty) {
                const batch = db.batch();
                notificationsSnapshot.docs.forEach(notifDoc => batch.delete(notifDoc.ref));
                await batch.commit();
                notificationCount += notificationsSnapshot.size;
            }

            await userRef.delete();
            deletedCount++;
            console.log(`Deleted circle AI: ${userId}`);
        }

        console.log(`=== cleanupOrphanedCircleAIs COMPLETE: ${deletedCount} users, ${notificationCount} notifications ===`);
        return {
            success: true,
            message: SUCCESS_MESSAGES.orphanAIsDeleted(deletedCount, notificationCount),
            deletedUsers: deletedCount,
            deletedNotifications: notificationCount,
        };
    }
);

/**
 * 管理者権限を設定（既存の管理者のみが実行可能）
 */
export const setAdminRole = onCall(async (request) => {
    const callerId = request.auth?.uid;
    if (!callerId) {
        throw new HttpsError("unauthenticated", AUTH_ERRORS.UNAUTHENTICATED_ALT);
    }

    const callerIsAdmin = await isAdmin(callerId);
    if (!callerIsAdmin) {
        throw new HttpsError("permission-denied", AUTH_ERRORS.ADMIN_REQUIRED);
    }

    const { targetUid } = request.data;
    if (!targetUid || typeof targetUid !== "string") {
        throw new HttpsError("invalid-argument", VALIDATION_ERRORS.TARGET_USER_ID_REQUIRED);
    }

    try {
        await admin.auth().setCustomUserClaims(targetUid, { admin: true });
        console.log(`Admin role granted to user: ${targetUid} by ${callerId}`);

        return { success: true, message: SUCCESS_MESSAGES.adminSet(targetUid) };
    } catch (error) {
        console.error(`Error setting admin role for ${targetUid}:`, error);
        throw new HttpsError("internal", SYSTEM_ERRORS.ADMIN_SET_FAILED);
    }
});

/**
 * 管理者権限を削除（既存の管理者のみが実行可能）
 */
export const removeAdminRole = onCall(async (request) => {
    const callerId = request.auth?.uid;
    if (!callerId) {
        throw new HttpsError("unauthenticated", AUTH_ERRORS.UNAUTHENTICATED_ALT);
    }

    const callerIsAdmin = await isAdmin(callerId);
    if (!callerIsAdmin) {
        throw new HttpsError("permission-denied", AUTH_ERRORS.ADMIN_REQUIRED);
    }

    const { targetUid } = request.data;
    if (!targetUid || typeof targetUid !== "string") {
        throw new HttpsError("invalid-argument", VALIDATION_ERRORS.TARGET_USER_ID_REQUIRED);
    }

    if (callerId === targetUid) {
        throw new HttpsError("invalid-argument", VALIDATION_ERRORS.SELF_ADMIN_REMOVE_NOT_ALLOWED);
    }

    try {
        const user = await admin.auth().getUser(targetUid);
        const claims = user.customClaims || {};
        delete claims.admin;
        await admin.auth().setCustomUserClaims(targetUid, claims);

        console.log(`Admin role removed from user: ${targetUid} by ${callerId}`);

        return { success: true, message: SUCCESS_MESSAGES.adminRemoved(targetUid) };
    } catch (error) {
        console.error(`Error removing admin role for ${targetUid}:`, error);
        throw new HttpsError("internal", SYSTEM_ERRORS.ADMIN_REMOVE_FAILED);
    }
});

/**
 * ユーザーを一時BANにする
 */
export const banUser = onCall(
    { region: LOCATION },
    async (request) => {
        if (!request.auth?.token.admin) {
            throw new HttpsError("permission-denied", AUTH_ERRORS.ADMIN_REQUIRED);
        }

        const { userId, reason } = request.data;
        if (!userId || !reason) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.USER_ID_AND_REASON_REQUIRED);
        }

        if (userId === request.auth.uid) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.SELF_BAN_NOT_ALLOWED);
        }

        const userDoc = await db.collection("users").doc(userId).get();
        if (!userDoc.exists) {
            throw new HttpsError("not-found", RESOURCE_ERRORS.USER_NOT_FOUND);
        }

        const banRecord = {
            type: "temporary",
            reason: reason,
            bannedAt: admin.firestore.Timestamp.now(),
            bannedBy: request.auth.uid,
        };

        const batch = db.batch();

        batch.update(userDoc.ref, {
            banStatus: "temporary",
            isBanned: true,
            banHistory: admin.firestore.FieldValue.arrayUnion(banRecord),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const notificationRef = db.collection("users").doc(userId).collection("notifications").doc();
        batch.set(notificationRef, {
            userId: userId,
            type: "user_banned",
            title: NOTIFICATION_TITLES.ACCOUNT_SUSPENDED,
            body: `規約違反のため、アカウント機能の一部を制限しました。理由: ${reason}`,
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        await batch.commit();

        await admin.auth().setCustomUserClaims(userId, { banned: true, banStatus: 'temporary' });

        console.log(`User ${userId} temporarily banned by ${request.auth.uid}`);
        return { success: true };
    }
);

/**
 * ユーザーを永久BANにする
 */
export const permanentBanUser = onCall(
    { region: LOCATION },
    async (request) => {
        if (!request.auth?.token.admin) {
            throw new HttpsError("permission-denied", AUTH_ERRORS.ADMIN_REQUIRED);
        }

        const { userId, reason } = request.data;
        if (!userId || !reason) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.USER_ID_AND_REASON_REQUIRED);
        }

        if (userId === request.auth.uid) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.SELF_BAN_NOT_ALLOWED);
        }

        const banRecord = {
            type: "permanent",
            reason: reason,
            bannedAt: admin.firestore.Timestamp.now(),
            bannedBy: request.auth.uid,
        };

        const batch = db.batch();

        const deletionDate = new Date();
        deletionDate.setDate(deletionDate.getDate() + 180);

        batch.update(db.collection("users").doc(userId), {
            banStatus: "permanent",
            isBanned: true,
            banHistory: admin.firestore.FieldValue.arrayUnion(banRecord),
            permanentBanScheduledDeletionAt: admin.firestore.Timestamp.fromDate(deletionDate),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const notificationRef = db.collection("users").doc(userId).collection("notifications").doc();
        batch.set(notificationRef, {
            userId: userId,
            type: "user_banned",
            title: NOTIFICATION_TITLES.ACCOUNT_PERMANENTLY_BANNED,
            body: `規約違反のため、アカウントを永久停止しました。理由: ${reason}`,
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        await batch.commit();

        try {
            await admin.auth().updateUser(userId, { disabled: true });
            await admin.auth().revokeRefreshTokens(userId);
            await admin.auth().setCustomUserClaims(userId, { banned: true, banStatus: 'permanent' });
        } catch (e) {
            console.warn(`Auth update failed for ${userId}:`, e);
        }

        console.log(`User ${userId} permanently banned by ${request.auth.uid}`);
        return { success: true };
    }
);

/**
 * BANを解除する
 */
export const unbanUser = onCall(
    { region: LOCATION },
    async (request) => {
        if (!request.auth?.token.admin) {
            throw new HttpsError("permission-denied", AUTH_ERRORS.ADMIN_REQUIRED);
        }

        const { userId } = request.data;
        if (!userId) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.USER_ID_ONLY_REQUIRED);
        }

        const batch = db.batch();

        batch.update(db.collection("users").doc(userId), {
            banStatus: "none",
            isBanned: false,
            permanentBanScheduledDeletionAt: admin.firestore.FieldValue.delete(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const notificationRef = db.collection("users").doc(userId).collection("notifications").doc();
        batch.set(notificationRef, {
            userId: userId,
            type: "user_unbanned",
            title: NOTIFICATION_TITLES.ACCOUNT_RESTRICTION_LIFTED,
            body: `アカウントの制限が解除されました。`,
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        await batch.commit();

        // banAppealsの削除
        try {
            const appealsSnapshot = await db.collection("banAppeals")
                .where("bannedUserId", "==", userId)
                .get();

            if (!appealsSnapshot.empty) {
                const deleteBatch = db.batch();
                appealsSnapshot.docs.forEach(doc => {
                    deleteBatch.delete(doc.ref);
                });
                await deleteBatch.commit();
                console.log(`Deleted ${appealsSnapshot.size} ban appeal(s) for user ${userId}`);
            }
        } catch (e) {
            console.warn(`Failed to delete ban appeals for ${userId}:`, e);
        }

        // Auth有効化
        try {
            await admin.auth().updateUser(userId, { disabled: false });
            const userRecord = await admin.auth().getUser(userId);
            const currentClaims = userRecord.customClaims || {};
            delete currentClaims.banned;
            delete currentClaims.banStatus;
            await admin.auth().setCustomUserClaims(userId, currentClaims);
        } catch (e) {
            console.warn(`Auth update failed for ${userId}:`, e);
        }

        console.log(`User ${userId} unbanned by ${request.auth.uid}`);
        return { success: true };
    }
);
