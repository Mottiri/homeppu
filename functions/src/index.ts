import { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } from "firebase-functions/v2/firestore";
import * as functionsV1 from "firebase-functions/v1";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions } from "firebase-functions/v2"; // Global Options

import * as admin from "firebase-admin";
import { GoogleGenerativeAI, Part, GenerativeModel } from "@google/generative-ai";


import { CloudTasksClient } from "@google-cloud/tasks";
import { google } from "googleapis";

import { AIProviderFactory } from "./ai/provider";
import { PROJECT_ID, LOCATION, QUEUE_NAME, SPREADSHEET_ID } from "./config/constants";
import { geminiApiKey, openaiApiKey, sheetsServiceAccountKey } from "./config/secrets";
import { isAdmin, getAdminUids } from "./helpers/admin";
import { deleteStorageFileFromUrl } from "./helpers/storage";
import { appendInquiryToSpreadsheet } from "./helpers/spreadsheet";
import { NegativeCategory, ModerationResult, MediaModerationResult, MediaItem } from "./types";
import {
  Gender,
  AgeGroup,
  OCCUPATIONS,
  PERSONALITIES,
  PRAISE_STYLES,
  AGE_GROUPS,
  NamePart,
  PREFIX_PARTS,
  SUFFIX_PARTS,
  AIPersona,
  BIO_TEMPLATES,
  AI_USABLE_PREFIXES,
  AI_USABLE_SUFFIXES,
  generateAIPersona,
  AI_PERSONAS,
  getSystemPrompt,
  getCircleSystemPrompt,
} from "./ai/personas";


// 分離されたモジュールの再エクスポート
export { initializeNameParts, getNameParts, updateUserName } from "./callable/names";
export { reportContent } from "./callable/reports";
export { createTask, getTasks } from "./callable/tasks";
export {
  createInquiry,
  sendInquiryMessage,
  sendInquiryReply,
  updateInquiryStatus,
} from "./callable/inquiries";

// Phase 4: サークル関連
export {
  deleteCircle,
  cleanupDeletedCircle,
  approveJoinRequest,
  rejectJoinRequest,
  sendJoinRequest,
} from "./callable/circles";
export { onCircleCreated, onCircleUpdated } from "./triggers/circles";
export {
  generateCircleAIPosts,
  executeCircleAIPost,
  triggerCircleAIPosts,
} from "./circle-ai/posts";
export {
  checkGhostCircles,
  evolveCircleAIs,
  triggerEvolveCircleAIs,
} from "./scheduled/circles";

// Phase 5: 投稿コメントリアクション関連
export { onPostCreated } from "./triggers/posts";
export { createPostWithRateLimit, createPostWithModeration } from "./callable/posts";
export { initializeAIAccounts, generateAIPosts } from "./callable/ai";
export { scheduleAIPosts } from "./scheduled/ai-posts";

admin.initializeApp();
const db = admin.firestore();

// Set global options for v2 functions
setGlobalOptions({ region: "asia-northeast1" });

// ===============================================
// ヘルパー関数
// ===============================================

/**
 * AIProviderFactoryを作成するヘルパー関数
 * 関数内でSecretにアクセスし、ファクトリーを返す
 */
function createAIProviderFactory(): AIProviderFactory {
  const geminiKey = geminiApiKey.value() || "";
  const openaiKey = openaiApiKey.value() || "";
  return new AIProviderFactory(geminiKey, openaiKey);
}

// ===============================================
// 徳システム設定
// ===============================================
const VIRTUE_CONFIG = {
  initial: 100,           // 初期徳ポイント
  maxDaily: 50,           // 1日の最大獲得量
  banThreshold: 0,        // BAN閾値
  lossPerNegative: 15,    // ネガティブ発言1回あたりの減少
  lossPerReport: 20,      // 通報1回あたりの減少
  gainPerPraise: 5,       // 称賛1回あたりの増加
  warningThreshold: 30,   // 警告表示閾値
};

// ===============================================
// プッシュ通知送信ヘルパー（サポート通知用）
// ===============================================

/**
 * 指定ユーザーにプッシュ通知のみを送信（Firestore保存なし）
 */
async function sendPushOnly(
  userId: string,
  title: string,
  body: string,
  data?: Record<string, unknown>
): Promise<void> {
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;

    if (!fcmToken) {
      console.log(`No FCM token for user ${userId}, skipping push notification`);
      return;
    }

    // チャンネルIDの決定
    let channelId = "default_channel";
    if (data?.type === "task_reminder" || data?.type === "task_due") {
      channelId = "task_reminders";
    }

    // FCM dataペイロードは全て文字列である必要があるため変換
    const stringifiedData: { [key: string]: string } = {};
    if (data) {
      for (const [key, value] of Object.entries(data)) {
        if (value !== undefined && value !== null) {
          // Timestamp オブジェクトの場合は toDate().toISOString() を使用
          if (typeof value === "object" && "toDate" in value && typeof value.toDate === "function") {
            stringifiedData[key] = value.toDate().toISOString();
          } else {
            stringifiedData[key] = String(value);
          }
        }
      }
    }

    const message: admin.messaging.Message = {
      token: fcmToken,
      notification: {
        title,
        body,
      },
      data: stringifiedData,
      android: {
        priority: "high",
        notification: {
          channelId,
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    await admin.messaging().send(message);
    console.log(`Push notification sent to user ${userId}: ${title} (channel: ${channelId})`);
  } catch (error: unknown) {
    // トークンが無効な場合はトークンを削除
    if (error && typeof error === "object" && "code" in error) {
      const firebaseError = error as { code: string };
      if (
        firebaseError.code === "messaging/invalid-registration-token" ||
        firebaseError.code === "messaging/registration-token-not-registered"
      ) {
        console.log(`Removing invalid FCM token for user ${userId}`);
        await db.collection("users").doc(userId).update({
          fcmToken: admin.firestore.FieldValue.delete(),
        });
      }
    }
    console.error(`Error sending push notification to ${userId}:`, error);
  }
}

// Google Sheets ヘルパー: helpers/spreadsheet.ts に移動


// メディアモデレーション・投稿関連は Phase 5 モジュールに移動済み

// AIの投稿テンプレート（職業・性格に応じた内容を動的に生成するための基本パターン）
// executeAIPostGeneration で使用
const POST_TEMPLATES_BY_OCCUPATION: Record<string, string[]> = {
  college_student: [
    "今日のレポート、なんとか終わった！期限ギリギリだったけど頑張った",
    "サークルの活動楽しかった！いい仲間がいるって幸せだな",
    "テスト勉強中...集中力が切れてきたけどもうひと踏ん張り！",
    "新しいカフェ発見した！勉強する場所増えて嬉しい",
    "バイト終わり！今日も忙しかったけど達成感ある",
  ],
  sales: [
    "今月の目標達成！チームのみんなのおかげ！",
    "新しいお客様と良い関係を築けた気がする",
    "プレゼン資料作り終わった...明日の商談頑張る",
    "先輩からのアドバイスで気づきがあった",
    "今日は契約取れた！嬉しい！！",
  ],
  engineer: [
    "新機能リリースできた！ユーザーの反応楽しみ",
    "バグ直した...原因見つけるまで長かったけど達成感",
    "コードレビューで学びがあった",
    "新しい技術試してみた。面白い",
    "今日のタスク全部終わった！明日も頑張ろ",
  ],
  nurse: [
    "患者さんから「ありがとう」って言われた...元気もらえる",
    "夜勤明け！今日もみんな無事で何より",
    "新人さんのフォローしてたら自分も勉強になった",
    "忙しかったけど、チームワークで乗り越えた",
    "久しぶりの連休！ゆっくり休もう",
  ],
  designer: [
    "デザイン採用された！嬉しい！",
    "クライアントさんに喜んでもらえた",
    "新しいツール使ってみたら作業効率上がった",
    "今日のデザイン、いい感じにできた気がする",
    "展示会で刺激もらった！創作意欲湧いてきた",
  ],
  teacher: [
    "生徒たちの成長を感じた一日だった",
    "授業準備完了！明日も頑張ろう",
    "保護者さんとの面談、いい話ができた",
    "テストの採点終わった！みんな頑張ってた",
    "今日は生徒たちと楽しく過ごせた",
  ],
  freelancer: [
    "納品完了！クライアントさんに喜んでもらえた",
    "新しい案件の依頼きた！ありがたい",
    "確定申告の準備進めた。少しずつだけど進んでる",
    "オンラインミーティング上手くいった",
    "今日は作業捗った！この調子で頑張る",
  ],
  homemaker: [
    "今日の夕飯、家族に好評だった",
    "大掃除完了！スッキリ！",
    "子どもの成長を感じた一日",
    "新しいレシピに挑戦してみた",
    "午前中に用事を全部終わらせた！えらい！",
  ],
};





// ===============================================
// 通報機能 → callable/reports.ts に移動
// ===============================================

// ===============================================
// フォロー機能
// ===============================================

/**
 * ユーザーをフォローする
 */
export const followUser = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const currentUserId = request.auth.uid;
    const { targetUserId } = request.data;

    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "フォロー対象のユーザーIDが必要です");
    }

    if (currentUserId === targetUserId) {
      throw new HttpsError("invalid-argument", "自分自身をフォローすることはできません");
    }

    const batch = db.batch();
    const currentUserRef = db.collection("users").doc(currentUserId);
    const targetUserRef = db.collection("users").doc(targetUserId);

    // 対象ユーザーが存在するか確認
    const targetUser = await targetUserRef.get();
    if (!targetUser.exists) {
      throw new HttpsError("not-found", "ユーザーが見つかりません");
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
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const currentUserId = request.auth.uid;
    const { targetUserId } = request.data;

    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "フォロー解除対象のユーザーIDが必要です");
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
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const currentUserId = request.auth.uid;
    const { targetUserId } = request.data;

    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "ユーザーIDが必要です");
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
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;

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
  { region: "asia-northeast1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const userDoc = await db.collection("users").doc(userId).get();

    if (!userDoc.exists) {
      throw new HttpsError("not-found", "ユーザーが見つかりません");
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

// ===============================================
// タスク機能 (callable/tasks.ts に移動)
// - createTask, getTasks
// ===============================================

/**
 * (Trigger) タスクが更新された時の処理
 * - 完了状態になった場合: 徳ポイントとストリークの計算
 */
export const onTaskUpdated = onDocumentUpdated("tasks/{taskId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();

  if (!before || !after) return;

  // 1. 完了状態への変化を検知 (false -> true)
  if (!before.isCompleted && after.isCompleted) {
    const userId = after.userId;

    // ストリーク計算のための前回完了日時取得
    // Firestore上で、このユーザーの直近の完了タスク(自分以外)を取得
    // ※単純化のため、Userドキュメントに持たせるのがベストだが、ここではクエリで頑張るか、
    // あるいはTaskService側でStreakを計算して投げているのを「正」とするか？
    // -> セキュリティ重視ならサーバーで計算すべき。
    // しかしクエリコストが高い。
    // 折衷案: ユーザーデータに `lastTaskCompletedAt` と `currentStreak` を持たせる。

    const userRef = db.collection("users").doc(userId);

    await db.runTransaction(async (transaction) => {
      const userDoc = await transaction.get(userRef);
      if (!userDoc.exists) return; // ユーザーがいない

      const userData = userDoc.data()!;
      const now = new Date();
      const lastCompleted = userData.lastTaskCompletedAt?.toDate();

      let newStreak = 1;
      let streakBonus = 0;

      if (lastCompleted) {
        // 日付の差分計算 (JST考慮が必要だが、UTCベースの日付差分で簡易判定)
        // 厳密には「営業日」的なロジックが必要だが、24時間以内かどうか等で判定
        const diffTime = now.getTime() - lastCompleted.getTime();
        const diffDays = diffTime / (1000 * 3600 * 24);

        if (diffDays < 1.5 && now.getDate() !== lastCompleted.getDate()) {
          // "昨日"完了している（大体36時間以内かつ日付が違う）
          // ※もっと厳密なロジックは必要だが、一旦簡易実装
          newStreak = (userData.currentStreak || 0) + 1;
        } else if (now.getDate() === lastCompleted.getDate()) {
          // 今日すでに完了している -> ストリーク維持
          newStreak = userData.currentStreak || 1;
        } else {
          // 途切れた
          newStreak = 1;
        }
      }

      // ポイント計算
      const baseVirtue = 2;
      streakBonus = Math.min(newStreak - 1, 5);
      const virtueGain = baseVirtue + streakBonus;

      // User更新
      transaction.update(userRef, {
        virtue: admin.firestore.FieldValue.increment(virtueGain),
        currentStreak: newStreak,
        lastTaskCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 履歴記録
      const historyRef = db.collection("virtueHistory").doc();
      transaction.set(historyRef, {
        userId: userId,
        change: virtueGain,
        reason: `タスク完了: ${after.content} ${newStreak > 1 ? `(${newStreak}連!)` : ''}`,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // タスク自体のStreak値も更新しておく（事後更新になるが結果整合性）
      // ※トリガー内で自身のドキュメントを更新すると無限ループのリスクがあるため注意。
      // ここでは `streak` が変化した場合のみ...だが、今回はやめておく。
      // アプリ側で表示用Streakは計算済みのはず。
    });
  }

  // 2. 完了取り消し (true -> false)
  if (before.isCompleted && !after.isCompleted) {
    // ポイント減算
    const userId = after.userId;
    // 減算ロジックは複雑（どのボーナス分だったか不明）なので、一律 -2 とする、等の運用が一般的
    // ここでは簡易的に Base + StreakBonus(Userの現在値から推測) を引く

    await db.runTransaction(async (transaction) => {
      const userRef = db.collection("users").doc(userId);
      transaction.update(userRef, {
        virtue: admin.firestore.FieldValue.increment(-2), // 最低限引く
      });

      // 履歴
      const historyRef = db.collection("virtueHistory").doc();
      transaction.set(historyRef, {
        userId: userId,
        change: -2,
        reason: `タスク完了取消: ${after.content}`,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  }
});



// ===============================================
// 名前パーツ方式 → callable/names.ts に移動
// ===============================================

// ===============================================
// プッシュ通知
// ===============================================

/**
 * プッシュ通知を送信
 */
async function sendPushNotification(
  userId: string,
  title: string,
  body: string,
  data: { [key: string]: string } = {},
  options?: {
    type: "comment" | "reaction" | "system";
    senderId: string;
    senderName: string;
    senderAvatarUrl?: string; // アイコンURLまたはインデックス
  }
) {
  try {
    // 1. Firestoreに通知ドキュメントを保存 (オプション指定時)
    if (options) {
      await db.collection("users").doc(userId).collection("notifications").add({
        userId: userId,
        senderId: options.senderId,
        senderName: options.senderName,
        senderAvatarUrl: options.senderAvatarUrl || "",
        type: options.type,
        title: title,
        body: body,
        postId: data.postId || null,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`Notification saved to Firestore for user: ${userId}`);
    }

    // 2. FCMトークン取得
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      console.log(`User not found: ${userId} `);
      return;
    }

    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;

    if (!fcmToken) {
      console.log(`No FCM token for user: ${userId} `);
      return;
    }

    // 2.5 通知設定の確認
    if (options && userData?.notificationSettings) {
      const type = options.type;
      // 設定キーへのマッピング (comment -> comments, reaction -> reactions)
      const settingKey = type === "comment" ? "comments" : type === "reaction" ? "reactions" : null;

      if (settingKey && userData.notificationSettings[settingKey] === false) {
        console.log(`Notification skipped due to user setting: ${type} for user ${userId}`);
        return;
      }
    }

    // 3. FCM送信
    // dataにはtype, postId等を含める（クライアントの通知タップ時ナビゲーション用）
    const fcmData: { [key: string]: string } = {
      ...data,
    };
    if (options?.type) {
      fcmData.type = options.type;
    }

    const message = {
      token: fcmToken,
      notification: {
        title,
        body,
      },
      data: fcmData,
      android: {
        priority: "high" as const,
        notification: {
          sound: "default",
          channelId: "default_channel",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    await admin.messaging().send(message);
    console.log(`Push notification sent to ${userId}: ${title} `);
  } catch (error) {
    console.error(`Failed to send push notification to ${userId}: `, error);
  }
}

/**
 * コメント作成時に投稿者へ通知
 */
export const onCommentCreatedNotify = onDocumentCreated(
  {
    document: "comments/{commentId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const commentData = snap.data();
    const postId = commentData.postId;
    const commenterName = commentData.userDisplayName;
    const commenterId = commentData.userId;
    // AIかどうかに関わらず通知（コンセプト: AIと人間の区別をつけない）

    // 投稿を取得
    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists) return;

    const postData = postDoc.data();
    const postOwnerId = postData?.userId;

    // 自分へのコメントは通知しない
    console.log(`Comment Notification Check: postOwner = ${postOwnerId}, commenter = ${commenterId} `);

    // 文字列として確実に比較（空白除去なども念のため）
    if (String(postOwnerId).trim() === String(commenterId).trim()) {
      console.log("Skipping self-comment notification");
      return;
    }

    // 未来の投稿（AIの予約投稿）の場合は通知しない
    // Note: クライアント側で表示される時間になったら通知を送る仕組みが必要（現在はCronジョブ等がないためスキップのみ）
    if (commentData.scheduledAt) {
      const scheduledAt = commentData.scheduledAt.toDate();
      const now = new Date();
      if (scheduledAt > now) {
        console.log(`Skipping notification for scheduled comment(scheduledAt: ${scheduledAt.toISOString()})`);
        return;
      }
    }

    // 通知を送信
    await sendPushNotification(
      postOwnerId,
      "コメント",
      `${commenterName}さんがコメントしました`,
      { postId },
      {
        type: "comment",
        senderId: commenterId,
        senderName: commenterName,
        senderAvatarUrl: String(commentData.userAvatarIndex ?? ""), // アバターインデックスを文字列として保存
      }
    );
  }
);

/**
 * リアクション追加時に投稿者へ通知
 */
export const onReactionAddedNotify = onDocumentCreated(
  {
    document: "reactions/{reactionId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const reactionData = snap.data();
    const postId = reactionData.postId;
    const reactorId = reactionData.userId;
    const reactorName = reactionData.userDisplayName || "誰か";

    // 投稿を取得
    const postDoc = await db.collection("posts").doc(postId).get();
    if (!postDoc.exists) return;

    const postData = postDoc.data();
    const postOwnerId = postData?.userId;

    // 自分へのリアクションは通知しない
    if (postOwnerId === reactorId) {
      console.log("Skipping self-reaction notification");
      return;
    }

    // 通知を送信
    await sendPushNotification(
      postOwnerId,
      "リアクション",
      `${reactorName}さんがリアクションしました`,
      { postId },
      {
        type: "reaction",
        senderId: reactorId,
        senderName: reactorName,
        senderAvatarUrl: "", // リアクションはアバターURLを持たないので空（クライアント側で適宜処理）
      }
    );
  }
);

/**
 * Cloud Tasks から呼び出される AI コメント生成関数 (v1)
 * v1を使用することでURLを固定化: https://asia-northeast1-positive-sns.cloudfunctions.net/generateAICommentV1
 */
// Imports removed as they are already in scope or invalid

export const generateAICommentV1 = functionsV1.region("asia-northeast1").runWith({
  secrets: ["GEMINI_API_KEY", "OPENAI_API_KEY"],
  timeoutSeconds: 60,
}).https.onRequest(async (request, response) => {
  // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
  const { verifyCloudTasksRequest } = await import("./helpers/cloud-tasks-auth");
  if (!await verifyCloudTasksRequest(request, "generateAICommentV1")) {
    response.status(403).send("Unauthorized");
    return;
  }

  try {
    const {
      postId,
      postContent,
      userDisplayName,
      personaId,
      personaName,
      personaGender,
      personaAgeGroup,
      personaOccupation,
      personaPersonality,
      personaPraiseStyle,
      personaAvatarIndex,
      mediaDescriptions,
      isCirclePost,
      circleName,
      circleDescription,
      circleGoal,
      circleRules,
    } = request.body;

    console.log(`Processing AI comment task for ${personaName} on post ${postId}`);

    // AIProviderFactory経由でテキスト生成
    const aiFactory = createAIProviderFactory();

    // ペルソナを再構築
    // まずAI_PERSONASから検索、見つからなければペイロードから構築
    let persona = AI_PERSONAS.find(p => p.id === personaId);

    if (!persona) {
      // サークルAIの場合、ペイロードからペルソナを構築
      console.log(`Persona ${personaId} not in AI_PERSONAS, using payload data`);

      // ペイロードに personality が含まれていればそれを使用
      // 含まれていなければデフォルトを使用
      const defaultPersonality = PERSONALITIES.female[0]; // 優しい系をデフォルトに

      persona = {
        id: personaId,
        name: personaName,
        namePrefixId: "",
        nameSuffixId: "",
        gender: personaGender || "female" as Gender,
        ageGroup: personaAgeGroup || "twenties" as AgeGroup,
        occupation: personaOccupation || { id: "student", name: "頑張り中", bio: "" },
        personality: personaPersonality || defaultPersonality,
        praiseStyle: personaPraiseStyle || PRAISE_STYLES[0],
        avatarIndex: personaAvatarIndex || 0,
        bio: "",
      };
    }

    // プロンプト構築
    const mediaContext = mediaDescriptions && mediaDescriptions.length > 0
      ? `\n\n【添付メディアの内容】\n${mediaDescriptions.join("\n")}`
      : "";

    // 既存のAIコメントを取得（重複回避のため）
    // 重要: コメントはトップレベルの comments コレクションに保存されている
    const postRef = db.collection("posts").doc(postId);
    let existingCommentsContext = "";
    try {
      console.log(`[DUPLICATE CHECK] Fetching existing AI comments for post: ${postId}`);

      // トップレベルのcommentsコレクションからpostIdでフィルタ
      const existingCommentsSnapshot = await db.collection("comments")
        .where("postId", "==", postId)
        .where("isAI", "==", true)
        .orderBy("createdAt", "asc")
        .limit(10)
        .get();

      console.log(`[DUPLICATE CHECK] Query returned ${existingCommentsSnapshot.size} documents`);

      if (!existingCommentsSnapshot.empty) {
        const existingComments = existingCommentsSnapshot.docs.map((doc, index) => {
          const data = doc.data();
          const commentText = `<comment_${index + 1}>${data.content}</comment_${index + 1}>`;
          console.log(`[DUPLICATE CHECK] Found: ${data.content?.substring(0, 50)}...`);
          return commentText;
        });
        existingCommentsContext = `
<existing_comments>
<instruction>以下は既に投稿されているコメントです。これらと同じフレーズ・表現は使用せず、異なる言い回しで返信してください。</instruction>
${existingComments.join("\n")}
</existing_comments>
`;
        console.log(`[DUPLICATE CHECK] Added ${existingComments.length} comments to context for diversity`);
      } else {
        console.log(`[DUPLICATE CHECK] No existing AI comments found for post ${postId}`);
      }
    } catch (error) {
      console.error("[DUPLICATE CHECK] Error fetching existing comments:", error);
      console.log("Proceeding without diversity check");
    }

    // サークル投稿かどうかでプロンプトを分岐
    let prompt: string;
    if (isCirclePost) {
      // サークル投稿: 専用プロンプトを使用
      prompt = getCircleSystemPrompt(
        persona,
        userDisplayName,
        circleName,
        circleDescription,
        postContent || "(テキストなし)",
        circleGoal,
        circleRules
      );
      // メディアコンテキストと既存コメントコンテキストを追加
      const additionalContext = existingCommentsContext + mediaContext;
      if (additionalContext) {
        // 新しいプロンプト構造では「---」の前に挿入
        prompt = prompt.replace(
          "---\n**上記の投稿に対し",
          additionalContext + "\n\n---\n**上記の投稿に対し"
        );
      }
    } else {
      // 一般投稿: 新しいプロンプト構造を使用
      const basePrompt = getSystemPrompt(persona, userDisplayName);
      const mediaNote = mediaDescriptions && mediaDescriptions.length > 0
        ? "\n\n# Additional Context (メディア情報)\n添付されたメディア（画像・動画）の内容も考慮して、具体的に褒めてください。"
        : "";

      prompt = `
${basePrompt}

# Input Data (今回の投稿)

<poster_name>${userDisplayName}</poster_name>
<post_content>
${postContent || "(テキストなし)"}
</post_content>
${mediaContext}
${existingCommentsContext}${mediaNote}

---
**上記の投稿に対し、思考プロセスや前置きを一切含めず、返信コメントのみを出力してください。**
`;
    }

    // プロンプト全文をログ出力（デバッグ用）
    console.log(`[AI PROMPT DEBUG] ===== PROMPT START =====`);
    console.log(prompt);
    console.log(`[AI PROMPT DEBUG] ===== PROMPT END =====`);

    const aiResult = await aiFactory.generateText(prompt);
    const commentText = aiResult.text?.trim();
    console.log(`AI comment generated by ${aiResult.provider}${aiResult.usedFallback ? " (fallback)" : ""}`);

    if (!commentText || commentText === "SKIP_COMMENT") {
      console.log(`Skipping comment: ${commentText || "Empty"}`);
      response.status(200).send("Comment skipped");
      return;
    }

    // リアクションもランダムで送信 (ポジティブなものから選択)
    const POSITIVE_REACTIONS = ["love", "praise", "cheer", "sparkles", "clap", "thumbsup", "smile"];
    const reactionType = POSITIVE_REACTIONS[Math.floor(Math.random() * POSITIVE_REACTIONS.length)];

    // 投稿が存在するか確認（Cloud Tasksの遅延実行中に削除された可能性）
    // postRefは既に上で宣言済み
    const postDoc = await postRef.get();
    if (!postDoc.exists) {
      console.warn(`Post ${postId} not found, skipping AI comment`);
      response.status(200).send("Post not found, skipping");
      return;
    }

    // バッチ書き込みで一括処理
    const batch = db.batch();

    // 1. コメント保存
    const commentRef = db.collection("comments").doc();
    batch.set(commentRef, {
      postId: postId,
      userId: persona.id,
      userDisplayName: persona.name,
      userAvatarIndex: persona.avatarIndex,
      isAI: true,
      content: commentText,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. リアクション保存 (通知トリガー用)
    const reactionRef = db.collection("reactions").doc();
    batch.set(reactionRef, {
      postId: postId,
      userId: persona.id,
      userDisplayName: persona.name,
      reactionType: reactionType,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 3. 投稿のリアクションカウント・コメント数を更新
    batch.update(postRef, {
      [`reactions.${reactionType}`]: admin.firestore.FieldValue.increment(1),
      commentCount: admin.firestore.FieldValue.increment(1),
    });

    await batch.commit();

    console.log(`AI comment and reaction posted: ${persona.name} (Reaction: ${reactionType})`);
    response.status(200).send("Comment and reaction posted successfully");

  } catch (error) {
    console.error("Error in generateAIComment:", error);
    response.status(500).send("Internal Server Error");
  }
}
);

// ===============================================
// モデレーション機能 (onCall)
// ===============================================

/**
 * テキストのモデレーション判定 (Gemini)
 */
async function moderateText(text: string, postContent: string = ""): Promise<ModerationResult> {
  // 短すぎる場合はスキップ
  if (!text || text.length < 2) {
    return { isNegative: false, category: "none", confidence: 0, reason: "", suggestion: "" };
  }

  const apiKey = geminiApiKey.value();
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

  const prompt = `
あなたはSNSのコミュニティマネージャーです。以下のテキストが、ポジティブで優しいSNS「ほめっぷ」にふさわしいかどうか（攻撃的、誹謗中傷、不適切でないか）を判定してください。
文脈として、ユーザーは「投稿内容」に対して「コメント」をしようとしています。
たとえ一見普通の言葉でも、文脈によって嫌味や攻撃になる場合はネガティブと判定してください。
特に「死ね」「殺す」「きもい」などの直接的な暴言・攻撃は厳しく判定してください。

【投稿内容】
"${postContent}"

【コメントしようとしている内容】
"${text}"

以下のJSON形式のみで回答してください:
{
  "isNegative": boolean, // ネガティブ（不適切）ならtrue
  "category": "harassment" | "hate_speech" | "profanity" | "self_harm" | "spam" | "none",
  "confidence": number, // 0.0〜1.0 (確信度)
  "reason": "判定理由（ユーザーに簡潔に伝える用）",
  "suggestion": "より優しい言い方の提案（もしあれば）"
}
`;

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
  } catch (e) {
    console.error("Moderation AI Error:", e);
    // エラー時は安全側に倒してスルー（または厳しくするか要検討）
    return { isNegative: false, category: "none", confidence: 0, reason: "", suggestion: "" };
  }
}

/**
 * 徳ポイントの更新（減少処理）
 */
async function penalizeUser(userId: string, penalty: number, reason: string) {
  const userRef = db.collection("users").doc(userId);

  await db.runTransaction(async (t) => {
    const doc = await t.get(userRef);
    if (!doc.exists) return;

    const currentVirtue = doc.data()?.virtue || 100;
    const newVirtue = Math.max(0, currentVirtue - penalty);

    t.update(userRef, { virtue: newVirtue });

    // 履歴追加
    const historyRef = db.collection("virtueHistory").doc();
    t.set(historyRef, {
      userId,
      change: -penalty,
      reason,
      newVirtue,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

/**
 * モデレーション付きコメント作成
 */
export const createCommentWithModeration = onCall(
  {
    region: "asia-northeast1",
    secrets: [geminiApiKey],
  },
  async (request) => {
    // 認証チェック
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be logged in");
    }

    const { postId, content, userDisplayName, userAvatarIndex } = request.data;
    const userId = request.auth.uid;

    if (!postId || !content) {
      throw new HttpsError("invalid-argument", "Missing postId or content");
    }

    // ユーザーがBANされているかチェック
    const userDoc = await db.collection("users").doc(userId).get();
    if (userDoc.exists && userDoc.data()?.isBanned) {
      throw new HttpsError(
        "permission-denied",
        "アカウントが制限されているため、現在この機能は使用できません。マイページ画面から運営へお問い合わせください。"
      );
    }

    // 投稿のコンテキストを取得
    let postContentText = "";
    try {
      const postDoc = await db.collection("posts").doc(postId).get();
      if (postDoc.exists) {
        postContentText = postDoc.data()?.content || "";
      }
    } catch (e) {
      console.warn(`Failed to fetch post context for moderation: ${postId}`, e);
    }

    // 1. モデレーション実行（コンテキスト付き）
    const moderation = await moderateText(content, postContentText);
    if (moderation.isNegative && moderation.confidence > 0.7) {
      // 徳ポイント減少
      await penalizeUser(userId, VIRTUE_CONFIG.lossPerNegative, `不適切な発言: ${moderation.category}`);

      throw new HttpsError(
        "invalid-argument",
        moderation.reason || "不適切な内容が含まれています",
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
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isVisibleNow: true, // 即時表示
    });

    // 3. 投稿のコメント数を更新
    await db.collection("posts").doc(postId).update({
      commentCount: admin.firestore.FieldValue.increment(1)
    });

    return { commentId: commentRef.id };
  }
);

/**
 * ユーザーリアクション追加関数
 * 1人あたり1投稿に対して最大5回までの制限あり
 */
export const addUserReaction = onCall(
  { region: LOCATION, enforceAppCheck: false },
  async (request) => {
    const { postId, reactionType } = request.data;
    const userId = request.auth?.uid;

    if (!userId) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    if (!postId || !reactionType) {
      throw new HttpsError("invalid-argument", "postIdとreactionTypeが必要です");
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
        `1つの投稿に対するリアクションは${MAX_REACTIONS_PER_USER}回までです`
      );
    }

    // ユーザー情報を取得
    const userDoc = await db.collection("users").doc(userId).get();
    const displayName = userDoc.data()?.displayName || "ユーザー";

    const batch = db.batch();

    // 1. リアクション保存
    const reactionRef = db.collection("reactions").doc();
    batch.set(reactionRef, {
      postId: postId,
      userId: userId,
      userDisplayName: displayName,
      reactionType: reactionType,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. 投稿のリアクションカウント更新
    const postRef = db.collection("posts").doc(postId);
    batch.update(postRef, {
      [`reactions.${reactionType}`]: admin.firestore.FieldValue.increment(1),
    });

    await batch.commit();

    console.log(`User reaction added: ${displayName} -> ${reactionType} on ${postId}`);
    return {
      success: true,
      remainingReactions: MAX_REACTIONS_PER_USER - existingReactions.size - 1
    };
  }
);

/**
 * Cloud Tasks から呼び出される AI リアクション生成関数 (v1)
 * 単体リアクション用
 */
export const generateAIReactionV1 = functionsV1.region("asia-northeast1").https.onRequest(async (request, response) => {
  // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
  const { verifyCloudTasksRequest } = await import("./helpers/cloud-tasks-auth");
  if (!await verifyCloudTasksRequest(request, "generateAIReactionV1")) {
    response.status(403).send("Unauthorized");
    return;
  }

  try {
    const { postId, personaId, personaName, reactionType } = request.body;

    console.log(`Processing AI reaction task for ${personaName} on post ${postId} (Type: ${reactionType})`);

    const persona = AI_PERSONAS.find(p => p.id === personaId);
    if (!persona) {
      response.status(400).send("Persona not found");
      return;
    }

    // 重複チェック: この AI が既にこの投稿にリアクションしているか確認
    const existingReaction = await db.collection("reactions")
      .where("postId", "==", postId)
      .where("userId", "==", persona.id)
      .limit(1)
      .get();

    if (!existingReaction.empty) {
      console.log(`Skipping duplicate reaction: ${persona.name} already reacted to post ${postId}`);
      response.status(200).send("Reaction already exists, skipped");
      return;
    }

    const batch = db.batch();

    // 1. リアクション保存
    const reactionRef = db.collection("reactions").doc();
    batch.set(reactionRef, {
      postId: postId,
      userId: persona.id,
      userDisplayName: persona.name,
      reactionType: reactionType,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. 投稿のリアクションカウント更新
    const postRef = db.collection("posts").doc(postId);
    batch.update(postRef, {
      [`reactions.${reactionType}`]: admin.firestore.FieldValue.increment(1),
    });

    await batch.commit();

    console.log(`AI reaction posted: ${persona.name} -> ${reactionType}`);
    response.status(200).send("Reaction posted successfully");

  } catch (error) {
    console.error("Error in generateAIReaction:", error);
    response.status(500).send("Internal Server Error");
  }
});

/**
 * 管理用: 全ユーザーのフォローリストを掃除する
 * 存在しないユーザーIDをフォローリストから削除し、カウントを整合させます。
 */
export const cleanUpUserFollows = onCall(
  { region: "asia-northeast1", timeoutSeconds: 540 },
  async (request) => {
    // 認証チェック
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    // 管理者チェック
    const userIsAdmin = await isAdmin(request.auth.uid);
    if (!userIsAdmin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    try {
      const usersSnapshot = await db.collection("users").get();
      let updatedCount = 0;

      for (const userDoc of usersSnapshot.docs) {
        const userData = userDoc.data();
        const following = userData.following || [];

        if (following.length === 0) continue;

        // フォロー中のIDが本当に存在するかチェック
        const validFollowing: string[] = [];
        const invalidFollowing: string[] = [];

        for (const followedId of following) {
          // 簡易チェック: IDにスペースが含まれていたら不正なので削除
          if (followedId.trim() !== followedId) {
            invalidFollowing.push(followedId);
            continue;
          }

          // Firestore確認 (コストかかるが確実)
          const followedUserDoc = await db.collection("users").doc(followedId).get();
          if (followedUserDoc.exists) {
            validFollowing.push(followedId);
          } else {
            invalidFollowing.push(followedId);
          }
        }

        // 変更がある場合のみ更新
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
      return { success: true, updatedCount, message: `${updatedCount}件のユーザーを更新しました` };

    } catch (error) {
      console.error("Error cleaning up follows:", error);
      throw new HttpsError("internal", "処理中にエラーが発生しました");
    }
  }
);

/**
 * 管理用: 全てのAIユーザーを削除する (v1)
 * AIユーザーとその投稿、コメント、リアクションを全て削除します。
 */
export const deleteAllAIUsers = functionsV1.region("asia-northeast1").runWith({
  timeoutSeconds: 540, // 処理が重くなる可能性があるので長めに
  memory: "1GB"
}).https.onCall(async (data, context) => {
  // セキュリティ: ログイン必須
  if (!context.auth) {
    throw new functionsV1.https.HttpsError("unauthenticated", "ログインが必要です");
  }

  // セキュリティ: 管理者権限チェック
  const userIsAdmin = await isAdmin(context.auth.uid);
  if (!userIsAdmin) {
    throw new functionsV1.https.HttpsError("permission-denied", "管理者権限が必要です");
  }

  try {
    console.log("Starting deletion of all AI users...");
    const batchSize = 400;
    let batch = db.batch();
    let operationCount = 0;

    // 1. AIユーザーを取得
    const aiUsersSnapshot = await db.collection("users").where("isAI", "==", true).get();
    console.log(`Found ${aiUsersSnapshot.size} AI users to delete.`);

    if (aiUsersSnapshot.empty) {
      return { success: true, message: "AIユーザーはいませんでした" };
    }

    const aiUserIds = aiUsersSnapshot.docs.map(doc => doc.id);

    // バッチコミット用ヘルパー
    const commitBatchIfNeeded = async () => {
      if (operationCount >= batchSize) {
        await batch.commit();
        batch = db.batch();
        operationCount = 0;
      }
    };

    // 2. 関連データの削除 (Posts, Comments, Reactions)
    // Helper to process deletion in chunks
    const deleteCollectionByUserId = async (collectionName: string) => {
      // 10人ずつ処理
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

    // 3. ユーザー自身の削除（サブコレクション 'notifications' も含めて）
    console.log("Deleting AI user profiles and subcollections...");
    for (const doc of aiUsersSnapshot.docs) {
      // notificationsサブコレクションを削除
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

    // 残りのバッチを実行
    if (operationCount > 0) {
      await batch.commit();
    }

    console.log("Successfully deleted all AI data.");
    return { success: true, message: `AIユーザー${aiUsersSnapshot.size}人とそのデータを削除しました` };

  } catch (error) {
    console.error("Error deleting AI users:", error);
    throw new functionsV1.https.HttpsError("internal", "削除処理中にエラーが発生しました");
  }
});

/**
 * 孤児サークルAI（サブコレクションのみ残っている状態）を一括削除
 */
export const cleanupOrphanedCircleAIs = onCall(
  { region: "asia-northeast1", timeoutSeconds: 300 },
  async (request) => {
    // セキュリティ: 管理者権限チェック
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const userIsAdmin = await isAdmin(request.auth.uid);
    if (!userIsAdmin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    console.log("=== cleanupOrphanedCircleAIs START ===");

    // circle_ai_で始まるユーザーを全て取得
    const circleAIsSnapshot = await db.collection("users")
      .where("__name__", ">=", "circle_ai_")
      .where("__name__", "<", "circle_ai_\uf8ff")
      .get();

    let deletedCount = 0;
    let notificationCount = 0;

    for (const doc of circleAIsSnapshot.docs) {
      const userId = doc.id;
      const userRef = db.collection("users").doc(userId);

      // サブコレクション（notifications）を削除
      const notificationsSnapshot = await userRef.collection("notifications").get();
      if (!notificationsSnapshot.empty) {
        const batch = db.batch();
        notificationsSnapshot.docs.forEach(notifDoc => batch.delete(notifDoc.ref));
        await batch.commit();
        notificationCount += notificationsSnapshot.size;
      }

      // ユーザードキュメント本体を削除
      await userRef.delete();
      deletedCount++;
      console.log(`Deleted circle AI: ${userId}`);
    }

    console.log(`=== cleanupOrphanedCircleAIs COMPLETE: ${deletedCount} users, ${notificationCount} notifications ===`);
    return {
      success: true,
      message: `孤児サークルAIを${deletedCount}件削除しました（通知${notificationCount}件）`,
      deletedUsers: deletedCount,
      deletedNotifications: notificationCount,
    };
  }
);


/**
 * Cloud Tasks から呼び出される AI 投稿生成関数 (Worker)
 */
export const executeAIPostGeneration = functionsV1.region("asia-northeast1").runWith({
  secrets: ["GEMINI_API_KEY"],
  timeoutSeconds: 300,
  memory: "1GB",
}).https.onRequest(async (request, response) => {
  // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
  const { verifyCloudTasksRequest } = await import("./helpers/cloud-tasks-auth");
  if (!await verifyCloudTasksRequest(request, "executeAIPostGeneration")) {
    response.status(403).send("Unauthorized");
    return;
  }

  try {
    const { postId, personaId, postTimeIso } = request.body;
    console.log(`Executing AI post generation for ${personaId}`);

    const apiKey = geminiApiKey.value();
    if (!apiKey) throw new Error("GEMINI_API_KEY is not set");

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

    // ペルソナ取得
    const persona = AI_PERSONAS.find((p) => p.id === personaId);
    if (!persona) {
      console.error(`Persona not found: ${personaId}`);
      response.status(400).send("Persona not found");
      return;
    }

    // 職業に応じたテンプレートを取得（フォールバック用）
    const templates = POST_TEMPLATES_BY_OCCUPATION[persona.occupation.id] || [];

    // 現在時刻
    const now = new Date();
    const hours = now.getHours();

    // プロンプト生成 (努力・達成・日常の頑張りをテーマに)
    const prompt = `
${getSystemPrompt(persona, "みんな")}

【指示】
あなたは「ホームップ」というSNSのユーザー「${persona.name}」です。
職業は「${persona.occupation.name}」、性格は「${persona.personality.name}」です。

今の時間帯（${hours}時頃）に合わせた、自然な「つぶやき」を投稿してください。
テーマは「今日頑張ったこと」「小さな達成」「日常の努力」「ふとした気づき」などです。
ポジティブで、他のユーザーが見て「頑張ってるな」と思えるような内容にしてください。

【条件】
- ネガティブな発言禁止
- 誹謗中傷禁止
- ハッシュタグ不要
- 絵文字を適度に使用して人間らしく
- 文章は短め〜中くらい（30文字〜80文字程度）

【例】
- 「今日は早起きして朝活できた！気持ちいい✨」
- 「仕事の資料、期限内に終わった〜！自分へのご褒美にコンビニスイーツ買う🍰」
- 「今日は疲れたけど、筋トレだけは欠かさずやった💪 えらい！」
`;

    const result = await model.generateContent(prompt);
    let content = result.response.text()?.trim();

    // 生成失敗時はテンプレートからランダム選択
    if (!content && templates.length > 0) {
      content = templates[Math.floor(Math.random() * templates.length)];
    }

    if (!content) {
      throw new Error("Failed to generate content");
    }

    // 投稿作成
    const postRef = db.collection("posts").doc(postId);
    const reactions = {
      love: Math.floor(Math.random() * 5),
      praise: Math.floor(Math.random() * 5),
      cheer: Math.floor(Math.random() * 5),
      empathy: Math.floor(Math.random() * 5),
    };

    // postTimeIsoがあればその時間、なければ現在時刻
    const createdAt = postTimeIso ? admin.firestore.Timestamp.fromDate(new Date(postTimeIso)) : admin.firestore.FieldValue.serverTimestamp();

    await postRef.set({
      userId: persona.id,
      userDisplayName: persona.name,
      userAvatarIndex: persona.avatarIndex,
      content: content,
      postMode: "mix", // 公開範囲
      circleId: null, // タイムラインのクエリ(where circleId isNull)にマッチさせるため明示的にnullを設定
      createdAt: createdAt,
      reactions: reactions,
      commentCount: 0,
      isVisible: true,
    });

    // ユーザーの統計更新
    const totalReactions = Object.values(reactions).reduce((a, b) => a + b, 0);
    await db.collection("users").doc(persona.id).update({
      totalPosts: admin.firestore.FieldValue.increment(1),
      totalPraises: admin.firestore.FieldValue.increment(totalReactions),
    });

    console.log(`Successfully created post for ${persona.name}: ${content}`);
    response.status(200).json({ success: true, postId: postRef.id });
  } catch (error) {
    console.error("Error in executeAIPostGeneration:", error);
    response.status(500).send("Internal Server Error");
  }
});

// ===============================================
// タスクリマインダー通知（イベント駆動方式）
// タスク作成/更新時にCloud Tasksにリマインダーを登録
// ===============================================

const TASK_REMINDER_QUEUE = "task-reminders";

/**
 * リマインダー時刻を計算
 */
function calculateReminderTime(
  scheduledAt: Date,
  reminder: { unit: string; value: number }
): Date {
  const ms = scheduledAt.getTime();
  if (reminder.unit === "minutes") {
    return new Date(ms - reminder.value * 60 * 1000);
  } else if (reminder.unit === "hours") {
    return new Date(ms - reminder.value * 60 * 60 * 1000);
  } else if (reminder.unit === "days") {
    return new Date(ms - reminder.value * 24 * 60 * 60 * 1000);
  }
  return new Date(ms);
}

/**
 * タスク作成/更新時にリマインダーをスケジュール
 */
export const scheduleTaskReminders = onDocumentUpdated(
  { document: "tasks/{taskId}", region: "asia-northeast1" },
  async (event) => {
    const taskId = event.params.taskId;
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();

    if (!afterData) return;

    // 完了したタスクは無視
    if (afterData.isCompleted) {
      console.log(`[Reminder] Task ${taskId} is completed, skipping`);
      return;
    }

    const scheduledAt = (afterData.scheduledAt as admin.firestore.Timestamp)?.toDate();
    if (!scheduledAt) {
      console.log(`[Reminder] Task ${taskId} has no scheduledAt`);
      return;
    }

    // スケジュールが変更されたか確認
    const beforeScheduledAt = (beforeData?.scheduledAt as admin.firestore.Timestamp)?.toDate();
    const beforeReminders = JSON.stringify(beforeData?.reminders || []);
    const afterReminders = JSON.stringify(afterData.reminders || []);

    if (
      beforeScheduledAt?.getTime() === scheduledAt.getTime() &&
      beforeReminders === afterReminders
    ) {
      console.log(`[Reminder] Task ${taskId} schedule unchanged`);
      return;
    }

    const userId = afterData.userId as string;
    const taskContent = (afterData.content as string) || "タスク";
    const reminders = afterData.reminders as Array<{ unit: string; value: number }> | undefined;

    console.log(`[Reminder] Scheduling reminders for task ${taskId}`);

    const tasksClient = new CloudTasksClient();
    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    const location = LOCATION;

    // 既存のリマインダータスクをキャンセル（sentRemindersを削除）
    const existingReminders = await db.collection("scheduledReminders")
      .where("taskId", "==", taskId)
      .get();

    const batch = db.batch();
    for (const doc of existingReminders.docs) {
      // Cloud Tasksのタスクをキャンセル
      const taskName = doc.data().cloudTaskName;
      if (taskName) {
        try {
          await tasksClient.deleteTask({ name: taskName });
          console.log(`[Reminder] Cancelled task: ${taskName}`);
        } catch (e) {
          // タスクが存在しない場合は無視
          console.log(`[Reminder] Task already gone: ${taskName}`);
        }
      }
      batch.delete(doc.ref);
    }
    await batch.commit();

    // 新しいリマインダーをスケジュール
    const queuePath = tasksClient.queuePath(project, location, TASK_REMINDER_QUEUE);
    const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeTaskReminder`;
    const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

    const now = new Date();

    // 1. 事前リマインダー
    if (reminders && reminders.length > 0) {
      for (const reminder of reminders) {
        const reminderTime = calculateReminderTime(scheduledAt, reminder);

        // 過去の時刻はスキップ
        if (reminderTime <= now) {
          console.log(`[Reminder] Skipping past reminder: ${reminderTime.toISOString()}`);
          continue;
        }

        const reminderKey = `${reminder.unit}_${reminder.value}`;
        const timeLabel = reminder.unit === "minutes"
          ? `${reminder.value}分前`
          : reminder.unit === "hours"
            ? `${reminder.value}時間前`
            : `${reminder.value}日前`;

        const payload = {
          taskId,
          userId,
          taskContent,
          timeLabel,
          reminderKey,
          type: "pre_reminder",
        };

        try {
          const [task] = await tasksClient.createTask({
            parent: queuePath,
            task: {
              httpRequest: {
                httpMethod: "POST",
                url: targetUrl,
                body: Buffer.from(JSON.stringify(payload)).toString("base64"),
                headers: { "Content-Type": "application/json" },
                oidcToken: { serviceAccountEmail },
              },
              scheduleTime: { seconds: Math.floor(reminderTime.getTime() / 1000) },
            },
          });

          // スケジュール済みとして記録
          await db.collection("scheduledReminders").add({
            taskId,
            reminderKey,
            cloudTaskName: task.name,
            scheduledFor: admin.firestore.Timestamp.fromDate(reminderTime),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          console.log(`[Reminder] Scheduled: ${taskId} - ${reminderKey} at ${reminderTime.toISOString()}`);
        } catch (error) {
          console.error(`[Reminder] Failed to schedule: ${reminderKey}`, error);
        }
      }
    }

    // 2. 予定時刻ちょうどの通知
    if (scheduledAt > now) {
      const payload = {
        taskId,
        userId,
        taskContent,
        timeLabel: "予定時刻",
        reminderKey: "on_time",
        type: "on_time",
      };

      try {
        const [task] = await tasksClient.createTask({
          parent: queuePath,
          task: {
            httpRequest: {
              httpMethod: "POST",
              url: targetUrl,
              body: Buffer.from(JSON.stringify(payload)).toString("base64"),
              headers: { "Content-Type": "application/json" },
              oidcToken: { serviceAccountEmail },
            },
            scheduleTime: { seconds: Math.floor(scheduledAt.getTime() / 1000) },
          },
        });

        await db.collection("scheduledReminders").add({
          taskId,
          reminderKey: "on_time",
          cloudTaskName: task.name,
          scheduledFor: admin.firestore.Timestamp.fromDate(scheduledAt),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`[Reminder] Scheduled on-time: ${taskId} at ${scheduledAt.toISOString()}`);
      } catch (error) {
        console.error(`[Reminder] Failed to schedule on-time`, error);
      }
    }
  }
);

/**
 * タスク作成時にリマインダーをスケジュール
 */
export const scheduleTaskRemindersOnCreate = onDocumentCreated(
  { document: "tasks/{taskId}", region: "asia-northeast1" },
  async (event) => {
    const taskId = event.params.taskId;
    const data = event.data?.data();

    if (!data) return;

    // 完了したタスクは無視
    if (data.isCompleted) return;

    const scheduledAt = (data.scheduledAt as admin.firestore.Timestamp)?.toDate();
    if (!scheduledAt) return;

    const userId = data.userId as string;
    const taskContent = (data.content as string) || "タスク";
    const reminders = data.reminders as Array<{ unit: string; value: number }> | undefined;

    console.log(`[Reminder] Scheduling reminders for new task ${taskId}`);

    const tasksClient = new CloudTasksClient();
    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    const location = LOCATION;

    const queuePath = tasksClient.queuePath(project, location, TASK_REMINDER_QUEUE);
    const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeTaskReminder`;
    const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

    const now = new Date();

    // 1. 事前リマインダー
    if (reminders && reminders.length > 0) {
      for (const reminder of reminders) {
        const reminderTime = calculateReminderTime(scheduledAt, reminder);

        if (reminderTime <= now) continue;

        const reminderKey = `${reminder.unit}_${reminder.value}`;
        const timeLabel = reminder.unit === "minutes"
          ? `${reminder.value}分前`
          : reminder.unit === "hours"
            ? `${reminder.value}時間前`
            : `${reminder.value}日前`;

        const payload = {
          taskId,
          userId,
          taskContent,
          timeLabel,
          reminderKey,
          type: "pre_reminder",
        };

        try {
          const [task] = await tasksClient.createTask({
            parent: queuePath,
            task: {
              httpRequest: {
                httpMethod: "POST",
                url: targetUrl,
                body: Buffer.from(JSON.stringify(payload)).toString("base64"),
                headers: { "Content-Type": "application/json" },
                oidcToken: { serviceAccountEmail },
              },
              scheduleTime: { seconds: Math.floor(reminderTime.getTime() / 1000) },
            },
          });

          await db.collection("scheduledReminders").add({
            taskId,
            reminderKey,
            cloudTaskName: task.name,
            scheduledFor: admin.firestore.Timestamp.fromDate(reminderTime),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          console.log(`[Reminder] Scheduled: ${taskId} - ${reminderKey}`);
        } catch (error) {
          console.error(`[Reminder] Failed to schedule: ${reminderKey}`, error);
        }
      }
    }

    // 2. 予定時刻ちょうどの通知
    if (scheduledAt > now) {
      const payload = {
        taskId,
        userId,
        taskContent,
        timeLabel: "予定時刻",
        reminderKey: "on_time",
        type: "on_time",
      };

      try {
        const [task] = await tasksClient.createTask({
          parent: queuePath,
          task: {
            httpRequest: {
              httpMethod: "POST",
              url: targetUrl,
              body: Buffer.from(JSON.stringify(payload)).toString("base64"),
              headers: { "Content-Type": "application/json" },
              oidcToken: { serviceAccountEmail },
            },
            scheduleTime: { seconds: Math.floor(scheduledAt.getTime() / 1000) },
          },
        });

        await db.collection("scheduledReminders").add({
          taskId,
          reminderKey: "on_time",
          cloudTaskName: task.name,
          scheduledFor: admin.firestore.Timestamp.fromDate(scheduledAt),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`[Reminder] Scheduled on-time: ${taskId}`);
      } catch (error) {
        console.error(`[Reminder] Failed to schedule on-time`, error);
      }
    }
  }
);

/**
 * リマインダー通知を実行するCloud Tasks用のHTTPエンドポイント
 */
export const executeTaskReminder = functionsV1.region("asia-northeast1").runWith({
  timeoutSeconds: 30,
}).https.onRequest(async (request, response) => {
  // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
  const { verifyCloudTasksRequest } = await import("./helpers/cloud-tasks-auth");
  if (!await verifyCloudTasksRequest(request, "executeTaskReminder")) {
    response.status(403).send("Unauthorized");
    return;
  }

  try {
    const { taskId, userId, taskContent, timeLabel, reminderKey, type } = request.body;

    console.log(`[Reminder] Executing reminder: ${taskId} - ${reminderKey}`);

    // タスクがまだ存在し、未完了か確認
    const taskDoc = await db.collection("tasks").doc(taskId).get();
    if (!taskDoc.exists) {
      console.log(`[Reminder] Task ${taskId} not found, skipping`);
      response.status(200).send("Task not found");
      return;
    }

    const taskData = taskDoc.data();
    if (taskData?.isCompleted) {
      console.log(`[Reminder] Task ${taskId} is completed, skipping`);
      response.status(200).send("Task completed");
      return;
    }

    // 送信済みかチェック
    const sentRef = db.collection("sentReminders").doc(`${taskId}_${reminderKey}`);
    const sentDoc = await sentRef.get();
    if (sentDoc.exists) {
      console.log(`[Reminder] Already sent: ${taskId} - ${reminderKey}`);
      response.status(200).send("Already sent");
      return;
    }

    // ユーザーのFCMトークンを取得
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      console.log(`[Reminder] User ${userId} not found`);
      response.status(200).send("User not found");
      return;
    }

    const fcmToken = userDoc.data()?.fcmToken;
    if (!fcmToken) {
      console.log(`[Reminder] No FCM token for user: ${userId}`);
      response.status(200).send("No FCM token");
      return;
    }

    // 通知を保存 (onNotificationCreatedにより自動でプッシュ通知も送信される)
    const title = type === "on_time" ? "📋 タスクの時間です" : "🔔 タスクリマインダー";
    const body = type === "on_time"
      ? `「${taskContent}」の予定時刻になりました`
      : `「${taskContent}」の${timeLabel}です`;

    await db.collection("users").doc(userId).collection("notifications").add({
      type: "task_reminder",
      title,
      body,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      taskId,
      reminderKey,
      clientType: type,
    });

    console.log(`[Reminder] Notification saved for ${taskId} - ${reminderKey}`);

    // 送信済みとして記録
    await sentRef.set({
      taskId,
      userId,
      reminderKey,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`[Reminder] Sent: ${taskId} - ${reminderKey}`);
    response.status(200).send("Notification sent");
  } catch (error) {
    console.error("[Reminder] Error:", error);
    response.status(500).send("Error");
  }
});


// ===============================================
// リアクション追加時のtotalPraises更新
// ===============================================

/**
 * リアクション追加時に投稿者のtotalPraisesをインクリメント
 */
export const onReactionCreated = onDocumentCreated(
  "reactions/{reactionId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No reaction data");
      return;
    }

    const reactionData = snapshot.data();
    const postId = reactionData.postId;
    const reactorId = reactionData.userId;

    console.log(`=== onReactionCreated: postId=${postId}, reactor=${reactorId} ===`);

    try {
      // 投稿を取得して投稿者IDを取得
      const postDoc = await db.collection("posts").doc(postId).get();
      if (!postDoc.exists) {
        console.log("Post not found:", postId);
        return;
      }

      const postData = postDoc.data()!;
      const postOwnerId = postData.userId;

      // 自分へのリアクションはカウントしない
      if (postOwnerId === reactorId) {
        console.log("Self-reaction, skipping totalPraises update");
        return;
      }

      // 投稿者のtotalPraisesをインクリメント
      await db.collection("users").doc(postOwnerId).update({
        totalPraises: admin.firestore.FieldValue.increment(1),
      });

      console.log(`Incremented totalPraises for user: ${postOwnerId}`);

    } catch (error) {
      console.error("onReactionCreated ERROR:", error);
    }
  }
);

// ===============================================
// 画像モデレーションCallable関数
// ===============================================

/**
 * アップロード前の画像をモデレーション
 * Base64エンコードされた画像データを受け取り、不適切かどうか判定
 */
export const moderateImageCallable = onCall(
  { secrets: [geminiApiKey], region: "asia-northeast1" },
  async (request) => {
    const { imageBase64, mimeType = "image/jpeg" } = request.data;

    if (!imageBase64) {
      throw new HttpsError("invalid-argument", "imageBase64 is required");
    }

    // 認証チェック
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    try {
      const apiKey = geminiApiKey.value();
      const genAI = new GoogleGenerativeAI(apiKey);
      const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash-exp" });

      const prompt = `
この画像がSNSへの投稿として適切かどうか判定してください。

【ブロック対象（isInappropriate: true）】
- adult: 成人向けコンテンツ、露出の多い画像、性的な内容
- violence: 暴力的な画像、血液、怪我、残虐な内容
- hate: ヘイトシンボル、差別的な画像
- dangerous: 危険な行為、違法行為、武器

【許可する内容（isInappropriate: false）】
- 通常の人物写真（水着でも一般的なものはOK）
- 風景、食べ物、ペット
- 趣味の写真
- 芸術作品（明らかにアダルトでない限り）

【回答形式】
必ず以下のJSON形式のみで回答してください：
{
  "isInappropriate": true または false,
  "category": "adult" | "violence" | "hate" | "dangerous" | "none",
  "confidence": 0から1の数値,
  "reason": "判定理由"
}
`;

      const imagePart: Part = {
        inlineData: {
          mimeType: mimeType,
          data: imageBase64,
        },
      };

      const result = await model.generateContent([prompt, imagePart]);
      const responseText = result.response.text().trim();

      let jsonText = responseText;
      // JSONブロックを抽出
      const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
      if (jsonMatch) {
        jsonText = jsonMatch[1];
      }

      const moderationResult = JSON.parse(jsonText) as MediaModerationResult;

      console.log(`Image moderation result: ${JSON.stringify(moderationResult)}`);

      return moderationResult;

    } catch (error) {
      console.error("moderateImageCallable ERROR:", error);
      // エラー時は許可（サービス継続性を優先）
      return {
        isInappropriate: false,
        category: "none",
        confidence: 0,
        reason: "モデレーションエラー",
      };
    }
  }
);

/**
 * 孤立メディアクリーンアップ
 * Cloud Schedulerで毎日実行
 * 24時間以上経過した孤立メディアを削除
 */
export const cleanupOrphanedMedia = onSchedule(
  {
    schedule: "0 3 * * *", // 毎日午前3時 JST
    timeZone: "Asia/Tokyo",
    region: "asia-northeast1",
    timeoutSeconds: 600, // 10分タイムアウト
  },
  async () => {
    console.log("=== cleanupOrphanedMedia START ===");
    const bucket = admin.storage().bucket();
    const now = Date.now();
    const TWENTY_FOUR_HOURS = 24 * 60 * 60 * 1000;

    let deletedCount = 0;
    let checkedCount = 0;

    // ===============================================
    // 1. 投稿メディアのクリーンアップ
    // ===============================================
    console.log("Checking posts media...");
    const [postFiles] = await bucket.getFiles({ prefix: "posts/" });

    for (const file of postFiles) {
      checkedCount++;
      try {
        const [metadata] = await file.getMetadata();
        const customMetadata = metadata.metadata || {};
        const uploadedAtStr = customMetadata.uploadedAt;
        const uploadedAt = uploadedAtStr ? parseInt(String(uploadedAtStr)) : 0;
        const postId = customMetadata.postId ? String(customMetadata.postId) : null;

        // 24時間以上経過していないならスキップ
        if (now - uploadedAt < TWENTY_FOUR_HOURS) continue;

        // postId未設定（古いファイル）はスキップ
        if (!postId) continue;

        let shouldDelete = false;

        if (postId === "PENDING") {
          // 投稿前に離脱したケース
          shouldDelete = true;
          console.log(`Orphan (PENDING): ${file.name}`);
        } else {
          // 投稿が存在するか確認
          const postDoc = await db.collection("posts").doc(postId).get();
          if (!postDoc.exists) {
            shouldDelete = true;
            console.log(`Orphan (post deleted): ${file.name}`);
          }
        }

        if (shouldDelete) {
          await file.delete();
          deletedCount++;
        }
      } catch (error) {
        console.error(`Error checking ${file.name}:`, error);
      }
    }

    // ===============================================
    // 2. サークル画像のクリーンアップ
    // ===============================================
    console.log("Checking circles media...");
    const [circleFiles] = await bucket.getFiles({ prefix: "circles/" });

    for (const file of circleFiles) {
      checkedCount++;
      try {
        const [metadata] = await file.getMetadata();
        const timeCreated = metadata.timeCreated;
        const createdAt = timeCreated ? new Date(timeCreated).getTime() : 0;

        // 24時間以上経過していないならスキップ
        if (now - createdAt < TWENTY_FOUR_HOURS) continue;

        // パスからcircleIdを抽出: circles/{circleId}/icon/{fileName}
        const pathParts = file.name.split("/");
        if (pathParts.length >= 2) {
          const circleId = pathParts[1];
          const circleDoc = await db.collection("circles").doc(circleId).get();

          if (!circleDoc.exists) {
            console.log(`Orphan (circle deleted): ${file.name}`);
            await file.delete();
            deletedCount++;
          }
        }
      } catch (error) {
        console.error(`Error checking ${file.name}:`, error);
      }
    }

    // ===============================================
    // 3. タスク添付のクリーンアップ
    // ===============================================
    console.log("Checking task attachments...");
    const [taskFiles] = await bucket.getFiles({ prefix: "task_attachments/" });

    for (const file of taskFiles) {
      checkedCount++;
      try {
        const [metadata] = await file.getMetadata();
        const taskTimeCreated = metadata.timeCreated;
        const taskCreatedAt = taskTimeCreated ? new Date(taskTimeCreated).getTime() : 0;

        // 24時間以上経過していないならスキップ
        if (now - taskCreatedAt < TWENTY_FOUR_HOURS) continue;

        // パスからtaskIdを抽出: task_attachments/{userId}/{taskId}/{fileName}
        const pathParts = file.name.split("/");
        if (pathParts.length >= 3) {
          const taskId = pathParts[2];
          const taskDoc = await db.collection("tasks").doc(taskId).get();

          if (!taskDoc.exists) {
            console.log(`Orphan (task deleted): ${file.name}`);
            await file.delete();
            deletedCount++;
          }
        }
      } catch (error) {
        console.error(`Error checking ${file.name}:`, error);
      }
    }

    // ===============================================
    // 4. 孤立サークル投稿のクリーンアップ（Firestore）
    // サークルが存在しない投稿を削除
    // ===============================================
    console.log("Checking orphaned circle posts...");
    let orphanedPostsDeleted = 0;

    // circleIdがnullでない投稿を取得（サークル投稿のみ）
    const circlePostsSnapshot = await db.collection("posts")
      .where("circleId", "!=", null)
      .limit(500) // バッチサイズ制限
      .get();

    // サークルの存在を確認するためのキャッシュ
    const circleExistsCache: Map<string, boolean> = new Map();

    for (const postDoc of circlePostsSnapshot.docs) {
      try {
        const postData = postDoc.data();
        const circleId = postData.circleId;

        if (!circleId) continue;

        // キャッシュを確認
        let circleExists = circleExistsCache.get(circleId);
        if (circleExists === undefined) {
          const circleDoc = await db.collection("circles").doc(circleId).get();
          circleExists = circleDoc.exists;
          circleExistsCache.set(circleId, circleExists);
        }

        if (!circleExists) {
          console.log(`Orphaned circle post found: ${postDoc.id} (circleId: ${circleId})`);

          // 関連データを削除
          const deleteRefs: FirebaseFirestore.DocumentReference[] = [];

          // コメント削除
          const comments = await db.collection("comments").where("postId", "==", postDoc.id).get();
          comments.docs.forEach((c) => deleteRefs.push(c.ref));

          // リアクション削除
          const reactions = await db.collection("reactions").where("postId", "==", postDoc.id).get();
          reactions.docs.forEach((r) => deleteRefs.push(r.ref));

          // 投稿自体を削除
          deleteRefs.push(postDoc.ref);

          // バッチ削除
          const batch = db.batch();
          deleteRefs.forEach((ref) => batch.delete(ref));
          await batch.commit();

          // メディアも削除
          const mediaItems = postData.mediaItems || [];
          for (const media of mediaItems) {
            if (media.url && media.url.includes("firebasestorage.googleapis.com")) {
              try {
                const urlParts = media.url.split("/o/")[1];
                if (urlParts) {
                  const filePath = decodeURIComponent(urlParts.split("?")[0]);
                  await bucket.file(filePath).delete().catch(() => { });
                }
              } catch (e) {
                console.error(`Media delete failed:`, e);
              }
            }
          }

          orphanedPostsDeleted++;
        }
      } catch (error) {
        console.error(`Error checking post ${postDoc.id}:`, error);
      }
    }

    // ===============================================
    // 5. 孤立コメントのクリーンアップ（Firestore）
    // 存在しない投稿に紐づくコメントを削除
    // ===============================================
    console.log("Checking orphaned comments...");
    let orphanedCommentsDeleted = 0;

    const commentsSnapshot = await db.collection("comments")
      .limit(1000)
      .get();

    // 投稿の存在を確認するためのキャッシュ
    const postExistsCache: Map<string, boolean> = new Map();

    for (const commentDoc of commentsSnapshot.docs) {
      try {
        const commentData = commentDoc.data();
        const postId = commentData.postId;

        if (!postId) continue;

        let postExists = postExistsCache.get(postId);
        if (postExists === undefined) {
          const postDoc = await db.collection("posts").doc(postId).get();
          postExists = postDoc.exists;
          postExistsCache.set(postId, postExists);
        }

        if (!postExists) {
          console.log(`Orphaned comment found: ${commentDoc.id} (postId: ${postId})`);
          await commentDoc.ref.delete();
          orphanedCommentsDeleted++;
        }
      } catch (error) {
        console.error(`Error checking comment ${commentDoc.id}:`, error);
      }
    }

    // ===============================================
    // 6. 孤立リアクションのクリーンアップ（Firestore）
    // 存在しない投稿に紐づくリアクションを削除
    // ===============================================
    console.log("Checking orphaned reactions...");
    let orphanedReactionsDeleted = 0;

    const reactionsSnapshot = await db.collection("reactions")
      .limit(1000)
      .get();

    for (const reactionDoc of reactionsSnapshot.docs) {
      try {
        const reactionData = reactionDoc.data();
        const postId = reactionData.postId;

        if (!postId) continue;

        let postExists = postExistsCache.get(postId);
        if (postExists === undefined) {
          const postDoc = await db.collection("posts").doc(postId).get();
          postExists = postDoc.exists;
          postExistsCache.set(postId, postExists);
        }

        if (!postExists) {
          console.log(`Orphaned reaction found: ${reactionDoc.id} (postId: ${postId})`);
          await reactionDoc.ref.delete();
          orphanedReactionsDeleted++;
        }
      } catch (error) {
        console.error(`Error checking reaction ${reactionDoc.id}:`, error);
      }
    }

    // サークルAI投稿履歴のクリーンアップ（2日以上前の履歴を削除）
    const twoDaysAgo = new Date();
    twoDaysAgo.setDate(twoDaysAgo.getDate() - 2);
    const twoDaysAgoStr = twoDaysAgo.toISOString().split("T")[0];

    const oldHistorySnapshot = await db.collection("circleAIPostHistory")
      .where("date", "<", twoDaysAgoStr)
      .get();

    let historyDeleted = 0;
    for (const doc of oldHistorySnapshot.docs) {
      await doc.ref.delete();
      historyDeleted++;
    }
    if (historyDeleted > 0) {
      console.log(`Deleted ${historyDeleted} old circleAIPostHistory documents`);
    }

    // AI投稿履歴のクリーンアップ（2日以上前の履歴を削除）
    const oldAIHistorySnapshot = await db.collection("aiPostHistory")
      .where("date", "<", twoDaysAgoStr)
      .get();

    let aiHistoryDeleted = 0;
    for (const doc of oldAIHistorySnapshot.docs) {
      await doc.ref.delete();
      aiHistoryDeleted++;
    }
    if (aiHistoryDeleted > 0) {
      console.log(`Deleted ${aiHistoryDeleted} old aiPostHistory documents`);
    }

    console.log(`=== cleanupOrphanedMedia COMPLETE: checked=${checkedCount}, deleted=${deletedCount}, orphanedPosts=${orphanedPostsDeleted}, orphanedComments=${orphanedCommentsDeleted}, orphanedReactions=${orphanedReactionsDeleted} ===`);
  }
);

// ============================================================
// 目標リマインダー通知機能
// ============================================================

/**
 * 目標リマインダー用時刻計算（期限から逆算）
 */
function calculateGoalReminderTime(deadline: Date, reminder: { unit: string; value: number }): Date {
  const ms = deadline.getTime();
  if (reminder.unit === "minutes") {
    return new Date(ms - reminder.value * 60 * 1000);
  } else if (reminder.unit === "hours") {
    return new Date(ms - reminder.value * 60 * 60 * 1000);
  } else if (reminder.unit === "days") {
    return new Date(ms - reminder.value * 24 * 60 * 60 * 1000);
  }
  return new Date(ms);
}

/**
 * 目標リマインダー実行エンドポイント
 */
export const executeGoalReminder = onRequest(
  { region: "asia-northeast1" },
  async (req, res) => {
    // 認証チェック（Cloud Tasksからのみ呼び出し可能）
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).send("Unauthorized");
      return;
    }

    try {
      const { goalId, userId, goalTitle, timeLabel, reminderKey, type } = req.body;

      if (!goalId || !userId) {
        res.status(400).send("Missing required fields");
        return;
      }

      // 重複チェック
      const sentKey = `goal_${goalId}_${type}_${reminderKey}`;
      const sentDoc = await db.collection("sentReminders").doc(sentKey).get();
      if (sentDoc.exists) {
        console.log(`[GoalReminder] Already sent: ${sentKey}`);
        res.status(200).send("Already sent");
        return;
      }

      // 目標がまだ存在し、未完了か確認
      const goalDoc = await db.collection("goals").doc(goalId).get();
      if (!goalDoc.exists) {
        console.log(`[GoalReminder] Goal ${goalId} no longer exists`);
        res.status(200).send("Goal deleted");
        return;
      }

      const goalData = goalDoc.data();
      if (goalData?.completedAt) {
        console.log(`[GoalReminder] Goal ${goalId} is already completed`);
        res.status(200).send("Goal completed");
        return;
      }

      // ユーザーのFCMトークン取得
      const userDoc = await db.collection("users").doc(userId).get();
      if (!userDoc.exists) {
        console.log(`[GoalReminder] User ${userId} not found`);
        res.status(200).send("User not found");
        return;
      }

      const fcmToken = userDoc.data()?.fcmToken;
      if (!fcmToken) {
        console.log(`[GoalReminder] User ${userId} has no FCM token`);
        res.status(200).send("No FCM token");
        return;
      }

      // 通知タイトル・本文
      const isDeadline = type === "goal_deadline";
      const title = isDeadline ? "🚩 目標の期限です！" : "🚩 目標リマインダー";
      const body = isDeadline
        ? `「${goalTitle}」の期限になりました。達成状況を確認しましょう！`
        : `「${goalTitle}」の期限まで${timeLabel}です`;

      // FCM送信
      await admin.messaging().send({
        token: fcmToken,
        notification: { title, body },
        data: {
          type: "goal_reminder",
          goalId,
        },
        android: {
          priority: "high",
          notification: {
            channelId: "reminders",
            priority: "high",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      });

      // 送信済みとして記録
      await db.collection("sentReminders").doc(sentKey).set({
        goalId,
        userId,
        type,
        reminderKey,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`[GoalReminder] Sent: ${goalId} - ${timeLabel}`);
      res.status(200).send("OK");
    } catch (error) {
      console.error("[GoalReminder] Error:", error);
      res.status(500).send("Error");
    }
  }
);

/**
 * 目標作成時にリマインダーをスケジュール
 */
export const scheduleGoalRemindersOnCreate = onDocumentCreated(
  { document: "goals/{goalId}", region: "asia-northeast1" },
  async (event) => {
    const goalId = event.params.goalId;
    const data = event.data?.data();

    if (!data) return;

    // 完了済みは無視
    if (data.completedAt) return;

    const deadline = (data.deadline as admin.firestore.Timestamp)?.toDate();
    if (!deadline) {
      console.log(`[GoalReminder] Goal ${goalId} has no deadline`);
      return;
    }

    const userId = data.userId as string;
    const goalTitle = (data.title as string) || "目標";
    const reminders = data.reminders as Array<{ unit: string; value: number }> | undefined;

    if (!reminders || reminders.length === 0) {
      console.log(`[GoalReminder] Goal ${goalId} has no reminders`);
      return;
    }

    console.log(`[GoalReminder] Scheduling reminders for new goal ${goalId}`);

    const tasksClient = new CloudTasksClient();
    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    const location = LOCATION;

    const queuePath = tasksClient.queuePath(project, location, TASK_REMINDER_QUEUE);
    const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeGoalReminder`;
    const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

    const now = new Date();

    for (const reminder of reminders) {
      const reminderTime = calculateGoalReminderTime(deadline, reminder);

      if (reminderTime <= now) {
        console.log(`[GoalReminder] Skipping past reminder: ${reminderTime.toISOString()}`);
        continue;
      }

      const reminderKey = `${reminder.unit}_${reminder.value}`;
      const timeLabel = reminder.unit === "minutes"
        ? `${reminder.value}分`
        : reminder.unit === "hours"
          ? `${reminder.value}時間`
          : `${reminder.value}日`;

      const payload = {
        goalId,
        userId,
        goalTitle,
        timeLabel,
        reminderKey,
        type: "goal_reminder",
      };

      const task = {
        httpRequest: {
          httpMethod: "POST" as const,
          url: targetUrl,
          headers: { "Content-Type": "application/json" },
          body: Buffer.from(JSON.stringify(payload)).toString("base64"),
          oidcToken: {
            serviceAccountEmail,
            audience: targetUrl,
          },
        },
        scheduleTime: {
          seconds: Math.floor(reminderTime.getTime() / 1000),
        },
      };

      try {
        const [response] = await tasksClient.createTask({ parent: queuePath, task });
        console.log(`[GoalReminder] Created task: ${response.name}`);

        // scheduledRemindersに記録
        await db.collection("scheduledReminders").add({
          goalId,
          reminderKey,
          type: "goal_reminder",
          scheduledFor: reminderTime,
          cloudTaskName: response.name,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (e) {
        console.error(`[GoalReminder] Failed to create task:`, e);
      }
    }

    // 2. 期限時刻通知（期限ちょうど）
    if (deadline > now) {
      const deadlinePayload = {
        goalId,
        userId,
        goalTitle,
        timeLabel: "期限",
        reminderKey: "deadline",
        type: "goal_deadline",
      };

      const deadlineTask = {
        httpRequest: {
          httpMethod: "POST" as const,
          url: targetUrl,
          headers: { "Content-Type": "application/json" },
          body: Buffer.from(JSON.stringify(deadlinePayload)).toString("base64"),
          oidcToken: {
            serviceAccountEmail,
            audience: targetUrl,
          },
        },
        scheduleTime: {
          seconds: Math.floor(deadline.getTime() / 1000),
        },
      };

      try {
        const [response] = await tasksClient.createTask({ parent: queuePath, task: deadlineTask });
        console.log(`[GoalReminder] Created deadline task: ${response.name}`);

        await db.collection("scheduledReminders").add({
          goalId,
          reminderKey: "deadline",
          type: "goal_deadline",
          scheduledFor: deadline,
          cloudTaskName: response.name,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (e) {
        console.error(`[GoalReminder] Failed to create deadline task:`, e);
      }
    }
  }
);

/**
 * 目標更新時にリマインダーを再スケジュール
 */
export const scheduleGoalReminders = onDocumentUpdated(
  { document: "goals/{goalId}", region: "asia-northeast1" },
  async (event) => {
    const goalId = event.params.goalId;
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();

    if (!afterData) return;

    // 完了した目標は無視
    if (afterData.completedAt) {
      console.log(`[GoalReminder] Goal ${goalId} is completed, skipping`);
      return;
    }

    const deadline = (afterData.deadline as admin.firestore.Timestamp)?.toDate();
    if (!deadline) {
      console.log(`[GoalReminder] Goal ${goalId} has no deadline`);
      return;
    }

    // 期限またはリマインダーが変更されたか確認
    const beforeDeadline = (beforeData?.deadline as admin.firestore.Timestamp)?.toDate();
    const beforeReminders = JSON.stringify(beforeData?.reminders || []);
    const afterReminders = JSON.stringify(afterData.reminders || []);

    if (
      beforeDeadline?.getTime() === deadline.getTime() &&
      beforeReminders === afterReminders
    ) {
      console.log(`[GoalReminder] Goal ${goalId} schedule unchanged`);
      return;
    }

    const userId = afterData.userId as string;
    const goalTitle = (afterData.title as string) || "目標";
    const reminders = afterData.reminders as Array<{ unit: string; value: number }> | undefined;

    console.log(`[GoalReminder] Rescheduling reminders for goal ${goalId}`);

    const tasksClient = new CloudTasksClient();
    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    const location = LOCATION;

    // 既存のリマインダータスクをキャンセル
    const existingReminders = await db.collection("scheduledReminders")
      .where("goalId", "==", goalId)
      .get();

    const batch = db.batch();
    for (const doc of existingReminders.docs) {
      const taskName = doc.data().cloudTaskName;
      if (taskName) {
        try {
          await tasksClient.deleteTask({ name: taskName });
          console.log(`[GoalReminder] Cancelled task: ${taskName}`);
        } catch (e) {
          console.log(`[GoalReminder] Task already gone: ${taskName}`);
        }
      }
      batch.delete(doc.ref);
    }
    await batch.commit();

    if (!reminders || reminders.length === 0) {
      console.log(`[GoalReminder] Goal ${goalId} has no reminders after update`);
      return;
    }

    // 新しいリマインダーをスケジュール
    const queuePath = tasksClient.queuePath(project, location, TASK_REMINDER_QUEUE);
    const targetUrl = `https://${location}-${project}.cloudfunctions.net/executeGoalReminder`;
    const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

    const now = new Date();

    for (const reminder of reminders) {
      const reminderTime = calculateGoalReminderTime(deadline, reminder);

      if (reminderTime <= now) {
        console.log(`[GoalReminder] Skipping past reminder: ${reminderTime.toISOString()}`);
        continue;
      }

      const reminderKey = `${reminder.unit}_${reminder.value}`;
      const timeLabel = reminder.unit === "minutes"
        ? `${reminder.value}分`
        : reminder.unit === "hours"
          ? `${reminder.value}時間`
          : `${reminder.value}日`;

      const payload = {
        goalId,
        userId,
        goalTitle,
        timeLabel,
        reminderKey,
        type: "goal_reminder",
      };

      const task = {
        httpRequest: {
          httpMethod: "POST" as const,
          url: targetUrl,
          headers: { "Content-Type": "application/json" },
          body: Buffer.from(JSON.stringify(payload)).toString("base64"),
          oidcToken: {
            serviceAccountEmail,
            audience: targetUrl,
          },
        },
        scheduleTime: {
          seconds: Math.floor(reminderTime.getTime() / 1000),
        },
      };

      try {
        const [response] = await tasksClient.createTask({ parent: queuePath, task });
        console.log(`[GoalReminder] Created task: ${response.name}`);

        await db.collection("scheduledReminders").add({
          goalId,
          reminderKey,
          type: "goal_reminder",
          scheduledFor: reminderTime,
          cloudTaskName: response.name,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (e) {
        console.error(`[GoalReminder] Failed to create task:`, e);
      }
    }

    // 2. 期限時刻通知（期限ちょうど）
    if (deadline > now) {
      const deadlinePayload = {
        goalId,
        userId,
        goalTitle,
        timeLabel: "期限",
        reminderKey: "deadline",
        type: "goal_deadline",
      };

      const deadlineTask = {
        httpRequest: {
          httpMethod: "POST" as const,
          url: targetUrl,
          headers: { "Content-Type": "application/json" },
          body: Buffer.from(JSON.stringify(deadlinePayload)).toString("base64"),
          oidcToken: {
            serviceAccountEmail,
            audience: targetUrl,
          },
        },
        scheduleTime: {
          seconds: Math.floor(deadline.getTime() / 1000),
        },
      };

      try {
        const [response] = await tasksClient.createTask({ parent: queuePath, task: deadlineTask });
        console.log(`[GoalReminder] Created deadline task: ${response.name}`);

        await db.collection("scheduledReminders").add({
          goalId,
          reminderKey: "deadline",
          type: "goal_deadline",
          scheduledFor: deadline,
          cloudTaskName: response.name,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (e) {
        console.error(`[GoalReminder] Failed to create deadline task:`, e);
      }
    }
  }
);

// ===============================================
// 問い合わせ・要望機能 (callable/inquiries.ts に移動)
// - createInquiry, sendInquiryMessage, sendInquiryReply, updateInquiryStatus
// ===============================================

/**
 * 問い合わせ自動クリーンアップ（毎日実行）
 * - 6日経過: 削除予告通知
 * - 7日経過: 本体削除 + アーカイブ保存
 */
export const cleanupResolvedInquiries = onSchedule(
  {
    schedule: "0 3 * * *", // 毎日午前3時（日本時間）
    timeZone: "Asia/Tokyo",
    region: "asia-northeast1",
  },
  async () => {
    console.log("=== cleanupResolvedInquiries started ===");

    const now = new Date();
    const sixDaysAgo = new Date(now.getTime() - 6 * 24 * 60 * 60 * 1000);
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    // 解決済みの問い合わせを取得
    const inquiriesSnapshot = await db.collection("inquiries")
      .where("status", "==", "resolved")
      .get();

    console.log(`Found ${inquiriesSnapshot.size} resolved inquiries`);

    for (const doc of inquiriesSnapshot.docs) {
      const inquiry = doc.data();
      const inquiryId = doc.id;
      const resolvedAt = inquiry.resolvedAt?.toDate?.();

      if (!resolvedAt) {
        console.log(`Inquiry ${inquiryId} has no resolvedAt, skipping`);
        continue;
      }

      // 7日以上経過 → 削除
      if (resolvedAt <= sevenDaysAgo) {
        console.log(`Deleting inquiry ${inquiryId} (resolved at ${resolvedAt})`);
        await deleteInquiryWithArchive(inquiryId, inquiry);
        continue;
      }

      // 6日以上経過 & 7日未満 → 削除予告通知
      if (resolvedAt <= sixDaysAgo && resolvedAt > sevenDaysAgo) {
        console.log(`Sending deletion warning for inquiry ${inquiryId}`);
        await sendDeletionWarning(inquiryId, inquiry);
      }
    }

    console.log("=== cleanupResolvedInquiries completed ===");
  }
);

/**
 * 問い合わせを削除し、アーカイブに保存
 */
async function deleteInquiryWithArchive(
  inquiryId: string,
  inquiry: FirebaseFirestore.DocumentData
): Promise<void> {
  try {
    const inquiryRef = db.collection("inquiries").doc(inquiryId);

    // 1. メッセージを取得して会話ログを作成
    const messagesSnapshot = await inquiryRef.collection("messages")
      .orderBy("createdAt", "asc")
      .get();

    let conversationLog = "";
    let firstMessage = "";

    messagesSnapshot.docs.forEach((msgDoc, index) => {
      const msg = msgDoc.data();
      const msgDate = msg.createdAt?.toDate?.() || new Date();
      const dateStr = `${msgDate.getFullYear()}-${String(msgDate.getMonth() + 1).padStart(2, "0")}-${String(msgDate.getDate()).padStart(2, "0")} ${String(msgDate.getHours()).padStart(2, "0")}:${String(msgDate.getMinutes()).padStart(2, "0")}`;
      const sender = msg.senderType === "admin" ? "運営チーム" : "ユーザー";
      conversationLog += `[${dateStr} ${sender}]\n${msg.content}\n\n`;

      if (index === 0) {
        firstMessage = msg.content || "";
      }
    });

    // 2. カテゴリラベル
    const categoryLabels: { [key: string]: string } = {
      bug: "バグ報告",
      feature: "機能要望",
      account: "アカウント関連",
      other: "その他",
    };
    const categoryLabel = categoryLabels[inquiry.category] || inquiry.category;

    // 3. 日時フォーマット
    const createdAtDate = inquiry.createdAt?.toDate?.() || new Date();
    const resolvedAtDate = inquiry.resolvedAt?.toDate?.() || new Date();
    const formatDate = (d: Date) =>
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;

    // 4. アーカイブに保存
    await db.collection("inquiry_archives").add({
      originalInquiryId: inquiryId,
      userId: inquiry.userId,
      userDisplayName: inquiry.userDisplayName,
      category: categoryLabel,
      subject: inquiry.subject,
      firstMessage,
      conversationLog: conversationLog.trim(),
      createdAt: inquiry.createdAt,
      resolvedAt: inquiry.resolvedAt,
      archivedAt: admin.firestore.FieldValue.serverTimestamp(),
      // 1年後に削除予定
      expiresAt: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000),
    });

    console.log(`Archived inquiry ${inquiryId}`);

    // 5. メッセージサブコレクションを削除
    const batch = db.batch();
    messagesSnapshot.docs.forEach((msgDoc) => {
      batch.delete(msgDoc.ref);
    });
    await batch.commit();

    console.log(`Deleted ${messagesSnapshot.size} messages for inquiry ${inquiryId}`);

    // 6. Storage画像を削除（存在する場合）
    for (const msgDoc of messagesSnapshot.docs) {
      const msg = msgDoc.data();
      if (msg.imageUrl) {
        await deleteStorageFileFromUrl(msg.imageUrl);
      }
    }

    // 7. 問い合わせ本体を削除
    await inquiryRef.delete();
    console.log(`Deleted inquiry ${inquiryId}`);

  } catch (error) {
    console.error(`Error deleting inquiry ${inquiryId}:`, error);
  }
}

/**
 * 削除予告通知を送信
 */
async function sendDeletionWarning(
  inquiryId: string,
  inquiry: FirebaseFirestore.DocumentData
): Promise<void> {
  try {
    const userId = inquiry.userId;
    const now = admin.firestore.FieldValue.serverTimestamp();
    const notifyBody = `「${inquiry.subject}」は明日削除されます（ステータス: 解決済み）`;

    // アプリ内通知
    await db.collection("users").doc(userId).collection("notifications").add({
      type: "inquiry_deletion_warning",
      title: "問い合わせ削除予告",
      body: notifyBody,
      inquiryId,
      isRead: false,
      createdAt: now,
    });

    // プッシュ通知 (onNotificationCreatedで自動送信)

    console.log(`Sent deletion warning to user ${userId} for inquiry ${inquiryId}`);
  } catch (error) {
    console.error(`Error sending deletion warning for inquiry ${inquiryId}:`, error);
  }
}

// ===============================================
// 定期実行処理
// ===============================================

/**
 * 毎日深夜に実行されるレポートクリーンアップ処理
 * 対処済み（reviewed/dismissed）かつ1ヶ月以上前のレポートを削除する
 */
export const cleanupReports = onSchedule(
  {
    schedule: "every day 00:00",
    timeZone: "Asia/Tokyo",
    timeoutSeconds: 300,
  },
  async (event) => {
    console.log("Starting cleanupReports function...");

    try {
      // 1ヶ月前の日時を計算
      const cutoffDate = new Date();
      cutoffDate.setMonth(cutoffDate.getMonth() - 1);
      const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoffDate);

      // Reviewed reports
      // status == 'reviewed' AND createdAt < cutoffTimestamp
      const reviewedSnapshot = await db
        .collection("reports")
        .where("status", "==", "reviewed")
        .where("createdAt", "<", cutoffTimestamp)
        .get();

      // Dismissed reports
      // status == 'dismissed' AND createdAt < cutoffTimestamp
      const dismissedSnapshot = await db
        .collection("reports")
        .where("status", "==", "dismissed")
        .where("createdAt", "<", cutoffTimestamp)
        .get();

      console.log(
        `Found ${reviewedSnapshot.size} reviewed and ${dismissedSnapshot.size} dismissed reports to delete.`
      );

      // 削除対象のドキュメントを結合
      const allDocs = [...reviewedSnapshot.docs, ...dismissedSnapshot.docs];

      if (allDocs.length === 0) {
        console.log("No reports to delete.");
        return;
      }

      // バッチ処理で削除（500件ずつ）
      const MAX_BATCH_SIZE = 500;
      const chunks = [];
      for (let i = 0; i < allDocs.length; i += MAX_BATCH_SIZE) {
        chunks.push(allDocs.slice(i, i + MAX_BATCH_SIZE));
      }

      let deletedCount = 0;
      for (const chunk of chunks) {
        const batch = db.batch();
        chunk.forEach((doc) => {
          batch.delete(doc.ref);
        });
        await batch.commit();
        deletedCount += chunk.length;
        console.log(`Deleted batch of ${chunk.length} reports.`);
      }

      console.log(`Cleanup completed. Total deleted: ${deletedCount}`);
    } catch (error) {
      console.error("Error in cleanupReports:", error);
    }
  }
);

// ===================================
// カスケード削除 (Post)
// ===================================
/**
 * 投稿削除トリガー
 * - コメント、リアクションの削除
 * - Storageの画像削除
 * - ユーザー/サークルの投稿数減算
 */
export const onPostDeleted = onDocumentDeleted("posts/{postId}", async (event) => {
  const snap = event.data;
  if (!snap) return;

  const postData = snap.data();
  const postId = event.params.postId;
  const userRef = postData.userId ? db.collection("users").doc(postData.userId) : null;
  const circleRef = postData.circleId ? db.collection("circles").doc(postData.circleId) : null;

  console.log(`=== onPostDeleted: postId=${postId} start ===`);

  try {
    const batch = db.batch();
    let opCount = 0;

    // 1. コメント削除
    const commentsSnap = await db.collection("comments").where("postId", "==", postId).get();
    commentsSnap.docs.forEach((doc) => {
      batch.delete(doc.ref);
      opCount++;
    });

    // 2. リアクション削除
    const reactionsSnap = await db.collection("reactions").where("postId", "==", postId).get();
    reactionsSnap.docs.forEach((doc) => {
      batch.delete(doc.ref);
      opCount++;
    });

    // 3. 関連通知の削除 (Post Owner)
    // 自分の投稿に対する「いいね」「コメント」通知などを削除
    if (userRef) {
      const notificationsSnap = await userRef.collection("notifications").where("postId", "==", postId).get();
      notificationsSnap.docs.forEach((doc) => {
        batch.delete(doc.ref);
        opCount++;
      });
    }

    // 4. ユーザー投稿数 減算
    if (userRef) {
      batch.update(userRef, {
        totalPosts: admin.firestore.FieldValue.increment(-1),
      });
      opCount++;
    }

    // 4. サークル投稿数 減算
    if (circleRef) {
      batch.update(circleRef, {
        postCount: admin.firestore.FieldValue.increment(-1),
      });
      opCount++;
    }

    if (opCount > 0) {
      await batch.commit();
      console.log(`Deleted ${commentsSnap.size} comments, ${reactionsSnap.size} reactions.`);
    }

    // 5. Storage削除（ヘルパー関数を使用）
    const mediaItems = postData.mediaItems;
    if (Array.isArray(mediaItems) && mediaItems.length > 0) {
      console.log(`Attempting to delete ${mediaItems.length} media items...`);
      for (const item of mediaItems) {
        // メディア本体を削除
        if (item.url) {
          await deleteStorageFileFromUrl(item.url);
        }
        // 動画の場合、サムネイルも削除
        if (item.thumbnailUrl) {
          await deleteStorageFileFromUrl(item.thumbnailUrl);
        }
      }
    }

  } catch (error) {
    console.error(`Error in onPostDeleted for ${postId}:`, error);
  }
});

// ===================================
// プッシュ通知自動送信
// ===================================
/**
 * 通知ドキュメント作成時に自動的にFCMプッシュ通知を送信
 * トリガー: users/{userId}/notifications/{notificationId}
 */
export const onNotificationCreated = onDocumentCreated("users/{userId}/notifications/{notificationId}", async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data();
  const userId = event.params.userId;

  // タイトルと本文があれば送信
  if (data.title && data.body) {
    try {
      // ユーザー設定を確認
      const userDoc = await db.collection("users").doc(userId).get();
      const userData = userDoc.data();
      if (!userData) return;

      const settings = userData.notificationSettings || {};
      const type = data.type;

      // 通知設定チェック (コメントとリアクションのみチェック、他は重要通知として通す)
      if (type === 'comment' && settings.comments === false) {
        console.log(`Skipping push for ${type} due to user settings`);
        return;
      }
      if (type === 'reaction' && settings.reactions === false) {
        console.log(`Skipping push for ${type} due to user settings`);
        return;
      }

      await sendPushOnly(userId, data.title, data.body, { ...data, notificationId: event.params.notificationId });
      console.log(`Auto push notification sent to ${userId} for notification ${event.params.notificationId}`);
    } catch (e) {
      console.error(`Failed to send auto push notification to ${userId}:`, e);
    }
  }
});

// ===================================
// 管理者権限管理
// ===================================

/**
 * 管理者権限を設定（既存の管理者のみが実行可能）
 */
export const setAdminRole = onCall(async (request) => {
  const callerId = request.auth?.uid;
  if (!callerId) {
    throw new HttpsError("unauthenticated", "認証が必要です");
  }

  // 呼び出し元が管理者かチェック
  const callerIsAdmin = await isAdmin(callerId);
  if (!callerIsAdmin) {
    throw new HttpsError("permission-denied", "管理者権限が必要です");
  }

  const { targetUid } = request.data;
  if (!targetUid || typeof targetUid !== "string") {
    throw new HttpsError("invalid-argument", "対象ユーザーIDが必要です");
  }

  try {
    // Custom Claimを設定
    await admin.auth().setCustomUserClaims(targetUid, { admin: true });
    console.log(`Admin role granted to user: ${targetUid} by ${callerId}`);

    return { success: true, message: `ユーザー ${targetUid} を管理者に設定しました` };
  } catch (error) {
    console.error(`Error setting admin role for ${targetUid}:`, error);
    throw new HttpsError("internal", "管理者権限の設定に失敗しました");
  }
});

/**
 * 管理者権限を削除（既存の管理者のみが実行可能）
 */
export const removeAdminRole = onCall(async (request) => {
  const callerId = request.auth?.uid;
  if (!callerId) {
    throw new HttpsError("unauthenticated", "認証が必要です");
  }

  // 呼び出し元が管理者かチェック
  const callerIsAdmin = await isAdmin(callerId);
  if (!callerIsAdmin) {
    throw new HttpsError("permission-denied", "管理者権限が必要です");
  }

  const { targetUid } = request.data;
  if (!targetUid || typeof targetUid !== "string") {
    throw new HttpsError("invalid-argument", "対象ユーザーIDが必要です");
  }

  // 自分自身の管理者権限は削除できない
  if (callerId === targetUid) {
    throw new HttpsError("invalid-argument", "自分自身の管理者権限は削除できません");
  }

  try {
    // Custom Claimを削除（adminをfalseに設定）
    const user = await admin.auth().getUser(targetUid);
    const claims = user.customClaims || {};
    delete claims.admin;
    await admin.auth().setCustomUserClaims(targetUid, claims);

    console.log(`Admin role removed from user: ${targetUid} by ${callerId}`);

    return { success: true, message: `ユーザー ${targetUid} の管理者権限を削除しました` };
  } catch (error) {
    console.error(`Error removing admin role for ${targetUid}:`, error);
    throw new HttpsError("internal", "管理者権限の削除に失敗しました");
  }
});


// ===============================================
// ユーザーBAN機能
// ===============================================

/**
 * ユーザーを一時BANにする
 */
export const banUser = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    // 呼び出し元が管理者かチェック
    if (!request.auth?.token.admin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    const { userId, reason } = request.data;
    if (!userId || !reason) {
      throw new HttpsError("invalid-argument", "userIdとreasonは必須です");
    }

    // 自分自身や他の管理者はBAN不可
    if (userId === request.auth.uid) {
      throw new HttpsError("invalid-argument", "自分自身をBANすることはできません");
    }

    // 対象ユーザー確認
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      throw new HttpsError("not-found", "ユーザーが見つかりません");
    }

    // 対象が管理者かどうかのチェックは、Firestore上のデータやCustom Claimsで確認すべきだが、
    // ここではFirestoreの管理者フラグがないため省略（ただし運用上管理者はBANされない前提）

    const banRecord = {
      type: "temporary",
      reason: reason,
      bannedAt: admin.firestore.Timestamp.now(),
      bannedBy: request.auth.uid,
    };

    const batch = db.batch();

    // ユーザー更新
    batch.update(userDoc.ref, {
      banStatus: "temporary",
      isBanned: true,
      banHistory: admin.firestore.FieldValue.arrayUnion(banRecord),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 通知送信
    const notificationRef = db.collection("users").doc(userId).collection("notifications").doc();
    batch.set(notificationRef, {
      userId: userId,
      type: "user_banned",
      title: "アカウントが一時停止されました",
      body: `規約違反のため、アカウント機能の一部を制限しました。理由: ${reason}`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Custom Claims更新
    await admin.auth().setCustomUserClaims(userId, { banned: true, banStatus: 'temporary' });

    console.log(`User ${userId} temporarily banned by ${request.auth.uid}`);
    return { success: true };
  }
);

/**
 * ユーザーを永久BANにする
 */
export const permanentBanUser = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    // Admin check
    if (!request.auth?.token.admin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    const { userId, reason } = request.data;
    if (!userId || !reason) {
      throw new HttpsError("invalid-argument", "userIdとreasonは必須です");
    }

    if (userId === request.auth.uid) {
      throw new HttpsError("invalid-argument", "自分自身をBANすることはできません");
    }

    const banRecord = {
      type: "permanent",
      reason: reason,
      bannedAt: admin.firestore.Timestamp.now(),
      bannedBy: request.auth.uid,
    };

    const batch = db.batch();

    // 180日後の日付
    const deletionDate = new Date();
    deletionDate.setDate(deletionDate.getDate() + 180);

    batch.update(db.collection("users").doc(userId), {
      banStatus: "permanent",
      isBanned: true,
      banHistory: admin.firestore.FieldValue.arrayUnion(banRecord),
      permanentBanScheduledDeletionAt: admin.firestore.Timestamp.fromDate(deletionDate),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 通知（機能しませんが記録として）
    const notificationRef = db.collection("users").doc(userId).collection("notifications").doc();
    batch.set(notificationRef, {
      userId: userId,
      type: "user_banned",
      title: "アカウントが永久停止されました",
      body: `規約違反のため、アカウントを永久停止しました。理由: ${reason}`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Auth無効化 & トークン破棄
    try {
      await admin.auth().updateUser(userId, { disabled: true });
      await admin.auth().revokeRefreshTokens(userId);
      // Custom Claims更新
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
  { region: "asia-northeast1" },
  async (request) => {
    // Admin check
    if (!request.auth?.token.admin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    const { userId } = request.data;
    if (!userId) {
      throw new HttpsError("invalid-argument", "userIdは必須です");
    }

    const batch = db.batch();

    batch.update(db.collection("users").doc(userId), {
      banStatus: "none",
      isBanned: false,
      permanentBanScheduledDeletionAt: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 解除通知
    const notificationRef = db.collection("users").doc(userId).collection("notifications").doc();
    batch.set(notificationRef, {
      userId: userId,
      type: "user_unbanned",
      title: "アカウント制限が解除されました",
      body: `アカウントの制限が解除されました。`,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // banAppealsの削除（該当ユーザーのチャット履歴を削除）
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
      // Custom Claims更新（bannedフラグ削除）
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

/**
 * 永久BANユーザーのデータ削除クリーンアップ（毎日午前4時）
 */
export const cleanupBannedUsers = onSchedule(
  {
    schedule: "0 4 * * *",
    timeZone: "Asia/Tokyo",
    region: "asia-northeast1",
    timeoutSeconds: 540,
  },
  async () => {
    console.log("=== cleanupBannedUsers START ===");
    const now = admin.firestore.Timestamp.now();

    const snapshot = await db.collection("users")
      .where("banStatus", "==", "permanent")
      .where("permanentBanScheduledDeletionAt", "<=", now)
      .limit(20)
      .get();

    if (snapshot.empty) {
      console.log("No users to delete");
      return;
    }

    console.log(`Found ${snapshot.size} users to scheduled delete`);

    for (const doc of snapshot.docs) {
      try {
        const uid = doc.id;
        console.log(`Deleting banned user: ${uid}`);

        await admin.auth().deleteUser(uid).catch(e => {
          console.warn(`Auth delete failed for ${uid}:`, e);
        });

        // ユーザードキュメント削除
        await db.collection("users").doc(uid).delete();

      } catch (error) {
        console.error(`Error deleting user ${doc.id}:`, error);
      }
    }

    console.log("=== cleanupBannedUsers COMPLETE ===");
  }
);

