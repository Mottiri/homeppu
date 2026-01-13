/**
 * 通報関連のCallable Functions
 * - reportContent: コンテンツを通報する
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db, FieldValue } from "../helpers/firebase";
import { isAdmin, getAdminUids } from "../helpers/admin";
import { LOCATION } from "../config/constants";

/**
 * コンテンツを通報する
 * - 重複チェック（1ユーザー1投稿1回）
 * - 5件で自動非表示化 + 投稿者通知
 * - 3件で徳ポイント減少
 */
export const reportContent = onCall(
  { region: LOCATION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const reporterId = request.auth.uid;
    const { contentId, contentType, reason, targetUserId } = request.data;

    if (!contentId || !contentType || !reason || !targetUserId) {
      throw new HttpsError("invalid-argument", "必要な情報が不足しています");
    }

    // 自分自身を通報できない
    if (reporterId === targetUserId) {
      throw new HttpsError("invalid-argument", "自分自身を通報することはできません");
    }

    // 既に同じ内容を通報していないかチェック
    const existingReport = await db
      .collection("reports")
      .where("reporterId", "==", reporterId)
      .where("contentId", "==", contentId)
      .get();

    if (!existingReport.empty) {
      throw new HttpsError("already-exists", "既にこの内容を通報しています");
    }

    const now = FieldValue.serverTimestamp();

    // 通報を記録
    const reportRef = await db.collection("reports").add({
      reporterId: reporterId,
      targetUserId: targetUserId,
      contentId: contentId,
      contentType: contentType, // "post" | "comment"
      reason: reason,
      status: "pending", // pending, reviewed, resolved, dismissed
      createdAt: now,
    });

    // 対象ユーザーの通報カウントを増加
    const targetUserRef = db.collection("users").doc(targetUserId);
    await targetUserRef.update({
      reportCount: FieldValue.increment(1),
    });

    // 同一コンテンツへの通報数をカウント
    const contentReportsSnapshot = await db
      .collection("reports")
      .where("contentId", "==", contentId)
      .where("status", "==", "pending")
      .get();

    const contentReportCount = contentReportsSnapshot.size;
    console.log(`Report count for content ${contentId}: ${contentReportCount}`);

    // 5件以上で自動非表示化
    if (contentReportCount >= 5) {
      if (contentType === "post") {
        const postRef = db.collection("posts").doc(contentId);
        await postRef.update({
          isVisible: false,
          hiddenAt: now,
          hiddenReason: "通報多数のため自動非表示",
        });

        // 投稿者に通知
        await db
          .collection("users")
          .doc(targetUserId)
          .collection("notifications")
          .add({
            type: "post_hidden",
            title: "投稿が非表示になりました",
            body: "複数の通報があったため、投稿が一時的に非表示になりました。運営が確認します。",
            postId: contentId,
            isRead: false,
            createdAt: now,
          });

        // プッシュ通知はonNotificationCreatedが自動送信

        console.log(`Post ${contentId} hidden due to ${contentReportCount} reports`);
      }
    }

    // [削除] 対象ユーザーへの累積通報が3件以上で徳減少・ステータス自動変更
    // → 管理者が手動で対応するため不要

    // ===============================================
    // 管理者への通知（新規通報）
    // ===============================================
    const reporterIsAdmin = await isAdmin(reporterId);
    if (!reporterIsAdmin) {
      try {
        const adminUids = await getAdminUids();
        const notifyBody = `新規通報: ${reason} (対象: ${targetUserId})`;

        // 全管理者にアプリ内通知を送信 (プッシュ通知はonNotificationCreatedで自動送信)
        for (const adminUid of adminUids) {
          await db.collection("users").doc(adminUid).collection("notifications").add({
            type: "admin_report",
            title: "新規通報を受信",
            body: notifyBody,
            reportId: reportRef.id,
            contentId: contentId,
            contentType: contentType,
            isRead: false,
            createdAt: now,
          });
        }

        console.log(`Sent admin notification for report ${reportRef.id}`);
      } catch (e) {
        console.error("Failed to send admin notification:", e);
      }
    }

    return {
      success: true,
      reportId: reportRef.id,
      message: "通報内容を運営チームで審査します。ご協力ありがとうございました！",
    };
  }
);
