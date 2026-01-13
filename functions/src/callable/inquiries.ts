/**
 * 問い合わせ関連のCallable Functions
 * - createInquiry: 新規問い合わせを作成
 * - sendInquiryMessage: ユーザーがメッセージを送信
 * - sendInquiryReply: 管理者が返信を送信
 * - updateInquiryStatus: ステータスを変更（スプレッドシート連携対応）
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db, FieldValue } from "../helpers/firebase";
import { isAdmin, getAdminUids } from "../helpers/admin";
import { appendInquiryToSpreadsheet } from "../helpers/spreadsheet";
import { sheetsServiceAccountKey } from "../config/secrets";
import { LOCATION } from "../config/constants";

/**
 * 新規問い合わせを作成
 */
export const createInquiry = onCall(
  { region: LOCATION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const { category, subject, content, imageUrl } = request.data;

    if (!category || !subject || !content) {
      throw new HttpsError("invalid-argument", "カテゴリ、件名、内容は必須です");
    }

    console.log(`=== createInquiry: userId=${userId}, category=${category} ===`);

    // 管理者UID一覧を取得
    const adminUids = await getAdminUids();

    try {
      // ユーザー情報を取得
      const userDoc = await db.collection("users").doc(userId).get();
      const userData = userDoc.data();
      const userDisplayName = userData?.displayName || "匿名ユーザー";
      const userAvatarIndex = userData?.avatarIndex || 0;

      // 問い合わせを作成
      const inquiryRef = db.collection("inquiries").doc();
      const now = FieldValue.serverTimestamp();

      await inquiryRef.set({
        userId,
        userDisplayName,
        userAvatarIndex,
        category,
        subject,
        status: "open",
        hasUnreadReply: false,
        hasUnreadMessage: true, // 管理者向け未読
        createdAt: now,
        updatedAt: now,
      });

      // 最初のメッセージを追加
      await inquiryRef.collection("messages").add({
        senderId: userId,
        senderName: userDisplayName,
        senderType: "user",
        content,
        imageUrl: imageUrl || null,
        createdAt: now,
      });

      // 管理者に通知を送信
      for (const adminUid of adminUids) {
        const notifyBody = `${userDisplayName}さんから問い合わせ「${subject}」が届きました`;
        await db
          .collection("users")
          .doc(adminUid)
          .collection("notifications")
          .add({
            type: "inquiry_received",
            title: "新規問い合わせ",
            body: notifyBody,
            senderId: userId,
            senderName: userDisplayName,
            senderAvatarUrl: String(userAvatarIndex),
            inquiryId: inquiryRef.id,
            isRead: false,
            createdAt: now,
          });
        // プッシュ通知はonNotificationCreatedが自動送信
      }

      console.log(`Created inquiry: ${inquiryRef.id}`);

      return { success: true, inquiryId: inquiryRef.id };
    } catch (error) {
      console.error("Error creating inquiry:", error);
      throw new HttpsError("internal", "問い合わせの作成に失敗しました");
    }
  }
);

/**
 * ユーザーがメッセージを送信
 */
export const sendInquiryMessage = onCall(
  { region: LOCATION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const { inquiryId, content, imageUrl } = request.data;

    if (!inquiryId || !content) {
      throw new HttpsError("invalid-argument", "問い合わせIDと内容は必須です");
    }

    console.log(`=== sendInquiryMessage: inquiryId=${inquiryId} ===`);

    // 管理者UID一覧を取得
    const adminUids = await getAdminUids();

    try {
      // 問い合わせの存在と所有者確認
      const inquiryRef = db.collection("inquiries").doc(inquiryId);
      const inquiryDoc = await inquiryRef.get();

      if (!inquiryDoc.exists) {
        throw new HttpsError("not-found", "問い合わせが見つかりません");
      }

      const inquiryData = inquiryDoc.data()!;
      if (inquiryData.userId !== userId) {
        throw new HttpsError(
          "permission-denied",
          "この問い合わせにはアクセスできません"
        );
      }

      // ユーザー情報を取得
      const userDoc = await db.collection("users").doc(userId).get();
      const userData = userDoc.data();
      const userDisplayName = userData?.displayName || "匿名ユーザー";
      const userAvatarIndex = userData?.avatarIndex || 0;

      const now = FieldValue.serverTimestamp();

      // メッセージを追加
      await inquiryRef.collection("messages").add({
        senderId: userId,
        senderName: userDisplayName,
        senderType: "user",
        content,
        imageUrl: imageUrl || null,
        createdAt: now,
      });

      // 問い合わせを更新
      await inquiryRef.update({
        hasUnreadMessage: true, // 管理者向け未読
        updatedAt: now,
      });

      // 管理者が閲覧中でない場合のみ通知を送信
      if (!inquiryData.adminViewing) {
        // 管理者に通知を送信
        for (const adminUid of adminUids) {
          const notifyBody = `${userDisplayName}さんが「${inquiryData.subject}」に返信しました`;
          await db
            .collection("users")
            .doc(adminUid)
            .collection("notifications")
            .add({
              type: "inquiry_user_reply",
              title: "問い合わせに返信",
              body: notifyBody,
              senderId: userId,
              senderName: userDisplayName,
              senderAvatarUrl: String(userAvatarIndex),
              inquiryId,
              isRead: false,
              createdAt: now,
            });
          // プッシュ通知はonNotificationCreatedが自動送信
        }
      } else {
        console.log(
          `Admin is viewing inquiry ${inquiryId}, skipping notification`
        );
      }

      console.log(`Added message to inquiry: ${inquiryId}`);

      return { success: true };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("Error sending inquiry message:", error);
      throw new HttpsError("internal", "メッセージの送信に失敗しました");
    }
  }
);

/**
 * 管理者が返信を送信
 */
export const sendInquiryReply = onCall(
  { region: LOCATION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const adminId = request.auth.uid;
    const { inquiryId, content } = request.data;

    // 管理者チェック
    const adminIsAdmin = await isAdmin(adminId);
    if (!adminIsAdmin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    if (!inquiryId || !content) {
      throw new HttpsError("invalid-argument", "問い合わせIDと内容は必須です");
    }

    console.log(`=== sendInquiryReply: inquiryId=${inquiryId} ===`);

    try {
      const inquiryRef = db.collection("inquiries").doc(inquiryId);
      const inquiryDoc = await inquiryRef.get();

      if (!inquiryDoc.exists) {
        throw new HttpsError("not-found", "問い合わせが見つかりません");
      }

      const inquiryData = inquiryDoc.data()!;
      const now = FieldValue.serverTimestamp();

      // 返信メッセージを追加
      await inquiryRef.collection("messages").add({
        senderId: adminId,
        senderName: "運営チーム",
        senderType: "admin",
        content,
        imageUrl: null,
        createdAt: now,
      });

      // 問い合わせを更新
      await inquiryRef.update({
        hasUnreadReply: true, // ユーザー向け未読
        hasUnreadMessage: false, // 管理者は既読
        status: "in_progress", // 対応中に変更
        updatedAt: now,
      });

      // ユーザーが閲覧中でない場合のみ通知を送信
      if (!inquiryData.userViewing) {
        // ユーザーに通知を送信
        const targetUserId = inquiryData.userId;
        const notifyBody = `「${inquiryData.subject}」に運営チームから返信があります`;
        await db
          .collection("users")
          .doc(targetUserId)
          .collection("notifications")
          .add({
            type: "inquiry_reply",
            title: "問い合わせに返信がありました",
            body: notifyBody,
            inquiryId,
            isRead: false,
            createdAt: now,
          });
        // プッシュ通知はonNotificationCreatedが自動送信
      } else {
        console.log(
          `User is viewing inquiry ${inquiryId}, skipping notification`
        );
      }

      console.log(`Sent reply to inquiry: ${inquiryId}`);

      return { success: true };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("Error sending inquiry reply:", error);
      throw new HttpsError("internal", "返信の送信に失敗しました");
    }
  }
);

/**
 * 問い合わせステータスを変更（スプレッドシート連携オプション付き）
 */
export const updateInquiryStatus = onCall(
  { region: LOCATION, secrets: [sheetsServiceAccountKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const adminId = request.auth.uid;
    const {
      inquiryId,
      status,
      saveToSpreadsheet = false,
      resolutionCategory = "",
      remarks = "",
    } = request.data;

    // 管理者チェック
    const adminIsAdmin = await isAdmin(adminId);
    if (!adminIsAdmin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    if (!inquiryId || !status) {
      throw new HttpsError(
        "invalid-argument",
        "問い合わせIDとステータスは必須です"
      );
    }

    // 有効なステータスかチェック
    const VALID_STATUSES = ["open", "in_progress", "resolved"];
    if (!VALID_STATUSES.includes(status)) {
      throw new HttpsError("invalid-argument", "無効なステータスです");
    }

    console.log(
      `=== updateInquiryStatus: inquiryId=${inquiryId}, status=${status}, saveToSpreadsheet=${saveToSpreadsheet} ===`
    );

    try {
      const inquiryRef = db.collection("inquiries").doc(inquiryId);
      const inquiryDoc = await inquiryRef.get();

      if (!inquiryDoc.exists) {
        throw new HttpsError("not-found", "問い合わせが見つかりません");
      }

      const inquiryData = inquiryDoc.data()!;
      const now = FieldValue.serverTimestamp();
      const nowDate = new Date();

      // ステータスを更新
      const updateData: { [key: string]: unknown } = {
        status,
        updatedAt: now,
      };

      // 解決済みの場合、resolvedAtを記録
      if (status === "resolved") {
        updateData.resolvedAt = now;
      } else {
        // 解決済み以外に変更された場合、resolvedAtを削除（カウントリセット）
        updateData.resolvedAt = FieldValue.delete();
      }

      await inquiryRef.update(updateData);

      // ステータスのラベルを取得
      const statusLabels: { [key: string]: string } = {
        open: "未対応",
        in_progress: "対応中",
        resolved: "解決済み",
      };
      const statusLabel = statusLabels[status] || status;

      // スプレッドシートに保存（解決済み かつ オプションONの場合）
      if (status === "resolved" && saveToSpreadsheet) {
        // 全メッセージを取得して会話ログを作成
        const messagesSnapshot = await inquiryRef
          .collection("messages")
          .orderBy("createdAt", "asc")
          .get();

        let conversationLog = "";
        let firstMessage = "";

        messagesSnapshot.docs.forEach((doc, index) => {
          const msg = doc.data();
          const msgDate = msg.createdAt?.toDate?.() || new Date();
          const dateStr = `${msgDate.getFullYear()}-${String(
            msgDate.getMonth() + 1
          ).padStart(2, "0")}-${String(msgDate.getDate()).padStart(
            2,
            "0"
          )} ${String(msgDate.getHours()).padStart(2, "0")}:${String(
            msgDate.getMinutes()
          ).padStart(2, "0")}`;
          const sender = msg.senderType === "admin" ? "運営チーム" : "ユーザー";
          conversationLog += `[${dateStr} ${sender}]\n${msg.content}\n\n`;

          if (index === 0) {
            firstMessage = msg.content || "";
          }
        });

        // 問い合わせ作成日時
        const createdAtDate = inquiryData.createdAt?.toDate?.() || new Date();
        const createdAtStr = `${createdAtDate.getFullYear()}-${String(
          createdAtDate.getMonth() + 1
        ).padStart(2, "0")}-${String(createdAtDate.getDate()).padStart(
          2,
          "0"
        )} ${String(createdAtDate.getHours()).padStart(2, "0")}:${String(
          createdAtDate.getMinutes()
        ).padStart(2, "0")}`;

        // 解決日時
        const resolvedAtStr = `${nowDate.getFullYear()}-${String(
          nowDate.getMonth() + 1
        ).padStart(2, "0")}-${String(nowDate.getDate()).padStart(
          2,
          "0"
        )} ${String(nowDate.getHours()).padStart(2, "0")}:${String(
          nowDate.getMinutes()
        ).padStart(2, "0")}`;

        // カテゴリラベル
        const categoryLabels: { [key: string]: string } = {
          bug: "バグ報告",
          feature: "機能要望",
          account: "アカウント関連",
          other: "その他",
        };
        const categoryLabel =
          categoryLabels[inquiryData.category] || inquiryData.category;

        await appendInquiryToSpreadsheet({
          inquiryId,
          userId: inquiryData.userId,
          category: categoryLabel,
          subject: inquiryData.subject,
          firstMessage,
          conversationLog: conversationLog.trim(),
          resolvedAt: resolvedAtStr,
          resolutionCategory,
          remarks,
          createdAt: createdAtStr,
        });
      }

      // ユーザーに通知を送信
      const targetUserId = inquiryData.userId;
      const notifyBody = `「${inquiryData.subject}」のステータスが「${statusLabel}」に変更されました`;
      await db
        .collection("users")
        .doc(targetUserId)
        .collection("notifications")
        .add({
          type: "inquiry_status_changed",
          title: "問い合わせステータス変更",
          body: notifyBody,
          inquiryId,
          isRead: false,
          createdAt: now,
        });
      // プッシュ通知はonNotificationCreatedが自動送信

      console.log(`Updated inquiry status: ${inquiryId} -> ${status}`);

      return { success: true };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      console.error("Error updating inquiry status:", error);
      throw new HttpsError("internal", "ステータスの変更に失敗しました");
    }
  }
);
