/**
 * サークル管理関連のCallable Functions
 * - deleteCircle: サークルを削除（ソフトデリート後、バックグラウンドで完全削除）
 * - cleanupDeletedCircle: バックグラウンドでサークルデータをクリーンアップ（Cloud Tasks）
 * - approveJoinRequest: 参加申請を承認
 * - rejectJoinRequest: 参加申請を拒否
 * - sendJoinRequest: 参加申請を送信
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as functionsV1 from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { scheduleHttpTask } from "../helpers/cloud-tasks";
import { db, FieldValue, FieldPath, Timestamp } from "../helpers/firebase";
import { requireAuth } from "../helpers/auth";
import { isAdmin } from "../helpers/admin";
import { deleteStorageFileFromUrl } from "../helpers/storage";
import { generateNameTokens } from "../helpers/search-tokens";
import { PROJECT_ID, LOCATION } from "../config/constants";
import {
  AUTH_ERRORS,
  RESOURCE_ERRORS,
  VALIDATION_ERRORS,
  PERMISSION_ERRORS,
  NOTIFICATION_TITLES,
  LABELS,
  SUCCESS_MESSAGES,
} from "../config/messages";

async function assertSubscriber(userId: string): Promise<void> {
  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) {
    throw new HttpsError("not-found", RESOURCE_ERRORS.USER_NOT_FOUND);
  }
  if (userDoc.data()?.isSubscriber !== true) {
    throw new HttpsError("permission-denied", PERMISSION_ERRORS.EPIC_REACTION_REQUIRES_SUBSCRIPTION);
  }
}

/** サブスクまたはトライアルアクティブのいずれかを要求 */
async function assertSubscriberOrTrial(userId: string): Promise<void> {
  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) {
    throw new HttpsError("permission-denied", PERMISSION_ERRORS.EPIC_REACTION_REQUIRES_SUBSCRIPTION);
  }
  const userData = userDoc.data()!;
  const isSubscriber = userData.isSubscriber === true;
  const trialStarted = userData.circleTrialLastStartedAt?.toDate?.();
  const trialEnded = userData.circleTrialLastEndedAt?.toDate?.();
  const isTrialActive = trialStarted && (!trialEnded || trialEnded < trialStarted);
  if (!isSubscriber && !isTrialActive) {
    throw new HttpsError("permission-denied", PERMISSION_ERRORS.EPIC_REACTION_REQUIRES_SUBSCRIPTION);
  }
}

export const startCircleBrowseTrial = onCall(
  {
    region: LOCATION,
    enforceAppCheck: true,
  },
  async (request) => {
    const userId = requireAuth(request, AUTH_ERRORS.UNAUTHENTICATED_ALT);
    const userRef = db.collection("users").doc(userId);
    const result = await db.runTransaction(async (tx) => {
      const userDoc = await tx.get(userRef);
      if (!userDoc.exists) {
        throw new HttpsError("not-found", RESOURCE_ERRORS.USER_NOT_FOUND);
      }
      const userData = userDoc.data()!;
      if (userData.isSubscriber === true) {
        return { allowed: true, isSubscriber: true };
      }
      if (userData.circleTrialUsed === true) {
        throw new HttpsError("failed-precondition", VALIDATION_ERRORS.ALREADY_APPLIED);
      }
      tx.update(userRef, {
        circleTrialUsed: true,
        circleTrialUsedAt: FieldValue.serverTimestamp(),
        circleTrialLastStartedAt: FieldValue.serverTimestamp(),
      });
      return { allowed: true, isSubscriber: false };
    });
    return result;
  }
);

export const endCircleBrowseTrial = onCall(
  {
    region: LOCATION,
    enforceAppCheck: true,
  },
  async (request) => {
    const userId = requireAuth(request, AUTH_ERRORS.UNAUTHENTICATED_ALT);
    await db.collection("users").doc(userId).set(
      {
        circleTrialLastEndedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return { success: true };
  }
);

/**
 * サークルを削除
 * 1. ソフトデリート（即座にUIから非表示）
 * 2. メンバーに通知
 * 3. バックグラウンドでCloud Tasksでクリーンアップをスケジュール
 */
export const deleteCircle = onCall(
  {
    region: LOCATION,
    timeoutSeconds: 60, // 即座にレスポンスするため短く
    memory: "256MiB",
    enforceAppCheck: true,
  },
  async (request) => {
    const { circleId, reason } = request.data;
    const userId = requireAuth(request, AUTH_ERRORS.UNAUTHENTICATED_ALT);

    if (!circleId) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.CIRCLE_ID_REQUIRED);
    }

    console.log(`=== deleteCircle START: circleId=${circleId}, userId=${userId} ===`);

    try {
      // 1. サークル情報を取得
      const circleDoc = await db.collection("circles").doc(circleId).get();
      if (!circleDoc.exists) {
        throw new HttpsError("not-found", RESOURCE_ERRORS.CIRCLE_NOT_FOUND);
      }

      const circleData = circleDoc.data()!;
      const ownerId = circleData.ownerId;
      const circleName = circleData.name;
      const memberIds: string[] = circleData.memberIds || [];

      // オーナーまたは管理者チェック
      const userIsAdmin = await isAdmin(userId);
      if (ownerId !== userId && !userIsAdmin) {
        throw new HttpsError("permission-denied", PERMISSION_ERRORS.CIRCLE_DELETE_OWNER_ONLY);
      }

      // 2. サークルをソフトデリート（即座にUIから非表示）
      await db.collection("circles").doc(circleId).update({
        isDeleted: true,
        deletedAt: FieldValue.serverTimestamp(),
        deletedBy: userId,
        deleteReason: reason || null,
      });

      console.log(`Soft deleted circle: ${circleName}`);

      // 3. メンバーに通知送信（オーナー以外）
      const ownerDoc = await db.collection("users").doc(ownerId).get();
      const ownerName = ownerDoc.exists ? ownerDoc.data()?.displayName || LABELS.OWNER : LABELS.OWNER;

      const notificationMessage = reason && reason.trim()
        ? `${circleName}が削除されました。理由: ${reason}`
        : `${circleName}が削除されました`;

      // 通知はバックグラウンドで送信（Promise.allで高速化）
      const notificationPromises = memberIds
        .filter((id) => id !== ownerId && !id.startsWith("circle_ai_"))
        .map(async (memberId) => {
          try {
            await db.collection("users").doc(memberId).collection("notifications").add({
              type: "circle_deleted",
              senderId: ownerId,
              senderName: ownerName,
              senderAvatarUrl: ownerDoc.data()?.avatarIndex?.toString() || "0",
              title: NOTIFICATION_TITLES.CIRCLE_DELETED,
              body: notificationMessage,
              circleName: circleName,
              isRead: false,
              createdAt: FieldValue.serverTimestamp(),
            });
            // プッシュ通知はonNotificationCreatedトリガーで自動送信される
          } catch (e) {
            console.error(`Notification failed for ${memberId}:`, e);
          }
        });

      await Promise.all(notificationPromises);

      // 4. バックグラウンドクリーンアップをスケジュール
      const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
      const location = LOCATION;
      const queue = "circle-cleanup";

      const targetUrl = `https://${location}-${project}.cloudfunctions.net/cleanupDeletedCircle`;

      const payload = { circleId, circleName };
      await scheduleHttpTask({
        queue,
        url: targetUrl,
        payload,
        scheduleTime: new Date(Date.now() + 5 * 1000), // 5 seconds later
        projectId: project,
        location,
      });
      console.log(`Scheduled cleanup task for circle: ${circleId}`);

      console.log(`=== deleteCircle SUCCESS: ${circleName} ===`);
      return { success: true, message: SUCCESS_MESSAGES.itemDeleted(circleName) };

    } catch (error) {
      console.error(`=== deleteCircle ERROR:`, error);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", `削除に失敗しました: ${error}`);
    }
  }
);

/**
 * バックグラウンドでサークルデータをクリーンアップ
 * Cloud Tasksから呼び出される
 * 100投稿ずつ処理し、残りがあれば自分自身を再スケジュール
 */
export const cleanupDeletedCircle = functionsV1.region(LOCATION).runWith({
  timeoutSeconds: 540,
  memory: "1GB",
}).https.onRequest(async (request, response) => {
  // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
  const { verifyCloudTasksRequest } = await import("../helpers/cloud-tasks-auth");
  if (!await verifyCloudTasksRequest(request, "cleanupDeletedCircle")) {
    response.status(403).send("Unauthorized");
    return;
  }

  try {
    // リクエストボディを取得（Cloud Tasksからは既にパース済みの場合がある）
    let payload: { circleId: string; circleName: string };
    if (typeof request.body === "string") {
      // Base64文字列の場合
      payload = JSON.parse(Buffer.from(request.body, "base64").toString());
    } else if (request.body && typeof request.body === "object") {
      // 既にJSONオブジェクトの場合
      payload = request.body as { circleId: string; circleName: string };
    } else {
      console.error("Invalid request body:", request.body);
      response.status(400).send("Invalid request body");
      return;
    }

    const { circleId, circleName } = payload;

    if (!circleId) {
      console.error("Missing circleId in payload");
      response.status(400).send("Missing circleId");
      return;
    }

    console.log(`=== cleanupDeletedCircle START: ${circleId} ===`);

    // 1. まず投稿を100件取得
    const BATCH_LIMIT = 100;
    const postsSnapshot = await db
      .collection("posts")
      .where("circleId", "==", circleId)
      .limit(BATCH_LIMIT)
      .get();

    console.log(`Found ${postsSnapshot.size} posts to process`);

    if (postsSnapshot.size > 0) {
      // 削除対象を収集
      const deleteRefs: FirebaseFirestore.DocumentReference[] = [];
      const mediaDeletePromises: Promise<void>[] = [];

      for (const postDoc of postsSnapshot.docs) {
        const postId = postDoc.id;
        const postData = postDoc.data();

        // コメント収集
        const comments = await db.collection("comments").where("postId", "==", postId).get();
        comments.docs.forEach((c) => deleteRefs.push(c.ref));

        // リアクション収集
        const reactions = await db.collection("reactions").where("postId", "==", postId).get();
        reactions.docs.forEach((r) => deleteRefs.push(r.ref));

        // メディア削除（ヘルパー関数を使用）
        const mediaItems = postData.mediaItems || [];
        for (const media of mediaItems) {
          if (media.url) {
            mediaDeletePromises.push(
              deleteStorageFileFromUrl(media.url).then(() => { })
            );
          }
          // サムネイルも削除
          if (media.thumbnailUrl) {
            mediaDeletePromises.push(
              deleteStorageFileFromUrl(media.thumbnailUrl).then(() => { })
            );
          }
        }

        deleteRefs.push(postDoc.ref);
      }

      // バッチ削除
      const MAX_BATCH = 400;
      for (let i = 0; i < deleteRefs.length; i += MAX_BATCH) {
        const batch = db.batch();
        deleteRefs.slice(i, i + MAX_BATCH).forEach((ref) => batch.delete(ref));
        await batch.commit();
      }

      // メディア並列削除
      await Promise.all(mediaDeletePromises.slice(0, 50));
      for (let i = 50; i < mediaDeletePromises.length; i += 50) {
        await Promise.all(mediaDeletePromises.slice(i, i + 50));
      }

      console.log(`Deleted ${postsSnapshot.size} posts and related data`);

      // まだ投稿が残っているか確認
      const remainingPosts = await db
        .collection("posts")
        .where("circleId", "==", circleId)
        .limit(1)
        .get();

      if (!remainingPosts.empty) {
        // 自分自身を再スケジュール
        const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
        const targetUrl = `https://${LOCATION}-${project}.cloudfunctions.net/cleanupDeletedCircle`;

        await scheduleHttpTask({
          queue: "circle-cleanup",
          url: targetUrl,
          payload: { circleId, circleName },
          scheduleTime: new Date(Date.now() + 2 * 1000),
          projectId: project,
          location: LOCATION,
        });

        console.log(`Scheduled next cleanup batch for ${circleId}`);
        response.status(200).send(`Processed ${postsSnapshot.size} posts, more remaining`);
        return;
      }
    }

    // 2. 全投稿削除完了 → 参加申請削除
    const joinRequests = await db.collection("circleJoinRequests").where("circleId", "==", circleId).get();
    const reqBatch = db.batch();
    joinRequests.docs.forEach((doc) => reqBatch.delete(doc.ref));
    if (joinRequests.size > 0) await reqBatch.commit();
    console.log(`Deleted ${joinRequests.size} join requests`);

    // 3. サークル画像をStorageから削除（icon, cover）
    try {
      const bucket = admin.storage().bucket();
      const [files] = await bucket.getFiles({ prefix: `circles/${circleId}/` });
      for (const file of files) {
        await file.delete().catch((e) => console.error(`Storage delete failed: ${file.name}`, e));
      }
      console.log(`Deleted ${files.length} circle image files from Storage`);
    } catch (storageError) {
      console.error("Circle image storage cleanup error:", storageError);
      // Storage削除失敗しても処理は継続
    }

    // 4. サークルAIアカウント削除（サブコレクション含む）
    const circleDoc = await db.collection("circles").doc(circleId).get();
    if (circleDoc.exists) {
      const generatedAIs = circleDoc.data()?.generatedAIs || [];
      for (const ai of generatedAIs) {
        if (ai.id && ai.id.startsWith("circle_ai_")) {
          const aiUserRef = db.collection("users").doc(ai.id);

          // サブコレクション（notifications）を削除
          const notificationsSnapshot = await aiUserRef.collection("notifications").get();
          if (!notificationsSnapshot.empty) {
            const subBatch = db.batch();
            notificationsSnapshot.docs.forEach(doc => subBatch.delete(doc.ref));
            await subBatch.commit();
            console.log(`Deleted ${notificationsSnapshot.size} notifications for AI ${ai.id}`);
          }

          // AIユーザードキュメント本体を削除
          await aiUserRef.delete().catch(() => { });
        }
      }
      console.log(`Deleted ${generatedAIs.length} AI accounts with subcollections`);

      // 5. サークル本体を完全削除
      await circleDoc.ref.delete();
      console.log(`Permanently deleted circle: ${circleName}`);
    }

    console.log(`=== cleanupDeletedCircle COMPLETE: ${circleId} ===`);
    response.status(200).send("Cleanup complete");

  } catch (error) {
    console.error("cleanupDeletedCircle ERROR:", error);
    response.status(500).send(`Error: ${error}`);
  }
});

/**
 * 参加申請を承認
 */
export const approveJoinRequest = onCall(
  {
    region: LOCATION,
    enforceAppCheck: true,
  },
  async (request) => {
    const { requestId, circleId, circleName } = request.data;
    const userId = requireAuth(request, AUTH_ERRORS.UNAUTHENTICATED_ALT);

    if (!requestId || !circleId) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.MISSING_PARAMS);
    }

    try {
      // サークル情報を取得してオーナーチェック
      const circleDoc = await db.collection("circles").doc(circleId).get();
      if (!circleDoc.exists) {
        throw new HttpsError("not-found", RESOURCE_ERRORS.CIRCLE_NOT_FOUND);
      }
      const circleData = circleDoc.data()!;
      const circleOwnerId = circleData.ownerId;
      const circleSubOwnerId = circleData.subOwnerId;

      // オーナー、副オーナー、または管理者のみ承認可能
      const userIsAdmin = await isAdmin(userId);
      if (userId !== circleOwnerId && userId !== circleSubOwnerId && !userIsAdmin) {
        throw new HttpsError("permission-denied", PERMISSION_ERRORS.CIRCLE_APPROVE_OWNER_ONLY);
      }

      // 申請情報を取得
      const requestDoc = await db.collection("circleJoinRequests").doc(requestId).get();
      if (!requestDoc.exists) {
        throw new HttpsError("not-found", RESOURCE_ERRORS.APPLICATION_NOT_FOUND);
      }
      const requestData = requestDoc.data()!;
      const applicantId = requestData.userId;

      // 申請を承認済みに更新
      await db.collection("circleJoinRequests").doc(requestId).update({
        status: "approved",
      });

      // サークルにメンバーを追加
      await db.collection("circles").doc(circleId).update({
        memberIds: FieldValue.arrayUnion(applicantId),
        memberCount: FieldValue.increment(1),
      });

      // 申請者の表示名を取得
      const ownerDoc = await db.collection("users").doc(userId).get();
      const ownerName = ownerDoc.data()?.displayName || LABELS.OWNER;

      // 申請者に通知を送信
      await db.collection("users").doc(applicantId).collection("notifications").add({
        type: "join_request_approved",
        senderId: userId,
        senderName: ownerName,
        senderAvatarUrl: ownerDoc.data()?.avatarIndex?.toString() || "0",
        title: NOTIFICATION_TITLES.JOIN_APPROVED,
        body: SUCCESS_MESSAGES.joinApproved(circleName),
        circleName: circleName,
        circleId: circleId,
        isRead: false,
        createdAt: FieldValue.serverTimestamp(),
      });

      console.log(`=== approveJoinRequest SUCCESS: ${requestId} ===`);
      return { success: true };

    } catch (error) {
      console.error(`=== approveJoinRequest ERROR:`, error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", `承認に失敗しました: ${error}`);
    }
  }
);

/**
 * 参加申請を拒否
 */
export const rejectJoinRequest = onCall(
  {
    region: LOCATION,
    enforceAppCheck: true,
  },
  async (request) => {
    const { requestId, circleId, circleName } = request.data;
    const userId = requireAuth(request, AUTH_ERRORS.UNAUTHENTICATED_ALT);

    if (!requestId || !circleId) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.MISSING_PARAMS);
    }

    try {
      // サークル情報を取得してオーナー/副オーナーチェック
      const circleDoc = await db.collection("circles").doc(circleId).get();
      if (!circleDoc.exists) {
        throw new HttpsError("not-found", RESOURCE_ERRORS.CIRCLE_NOT_FOUND);
      }
      const circleData = circleDoc.data()!;
      const circleOwnerId = circleData.ownerId;
      const circleSubOwnerId = circleData.subOwnerId;

      // オーナー、副オーナー、または管理者のみ拒否可能
      const userIsAdmin = await isAdmin(userId);
      if (userId !== circleOwnerId && userId !== circleSubOwnerId && !userIsAdmin) {
        throw new HttpsError("permission-denied", PERMISSION_ERRORS.CIRCLE_REJECT_OWNER_ONLY);
      }

      // 申請情報を取得
      const requestDoc = await db.collection("circleJoinRequests").doc(requestId).get();
      if (!requestDoc.exists) {
        throw new HttpsError("not-found", RESOURCE_ERRORS.APPLICATION_NOT_FOUND);
      }
      const requestData = requestDoc.data()!;
      const applicantId = requestData.userId;

      // 申請を拒否済みに更新
      await db.collection("circleJoinRequests").doc(requestId).update({
        status: "rejected",
      });

      // オーナーの表示名を取得
      const ownerDoc = await db.collection("users").doc(userId).get();
      const ownerName = ownerDoc.data()?.displayName || LABELS.OWNER;

      // 申請者に通知を送信
      await db.collection("users").doc(applicantId).collection("notifications").add({
        type: "join_request_rejected",
        senderId: userId,
        senderName: ownerName,
        senderAvatarUrl: ownerDoc.data()?.avatarIndex?.toString() || "0",
        title: NOTIFICATION_TITLES.JOIN_REJECTED,
        body: SUCCESS_MESSAGES.joinRejected(circleName),
        circleName: circleName,
        circleId: circleId,
        isRead: false,
        createdAt: FieldValue.serverTimestamp(),
      });

      console.log(`=== rejectJoinRequest SUCCESS: ${requestId} ===`);
      return { success: true };

    } catch (error) {
      console.error(`=== rejectJoinRequest ERROR:`, error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", `拒否に失敗しました: ${error}`);
    }
  }
);

/**
 * 参加申請を送信（オーナーに通知）
 */
export const sendJoinRequest = onCall(
  {
    region: LOCATION,
    enforceAppCheck: true,
  },
  async (request) => {
    const { circleId } = request.data;
    const userId = requireAuth(request, AUTH_ERRORS.UNAUTHENTICATED_ALT);

    if (!circleId) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.CIRCLE_ID_REQUIRED_ALT);
    }

    try {
      await assertSubscriber(userId);
      // サークル情報を取得
      const circleDoc = await db.collection("circles").doc(circleId).get();
      if (!circleDoc.exists) {
        throw new HttpsError("not-found", RESOURCE_ERRORS.CIRCLE_NOT_FOUND);
      }
      const circleData = circleDoc.data()!;
      const ownerId = circleData.ownerId;
      const subOwnerId = circleData.subOwnerId;
      const circleName = circleData.name;

      // 既に申請中かチェック
      const existingRequest = await db
        .collection("circleJoinRequests")
        .where("circleId", "==", circleId)
        .where("userId", "==", userId)
        .where("status", "==", "pending")
        .limit(1)
        .get();

      if (!existingRequest.empty) {
        throw new HttpsError("already-exists", VALIDATION_ERRORS.ALREADY_APPLIED);
      }

      // 申請を作成
      await db.collection("circleJoinRequests").add({
        circleId: circleId,
        userId: userId,
        status: "pending",
        createdAt: FieldValue.serverTimestamp(),
      });

      // 申請者の情報を取得
      const applicantDoc = await db.collection("users").doc(userId).get();
      const applicantName = applicantDoc.data()?.displayName || LABELS.USER;

      // 通知対象者リスト（オーナー + 副オーナー）
      const notifyTargets = [ownerId];
      if (subOwnerId && subOwnerId !== ownerId) {
        notifyTargets.push(subOwnerId);
      }

      // オーナーと副オーナーにアプリ内通知を送信
      for (const targetId of notifyTargets) {
        await db.collection("users").doc(targetId).collection("notifications").add({
          type: "join_request_received",
          senderId: userId,
          senderName: applicantName,
          senderAvatarUrl: applicantDoc.data()?.avatarIndex?.toString() || "0",
          title: NOTIFICATION_TITLES.JOIN_REQUEST_RECEIVED,
          body: `${applicantName}さんが${circleName}への参加を申請しました`,
          circleName: circleName,
          circleId: circleId,
          isRead: false,
          createdAt: FieldValue.serverTimestamp(),
        });
      }

      // プッシュ通知はonNotificationCreatedトリガーで自動送信される

      console.log(`=== sendJoinRequest SUCCESS: ${userId} -> ${circleId} ===`);
      return { success: true };

    } catch (error) {
      console.error(`=== sendJoinRequest ERROR:`, error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", `申請に失敗しました: ${error}`);
    }
  }
);

// Join a public circle
export const joinCircle = onCall(
  {
    region: LOCATION,
    enforceAppCheck: true,
  },
  async (request) => {
    const { circleId } = request.data;
    const userId = requireAuth(request, AUTH_ERRORS.UNAUTHENTICATED_ALT);

    if (!circleId) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.CIRCLE_ID_REQUIRED);
    }

    await assertSubscriber(userId);

    const userDoc = await db.collection("users").doc(userId).get();
    if (userDoc.exists && userDoc.data()?.isBanned) {
      throw new HttpsError("permission-denied", AUTH_ERRORS.BANNED);
    }

    const circleRef = db.collection("circles").doc(circleId);

    try {
      await db.runTransaction(async (tx) => {
        const circleDoc = await tx.get(circleRef);
        if (!circleDoc.exists) {
          throw new HttpsError("not-found", RESOURCE_ERRORS.CIRCLE_NOT_FOUND);
        }

        const circleData = circleDoc.data()!;
        if (circleData.isDeleted) {
          throw new HttpsError("failed-precondition", "circle_deleted");
        }

        const isPublic = circleData.isPublic !== false;
        if (!isPublic) {
          throw new HttpsError("failed-precondition", "circle_invite_only");
        }

        const memberIds: string[] = circleData.memberIds || [];
        if (memberIds.includes(userId)) {
          return;
        }

        const memberCount: number = circleData.memberCount ?? memberIds.length;
        const maxMembers: number = circleData.maxMembers ?? 20;
        if (memberCount >= maxMembers) {
          throw new HttpsError("failed-precondition", "circle_full");
        }

        tx.update(circleRef, {
          memberIds: FieldValue.arrayUnion(userId),
          memberCount: FieldValue.increment(1),
        });
      });

      return { success: true };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      console.error("joinCircle error:", error);
      throw new HttpsError("internal", "joinCircle failed");
    }
  }
);

// Leave a circle (owner cannot leave)
export const leaveCircle = onCall(
  {
    region: LOCATION,
    enforceAppCheck: true,
  },
  async (request) => {
    const { circleId } = request.data;
    const userId = requireAuth(request, AUTH_ERRORS.UNAUTHENTICATED_ALT);

    if (!circleId) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.CIRCLE_ID_REQUIRED);
    }

    const circleRef = db.collection("circles").doc(circleId);

    try {
      await db.runTransaction(async (tx) => {
        const circleDoc = await tx.get(circleRef);
        if (!circleDoc.exists) {
          throw new HttpsError("not-found", RESOURCE_ERRORS.CIRCLE_NOT_FOUND);
        }

        const circleData = circleDoc.data()!;
        if (circleData.ownerId === userId) {
          throw new HttpsError("permission-denied", "owner_cannot_leave");
        }

        const memberIds: string[] = circleData.memberIds || [];
        if (!memberIds.includes(userId)) {
          return;
        }

        const updates: Record<string, unknown> = {
          memberIds: FieldValue.arrayRemove(userId),
          memberCount: FieldValue.increment(-1),
        };

        if (circleData.subOwnerId === userId) {
          updates.subOwnerId = null;
        }

        tx.update(circleRef, updates);
      });

      return { success: true };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      console.error("leaveCircle error:", error);
      throw new HttpsError("internal", "leaveCircle failed");
    }
  }
);

/**
 * サークル検索（Cloud Functions callable）
 * N-gramトークン + array-contains による部分一致検索
 * cursorページネーション対応
 */
export const searchCircles = onCall(
  {
    region: LOCATION,
    enforceAppCheck: true,
    timeoutSeconds: 10,
    memory: "256MiB",
  },
  async (request) => {
    const userId = requireAuth(request, AUTH_ERRORS.UNAUTHENTICATED_ALT);

    await assertSubscriberOrTrial(userId);

    const { query, category, limit: requestLimit, cursor, joinedOnly } = request.data;

    // バリデーション
    if (!query || typeof query !== "string" || query.trim().length < 1) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
    }
    if (query.length > 100) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
    }
    // cursorバリデーション
    if (cursor) {
      if (typeof cursor.memberCount !== "number" || typeof cursor.id !== "string") {
        throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
      }
    }

    const searchLimit = Math.min(Math.max(requestLimit || 20, 1), 50);
    const searchToken = query.toLowerCase().trim();
    const isJoinedOnly = joinedOnly === true;

    // レスポンス整形ヘルパー
    const formatCircle = (data: FirebaseFirestore.DocumentData, id: string) => ({
      id,
      name: data.name || "",
      description: data.description || "",
      category: data.category || "その他",
      ownerId: data.ownerId || "",
      subOwnerId: data.subOwnerId || null,
      aiMode: data.aiMode || "mix",
      isPublic: data.isPublic ?? true,
      memberCount: data.memberCount || 0,
      postCount: data.postCount || 0,
      iconImageUrl: data.iconImageUrl || null,
      coverImageUrl: data.coverImageUrl || null,
      goal: data.goal || "",
      recentActivity: data.recentActivity?.toDate?.()?.toISOString() || null,
      lastHumanPostAt: data.lastHumanPostAt?.toDate?.()?.toISOString() || null,
      createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
    });

    // --- joinedOnlyモード ---
    // memberIds array-contains userId で参加サークルを取得し、名前でJSフィルタ
    // 参加サークル数は通常少数（数十件）なのでページネーション不要
    if (isJoinedOnly) {
      let joinedQuery: FirebaseFirestore.Query = db.collection("circles")
        .where("isDeleted", "==", false)
        .where("memberIds", "array-contains", userId);

      if (category && category !== "全て") {
        joinedQuery = joinedQuery.where("category", "==", category);
      }

      // 参加サークルは通常少数なので全件取得（上限200）
      joinedQuery = joinedQuery.orderBy("memberCount", "desc").limit(200);
      const joinedSnapshot = await joinedQuery.get();

      // 名前でフィルタ（部分一致）
      const matchedDocs = joinedSnapshot.docs.filter((doc) => {
        const name = (doc.data().name || "").toLowerCase();
        return name.includes(searchToken);
      });

      // aiOnlyのオーナーサークルとそれ以外を分離
      const privateOwnerCircles: ReturnType<typeof formatCircle>[] = [];
      const circles: ReturnType<typeof formatCircle>[] = [];
      for (const doc of matchedDocs) {
        const data = doc.data();
        if (data.aiMode === "aiOnly" && data.ownerId === userId) {
          privateOwnerCircles.push(formatCircle(data, doc.id));
        } else {
          circles.push(formatCircle(data, doc.id));
        }
      }

      // 200件上限に達した場合、結果が不完全であることを通知
      const joinedTruncated = joinedSnapshot.docs.length >= 200;

      return { circles, privateOwnerCircles, hasMore: false, nextCursor: undefined, joinedTruncated };
    }

    // --- 通常モード（全体検索） ---
    // クエリ1: オーナーのaiOnlyサークル（初回のみ）
    // クエリ2: 公開サークル検索（cursorページネーション対応）
    // 両クエリは独立しているため Promise.all で並列実行
    const fetchLimit = searchLimit + 1;

    let ownerQueryPromise: Promise<FirebaseFirestore.QuerySnapshot> | null = null;

    if (!cursor) {
      let ownerQuery: FirebaseFirestore.Query = db.collection("circles")
        .where("isDeleted", "==", false)
        .where("ownerId", "==", userId)
        .where("aiMode", "==", "aiOnly")
        .where("nameTokens", "array-contains", searchToken);

      if (category && category !== "全て") {
        ownerQuery = ownerQuery.where("category", "==", category);
      }

      ownerQuery = ownerQuery.limit(50);
      ownerQueryPromise = ownerQuery.get();
    }

    let publicQuery: FirebaseFirestore.Query = db.collection("circles")
      .where("isDeleted", "==", false)
      .where("isPublic", "==", true)
      .where("aiMode", "in", ["mix", "humanOnly"])
      .where("nameTokens", "array-contains", searchToken)
      .orderBy("memberCount", "desc")
      .orderBy(FieldPath.documentId())
      .limit(fetchLimit);

    if (category && category !== "全て") {
      publicQuery = publicQuery.where("category", "==", category);
    }

    if (cursor) {
      publicQuery = publicQuery.startAfter(cursor.memberCount, cursor.id);
    }

    const [ownerSnapshot, publicSnapshot] = await Promise.all([
      ownerQueryPromise ?? Promise.resolve(null),
      publicQuery.get(),
    ]);

    // オーナーのaiOnlyサークル
    const privateOwnerCircles: ReturnType<typeof formatCircle>[] = [];
    if (ownerSnapshot) {
      for (const doc of ownerSnapshot.docs) {
        privateOwnerCircles.push(formatCircle(doc.data(), doc.id));
      }
    }

    // 公開サークル
    const hasMore = publicSnapshot.docs.length > searchLimit;
    const publicDocs = publicSnapshot.docs.slice(0, searchLimit);
    const circles = publicDocs.map((doc) => formatCircle(doc.data(), doc.id));

    let nextCursor: { memberCount: number; id: string } | undefined;
    if (hasMore) {
      const lastDoc = publicDocs[publicDocs.length - 1];
      nextCursor = {
        memberCount: lastDoc.data().memberCount || 0,
        id: lastDoc.id,
      };
    }

    return { circles, privateOwnerCircles, hasMore, nextCursor };
  }
);

/**
 * サークル作成（Cloud Functions callable）
 * オーナーが作成できるサークル数を上限30に制限
 */
const MAX_CIRCLES_PER_USER = 30;

export const createCircle = onCall(
  {
    region: LOCATION,
    enforceAppCheck: true,
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    const userId = requireAuth(request, AUTH_ERRORS.UNAUTHENTICATED_ALT);
    await assertSubscriber(userId);

    // BANチェック
    const userDoc = await db.collection("users").doc(userId).get();
    if (userDoc.exists && userDoc.data()?.isBanned) {
      throw new HttpsError("permission-denied", AUTH_ERRORS.BANNED);
    }

    const { name, description, category, aiMode, goal, isPublic, rules: circleRules } = request.data;

    // バリデーション
    if (!name || typeof name !== "string" || name.trim().length === 0) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.MISSING_REQUIRED);
    }
    if (name.length > 30) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
    }
    if (!description || typeof description !== "string") {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.MISSING_REQUIRED);
    }
    if (description.length > 500) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
    }
    if (goal !== undefined && typeof goal !== "string") {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
    }
    if (typeof goal === "string" && goal.length > 200) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
    }
    if (circleRules !== undefined && (typeof circleRules !== "string" || circleRules.length > 1000)) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
    }
    const validCategories = ["勉強", "ダイエット", "運動", "趣味", "仕事", "資格", "読書", "語学", "音楽", "その他"];
    if (!category || typeof category !== "string" || !validCategories.includes(category)) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
    }
    if (isPublic !== undefined && typeof isPublic !== "boolean") {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
    }
    const validAIModes = ["aiOnly", "mix", "humanOnly"];
    if (!aiMode || !validAIModes.includes(aiMode)) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
    }

    // オーナーが作成したサークル数をチェック（削除済みは除外）
    const ownedCirclesSnapshot = await db.collection("circles")
      .where("ownerId", "==", userId)
      .where("isDeleted", "==", false)
      .select() // ドキュメントデータ不要、カウントのみ
      .get();

    if (ownedCirclesSnapshot.size >= MAX_CIRCLES_PER_USER) {
      throw new HttpsError("resource-exhausted", VALIDATION_ERRORS.CIRCLE_LIMIT_EXCEEDED);
    }

    // サークル作成
    const docRef = db.collection("circles").doc();
    const circleData = {
      name: name.trim(),
      description: description.trim(),
      category: category || "その他",
      ownerId: userId,
      subOwnerId: null,
      memberIds: [userId],
      aiMode,
      generatedAIs: [],
      isPublic: aiMode === "aiOnly" ? false : isPublic !== false,
      maxMembers: 20,
      createdAt: Timestamp.now(),
      recentActivity: null,
      lastHumanPostAt: null,
      goal: (goal || "").trim(),
      coverImageUrl: null,
      iconImageUrl: null,
      memberCount: 1,
      postCount: 0,
      rules: circleRules || null,
      isDeleted: false,
      nameTokens: generateNameTokens(name.trim()),
    };

    await docRef.set(circleData);

    return { circleId: docRef.id };
  }
);
