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
import { db, FieldValue } from "../helpers/firebase";
import { requireAuth } from "../helpers/auth";
import { isAdmin } from "../helpers/admin";
import { deleteStorageFileFromUrl } from "../helpers/storage";
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
        scheduleTime: new Date(Date.now() + 5 * 1000), // 5?????????
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
        memberIds: admin.firestore.FieldValue.arrayUnion(applicantId),
        memberCount: admin.firestore.FieldValue.increment(1),
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
  },
  async (request) => {
    const { circleId } = request.data;
    const userId = requireAuth(request, AUTH_ERRORS.UNAUTHENTICATED_ALT);

    if (!circleId) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.CIRCLE_ID_REQUIRED_ALT);
    }

    try {
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
