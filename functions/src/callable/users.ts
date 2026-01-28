/**
 * ユーザー関連のCallable関数
 * Phase 6: index.ts から分離
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

import { db } from "../helpers/firebase";
import { requireAuth } from "../helpers/auth";
import { VIRTUE_CONFIG } from "../helpers/virtue";
import { LOCATION } from "../config/constants";
import { AUTH_ERRORS, RESOURCE_ERRORS, VALIDATION_ERRORS } from "../config/messages";

/**
 * ユーザーをフォローする
 */
export const followUser = onCall(
    { region: LOCATION },
    async (request) => {
        const currentUserId = requireAuth(request);
        const { targetUserId } = request.data;

        if (!targetUserId) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.FOLLOW_TARGET_REQUIRED);
        }

        if (currentUserId === targetUserId) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.SELF_FOLLOW_NOT_ALLOWED);
        }

        const batch = db.batch();
        const currentUserRef = db.collection("users").doc(currentUserId);
        const targetUserRef = db.collection("users").doc(targetUserId);

        // 対象ユーザーが存在するか確認
        const targetUser = await targetUserRef.get();
        if (!targetUser.exists) {
            throw new HttpsError("not-found", RESOURCE_ERRORS.USER_NOT_FOUND);
        }

        // 現在のユーザーのfollowing配列に追加
        batch.update(currentUserRef, {
            following: admin.firestore.FieldValue.arrayUnion(targetUserId),
            followingCount: admin.firestore.FieldValue.increment(1),
        });

        // 対象ユーザーのfollowers配列に追加
        batch.update(targetUserRef, {
            followers: admin.firestore.FieldValue.arrayUnion(currentUserId),
            followersCount: admin.firestore.FieldValue.increment(1),
        });

        await batch.commit();

        console.log(`User ${currentUserId} followed ${targetUserId} `);

        return { success: true };
    }
);

/**
 * フォローを解除する
 */
export const unfollowUser = onCall(
    { region: LOCATION },
    async (request) => {
        const currentUserId = requireAuth(request);
        const { targetUserId } = request.data;

        if (!targetUserId) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.UNFOLLOW_TARGET_REQUIRED);
        }

        const batch = db.batch();
        const currentUserRef = db.collection("users").doc(currentUserId);
        const targetUserRef = db.collection("users").doc(targetUserId);

        // 現在のユーザーのfollowing配列から削除
        batch.update(currentUserRef, {
            following: admin.firestore.FieldValue.arrayRemove(targetUserId),
            followingCount: admin.firestore.FieldValue.increment(-1),
        });

        // 対象ユーザーのfollowers配列から削除
        batch.update(targetUserRef, {
            followers: admin.firestore.FieldValue.arrayRemove(currentUserId),
            followersCount: admin.firestore.FieldValue.increment(-1),
        });

        await batch.commit();

        console.log(`User ${currentUserId} unfollowed ${targetUserId} `);

        return { success: true };
    }
);

/**
 * フォロー状態を取得する
 */
export const getFollowStatus = onCall(
    { region: LOCATION },
    async (request) => {
        const currentUserId = requireAuth(request);
        const { targetUserId } = request.data;

        if (!targetUserId) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.USER_ID_REQUIRED);
        }

        const currentUser = await db.collection("users").doc(currentUserId).get();

        if (!currentUser.exists) {
            return { isFollowing: false };
        }

        const following = currentUser.data()?.following || [];
        const isFollowing = following.includes(targetUserId);

        return { isFollowing };
    }
);

/**
 * 徳ポイント履歴を取得
 */
export const getVirtueHistory = onCall(
    { region: LOCATION },
    async (request) => {
        const userId = requireAuth(request);

        const history = await db
            .collection("virtueHistory")
            .where("userId", "==", userId)
            .orderBy("createdAt", "desc")
            .limit(20)
            .get();

        return {
            history: history.docs.map((doc) => ({
                id: doc.id,
                ...doc.data(),
                createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
            })),
        };
    }
);

/**
 * 徳ポイントの現在値と設定を取得
 */
export const getVirtueStatus = onCall(
    { region: LOCATION },
    async (request) => {
        const userId = requireAuth(request);
        const userDoc = await db.collection("users").doc(userId).get();

        if (!userDoc.exists) {
            throw new HttpsError("not-found", RESOURCE_ERRORS.USER_NOT_FOUND);
        }

        const userData = userDoc.data()!;

        return {
            virtue: userData.virtue || VIRTUE_CONFIG.initial,
            isBanned: userData.isBanned || false,
            warningThreshold: VIRTUE_CONFIG.warningThreshold,
            maxVirtue: VIRTUE_CONFIG.initial,
        };
    }
);
