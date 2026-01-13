/**
 * サークル関連のスケジュール実行関数
 * - checkGhostCircles: ゴースト・放置サークルの検出と削除
 * - evolveCircleAIs: サークルAI成長システム（月1回）
 * - triggerEvolveCircleAIs: 手動トリガー（管理者用）
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as functionsV1 from "firebase-functions/v1";
import { CloudTasksClient } from "@google-cloud/tasks";
import { db, FieldValue } from "../helpers/firebase";
import { isAdmin } from "../helpers/admin";
import { PROJECT_ID, LOCATION } from "../config/constants";

// サークル定期クリーンアップ定数
const GHOST_THRESHOLD_DAYS = 365; // 人間投稿なしの日数
const EMPTY_THRESHOLD_DAYS = 30;  // 投稿0サークルの猶予日数
const DELETE_GRACE_DAYS = 7;      // 通知から削除までの猶予

/**
 * ゴースト・放置サークルをチェックして通知・削除
 * 毎日午前3時30分に実行
 */
export const checkGhostCircles = onSchedule(
  {
    schedule: "30 3 * * *", // 毎日午前3時30分 JST
    timeZone: "Asia/Tokyo",
    region: LOCATION,
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    console.log("=== checkGhostCircles START ===");
    const now = Date.now();
    const ghostThreshold = new Date(now - GHOST_THRESHOLD_DAYS * 24 * 60 * 60 * 1000);
    const emptyThreshold = new Date(now - EMPTY_THRESHOLD_DAYS * 24 * 60 * 60 * 1000);
    const deleteThreshold = new Date(now - DELETE_GRACE_DAYS * 24 * 60 * 60 * 1000);

    let notifiedCount = 0;
    let deletedCount = 0;

    try {
      // 削除済みでないサークルを取得
      const circlesSnapshot = await db.collection("circles")
        .where("isDeleted", "!=", true)
        .get();

      console.log(`Checking ${circlesSnapshot.size} circles...`);

      for (const circleDoc of circlesSnapshot.docs) {
        const circleId = circleDoc.id;
        const circleData = circleDoc.data();
        const circleName = circleData.name || "サークル";
        const ownerId = circleData.ownerId;
        const createdAt = circleData.createdAt?.toDate?.() || new Date();
        const lastHumanPostAt = circleData.lastHumanPostAt?.toDate?.();
        const ghostWarningNotifiedAt = circleData.ghostWarningNotifiedAt?.toDate?.();

        // 判定: ゴーストサークル or 放置サークル
        let isGhost = false;
        let isEmpty = false;

        if (lastHumanPostAt && lastHumanPostAt < ghostThreshold) {
          isGhost = true;
        }
        // 放置サークル: 人間の投稿が1個もない + 作成から30日経過
        if (!lastHumanPostAt && createdAt < emptyThreshold) {
          isEmpty = true;
        }

        if (!isGhost && !isEmpty) {
          continue; // 対象外
        }

        const warningType = isGhost ? "ゴースト" : "放置";
        console.log(`Found ${warningType} circle: ${circleName} (${circleId})`);

        if (!ghostWarningNotifiedAt) {
          // 未通知 → オーナーに警告通知を送信
          const ownerDoc = await db.collection("users").doc(ownerId).get();
          if (!ownerDoc.exists) {
            console.log(`Owner ${ownerId} not found, skipping notification`);
            continue;
          }

          const reasonText = isGhost
            ? "1年以上人間の投稿がない"
            : "作成から1ヶ月以上経過しても投稿がない";

          await db.collection("users").doc(ownerId).collection("notifications").add({
            type: "circle_ghost_warning",
            title: "⚠️ サークル削除予定のお知らせ",
            body: `「${circleName}」は${reasonText}ため、1週間後に自動削除されます。継続する場合は投稿してください。`,
            circleId,
            circleName,
            isRead: false,
            createdAt: FieldValue.serverTimestamp(),
          });

          await circleDoc.ref.update({
            ghostWarningNotifiedAt: FieldValue.serverTimestamp(),
          });

          console.log(`Sent warning notification to owner of ${circleName}`);
          notifiedCount++;

        } else if (ghostWarningNotifiedAt < deleteThreshold) {
          // 通知から7日経過 → 削除実行
          console.log(`Deleting ghost circle: ${circleName} (notified at ${ghostWarningNotifiedAt.toISOString()})`);

          // ソフトデリートマーク
          await circleDoc.ref.update({
            isDeleted: true,
            deletedAt: FieldValue.serverTimestamp(),
            deletedBy: "system_ghost_cleanup",
            deleteReason: isGhost ? "1年以上人間の投稿がないため自動削除" : "投稿がなく放置されていたため自動削除",
          });

          // Cloud Tasksでバックグラウンド削除をスケジュール
          const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
          const tasksClient = new CloudTasksClient();
          const queuePath = tasksClient.queuePath(project, LOCATION, "circle-cleanup");
          const targetUrl = `https://${LOCATION}-${project}.cloudfunctions.net/cleanupDeletedCircle`;

          await tasksClient.createTask({
            parent: queuePath,
            task: {
              httpRequest: {
                httpMethod: "POST" as const,
                url: targetUrl,
                body: Buffer.from(JSON.stringify({ circleId, circleName })).toString("base64"),
                headers: { "Content-Type": "application/json" },
                oidcToken: { serviceAccountEmail: `cloud-tasks-sa@${project}.iam.gserviceaccount.com` },
              },
              scheduleTime: { seconds: Math.floor(Date.now() / 1000) + 5 },
            },
          });

          // オーナーに削除完了通知
          await db.collection("users").doc(ownerId).collection("notifications").add({
            type: "circle_ghost_deleted",
            title: "🗑️ サークルが削除されました",
            body: `「${circleName}」は活動がなかったため、自動削除されました。`,
            circleName,
            isRead: false,
            createdAt: FieldValue.serverTimestamp(),
          });

          console.log(`Scheduled cleanup for ${circleName}`);
          deletedCount++;
        } else {
          console.log(`Circle ${circleName} is waiting for deletion (notified ${Math.floor((now - ghostWarningNotifiedAt.getTime()) / (24 * 60 * 60 * 1000))} days ago)`);
        }
      }

      console.log(`=== checkGhostCircles COMPLETE: notified=${notifiedCount}, deleted=${deletedCount} ===`);
    } catch (error) {
      console.error("=== checkGhostCircles ERROR:", error);
    }
  }
);

/**
 * サークルAIの成長イベント（毎月1日に実行）
 * growthLevel: 0=初心者, 1-2=初級, 3-4=中級初め, 5=中級（上限）
 */
export const evolveCircleAIs = functionsV1.region(LOCATION).runWith({
  timeoutSeconds: 300,
  memory: "256MB",
}).pubsub.schedule("0 10 1 * *").timeZone("Asia/Tokyo").onRun(async () => {
  console.log("=== evolveCircleAIs START (Monthly Growth Event) ===");

  try {
    // growthLevel < 5 のサークルAIを取得
    const aiUsersSnapshot = await db.collection("users")
      .where("isAI", "==", true)
      .where("circleId", "!=", null)
      .get();

    let evolvedCount = 0;
    const batch = db.batch();
    const now = new Date();

    for (const userDoc of aiUsersSnapshot.docs) {
      const userData = userDoc.data();
      const currentLevel = userData.growthLevel || 0;
      const lastGrowthAt = userData.lastGrowthAt?.toDate() || new Date(0);

      // 30日以上経過していない場合はスキップ
      const daysSinceLastGrowth = Math.floor((now.getTime() - lastGrowthAt.getTime()) / (1000 * 60 * 60 * 24));
      if (daysSinceLastGrowth < 30) {
        console.log(`${userData.displayName}: Only ${daysSinceLastGrowth} days since last growth, skipping`);
        continue;
      }

      // 上限チェック（中級者=5で成長停止）
      if (currentLevel >= 5) {
        console.log(`${userData.displayName}: Already at max level (${currentLevel}), skipping`);
        continue;
      }

      // 成長ロジック：80%の確率で成長（運も演出）
      if (Math.random() > 0.8) {
        console.log(`${userData.displayName}: Unlucky this month, no growth`);
        continue;
      }

      // レベルアップ
      const newLevel = currentLevel + 1;
      batch.update(userDoc.ref, {
        growthLevel: newLevel,
        lastGrowthAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      console.log(`${userData.displayName}: Level up! ${currentLevel} -> ${newLevel}`);
      evolvedCount++;
    }

    if (evolvedCount > 0) {
      await batch.commit();
    }

    console.log(`=== evolveCircleAIs COMPLETE: ${evolvedCount} AIs evolved ===`);

  } catch (error) {
    console.error("=== evolveCircleAIs ERROR:", error);
  }
});

/**
 * サークルAI成長を手動トリガー（テスト用）
 */
export const triggerEvolveCircleAIs = onCall(
  { region: LOCATION, timeoutSeconds: 120 },
  async (request) => {
    // セキュリティ: 管理者権限チェック
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const userIsAdmin = await isAdmin(request.auth.uid);
    if (!userIsAdmin) {
      throw new HttpsError("permission-denied", "管理者権限が必要です");
    }

    console.log("=== triggerEvolveCircleAIs (manual) START ===");

    try {
      const aiUsersSnapshot = await db.collection("users")
        .where("isAI", "==", true)
        .where("circleId", "!=", null)
        .get();

      let evolvedCount = 0;
      const batch = db.batch();

      for (const userDoc of aiUsersSnapshot.docs) {
        const userData = userDoc.data();
        const currentLevel = userData.growthLevel || 0;

        if (currentLevel >= 5) continue;

        // テスト用：100%成長
        const newLevel = currentLevel + 1;
        batch.update(userDoc.ref, {
          growthLevel: newLevel,
          lastGrowthAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });

        evolvedCount++;
      }

      if (evolvedCount > 0) {
        await batch.commit();
      }

      return {
        success: true,
        message: `${evolvedCount}体のサークルAIが成長しました`,
        evolvedCount,
      };

    } catch (error) {
      console.error("triggerEvolveCircleAIs ERROR:", error);
      return { success: false, message: `エラー: ${error}` };
    }
  }
);
