/**
 * サークル関連の定期処理
 * - checkGhostCircles: ゴースト/放置サークルの警告と削除
 * - evolveCircleAIs: サークルAIの月次進化
 * - triggerEvolveCircleAIs: 管理者向け手動トリガー
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as functionsV1 from "firebase-functions/v1";
import { scheduleHttpTask } from "../helpers/cloud-tasks";
import { db, FieldValue, Timestamp } from "../helpers/firebase";
import { isAdmin } from "../helpers/admin";
import {
  GHOST_THRESHOLD_DAYS,
  EMPTY_THRESHOLD_DAYS,
  DELETE_GRACE_DAYS,
  computeNextGhostCheckAt,
} from "../helpers/circle-scheduling";
import { PROJECT_ID, LOCATION } from "../config/constants";
import {
  AUTH_ERRORS,
  NOTIFICATION_TITLES,
  NOTIFICATION_BODIES,
  LABELS,
  SUCCESS_MESSAGES,
} from "../config/messages";

/**
 * ゴースト/放置サークルの warning/delete を due-at ベースで処理
 * 毎日 21:00 JST に実行
 */
export const checkGhostCircles = onSchedule(
  {
    schedule: "0 21 * * *",
    timeZone: "Asia/Tokyo",
    region: LOCATION,
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    console.log("=== checkGhostCircles START ===");

    const now = new Date();
    const nowMs = now.getTime();
    const ghostThreshold = new Date(nowMs - GHOST_THRESHOLD_DAYS * 24 * 60 * 60 * 1000);
    const emptyThreshold = new Date(nowMs - EMPTY_THRESHOLD_DAYS * 24 * 60 * 60 * 1000);
    const deleteThreshold = new Date(nowMs - DELETE_GRACE_DAYS * 24 * 60 * 60 * 1000);

    let notifiedCount = 0;
    let deletedCount = 0;
    let rescheduledCount = 0;

    try {
      const circlesSnapshot = await db.collection("circles")
        .where("isDeleted", "==", false)
        .where("nextGhostCheckAt", "<=", Timestamp.fromDate(now))
        .orderBy("nextGhostCheckAt", "asc")
        .limit(200)
        .get();
      for (const circleDoc of circlesSnapshot.docs) {
        const circleId = circleDoc.id;
        const circleData = circleDoc.data();
        const circleName = circleData.name || LABELS.CIRCLE;
        const ownerId = circleData.ownerId;
        const createdAt = circleData.createdAt?.toDate?.() || now;
        const lastHumanPostAt = circleData.lastHumanPostAt?.toDate?.() || null;
        const ghostWarningNotifiedAt = circleData.ghostWarningNotifiedAt?.toDate?.() || null;

        const isGhost = !!lastHumanPostAt && lastHumanPostAt < ghostThreshold;
        const isEmpty = !lastHumanPostAt && createdAt < emptyThreshold;

        if (!isGhost && !isEmpty) {
          const resetData: Record<string, unknown> = {
            nextGhostCheckAt: Timestamp.fromDate(
              computeNextGhostCheckAt({
                createdAt,
                lastHumanPostAt,
                ghostWarningNotifiedAt: null,
              })
            ),
          };
          if (ghostWarningNotifiedAt) {
            resetData.ghostWarningNotifiedAt = FieldValue.delete();
          }
          await circleDoc.ref.update(resetData);
          rescheduledCount++;
          continue;
        }

        if (!ghostWarningNotifiedAt) {
          if (typeof ownerId !== "string" || ownerId.length === 0) {
            await circleDoc.ref.update({
              ghostWarningNotifiedAt: FieldValue.serverTimestamp(),
              nextGhostCheckAt: Timestamp.fromDate(
                computeNextGhostCheckAt({
                  createdAt,
                  lastHumanPostAt,
                  ghostWarningNotifiedAt: now,
                })
              ),
            });
            rescheduledCount++;
            continue;
          }

          const ownerDoc = await db.collection("users").doc(ownerId).get();
          if (!ownerDoc.exists) {
            await circleDoc.ref.update({
              ghostWarningNotifiedAt: FieldValue.serverTimestamp(),
              nextGhostCheckAt: Timestamp.fromDate(
                computeNextGhostCheckAt({
                  createdAt,
                  lastHumanPostAt,
                  ghostWarningNotifiedAt: now,
                })
              ),
            });
            rescheduledCount++;
            continue;
          }

          const reasonText = isGhost ? LABELS.WARNING_GHOST : LABELS.WARNING_ABANDONED;
          await db.collection("users").doc(ownerId).collection("notifications").add({
            type: "circle_ghost_warning",
            title: NOTIFICATION_TITLES.CIRCLE_DELETE_WARNING,
            body: NOTIFICATION_BODIES.circleDeleteWarning(circleName, reasonText),
            circleId,
            circleName,
            isRead: false,
            createdAt: FieldValue.serverTimestamp(),
          });

          await circleDoc.ref.update({
            ghostWarningNotifiedAt: FieldValue.serverTimestamp(),
            nextGhostCheckAt: Timestamp.fromDate(
              computeNextGhostCheckAt({
                createdAt,
                lastHumanPostAt,
                ghostWarningNotifiedAt: now,
              })
            ),
          });

          notifiedCount++;
          continue;
        }

        if (ghostWarningNotifiedAt < deleteThreshold) {
          await circleDoc.ref.update({
            isDeleted: true,
            deletedAt: FieldValue.serverTimestamp(),
            deletedBy: "system_ghost_cleanup",
            deleteReason: isGhost ? LABELS.DELETE_REASON_GHOST : LABELS.DELETE_REASON_ABANDONED,
          });

          const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
          const targetUrl = `https://${LOCATION}-${project}.cloudfunctions.net/cleanupDeletedCircle`;

          await scheduleHttpTask({
            queue: "circle-cleanup",
            url: targetUrl,
            payload: { circleId, circleName },
            scheduleTime: new Date(Date.now() + 5 * 1000),
            projectId: project,
            location: LOCATION,
          });

          if (typeof ownerId === "string" && ownerId.length > 0) {
            const ownerDoc = await db.collection("users").doc(ownerId).get();
            if (ownerDoc.exists) {
              await db.collection("users").doc(ownerId).collection("notifications").add({
                type: "circle_ghost_deleted",
                title: NOTIFICATION_TITLES.CIRCLE_AUTO_DELETED,
                body: NOTIFICATION_BODIES.circleAutoDeleted(circleName),
                circleId,
                circleName,
                isRead: false,
                createdAt: FieldValue.serverTimestamp(),
              });
            }
          }

          deletedCount++;
          continue;
        }

        await circleDoc.ref.update({
          nextGhostCheckAt: Timestamp.fromDate(
            computeNextGhostCheckAt({
              createdAt,
              lastHumanPostAt,
              ghostWarningNotifiedAt,
            })
          ),
        });
        rescheduledCount++;
      }

      console.log(
        `=== checkGhostCircles COMPLETE: notified=${notifiedCount}, ` +
        `deleted=${deletedCount}, rescheduled=${rescheduledCount} ===`
      );
    } catch (error) {
      console.error("=== checkGhostCircles ERROR:", error);
    }
  }
);

/**
 * サークルAIの月次進化イベント
 * growthLevel: 0=初期, 1-2=初級, 3-4=中級, 5=中級+
 */
export const evolveCircleAIs = functionsV1.region(LOCATION).runWith({
  timeoutSeconds: 300,
  memory: "256MB",
}).pubsub.schedule("0 10 1 * *").timeZone("Asia/Tokyo").onRun(async () => {
  console.log("=== evolveCircleAIs START (Monthly Growth Event) ===");

  try {
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

      const daysSinceLastGrowth = Math.floor((now.getTime() - lastGrowthAt.getTime()) / (1000 * 60 * 60 * 24));
      if (daysSinceLastGrowth < 30) {
        continue;
      }

      if (currentLevel >= 5) {
        continue;
      }

      if (Math.random() > 0.8) {
        continue;
      }

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

    console.log(`=== evolveCircleAIs COMPLETE: ${evolvedCount} AIs evolved ===`);
  } catch (error) {
    console.error("=== evolveCircleAIs ERROR:", error);
  }
});

/**
 * サークルAI進化の手動トリガー（テスト用）
 */
export const triggerEvolveCircleAIs = onCall(
  { region: LOCATION, timeoutSeconds: 120, enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", AUTH_ERRORS.UNAUTHENTICATED);
    }
    const userIsAdmin = await isAdmin(request.auth.uid);
    if (!userIsAdmin) {
      throw new HttpsError("permission-denied", AUTH_ERRORS.ADMIN_REQUIRED);
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
        message: SUCCESS_MESSAGES.circleAIsEvolved(evolvedCount),
        evolvedCount,
      };
    } catch (error) {
      console.error("triggerEvolveCircleAIs ERROR:", error);
      return { success: false, message: `エラー: ${error}` };
    }
  }
);
