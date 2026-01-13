/**
 * サークル関連のFirestoreトリガー
 * - onCircleCreated: サークル作成時にAI3体を自動生成
 * - onCircleUpdated: サークル設定変更時にメンバーへ通知
 */

import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { db, FieldValue } from "../helpers/firebase";
import { deleteStorageFileFromUrl } from "../helpers/storage";
import { generateCircleAIPersona } from "../circle-ai/generator";
import { LOCATION } from "../config/constants";

/**
 * サークル作成時にAI3体を自動生成
 */
export const onCircleCreated = onDocumentCreated(
  {
    document: "circles/{circleId}",
    region: LOCATION,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No document data");
      return;
    }

    const circleData = snapshot.data();
    const circleId = event.params.circleId;

    console.log(`=== onCircleCreated: ${circleId} ===`);
    console.log(`Circle name: ${circleData.name}, AI mode: ${circleData.aiMode}`);

    // humanOnlyモードの場合はAIを生成しない
    if (circleData.aiMode === "humanOnly") {
      console.log(`Circle ${circleId} is humanOnly mode, skipping AI generation`);
      return;
    }

    try {
      // サークル情報を取得
      const circleInfo = {
        name: circleData.name || "",
        description: circleData.description || "",
        category: circleData.category || "その他",
      };

      // AI3体を生成してusersコレクションに作成
      const generatedAIs = [];
      const aiMemberIds = [];
      const batch = db.batch();

      for (let i = 0; i < 3; i++) {
        const aiPersona = generateCircleAIPersona(circleInfo, i);
        generatedAIs.push(aiPersona);

        // usersコレクションにAIユーザードキュメントを作成
        const aiUserRef = db.collection("users").doc(aiPersona.id);
        batch.set(aiUserRef, {
          uid: aiPersona.id,
          displayName: aiPersona.name,
          bio: aiPersona.bio,
          avatarIndex: aiPersona.avatarIndex,
          namePrefixId: aiPersona.namePrefixId,
          nameSuffixId: aiPersona.nameSuffixId,
          isAI: true,
          circleId: circleId, // このAIが所属するサークル
          circleContext: aiPersona.circleContext,
          growthLevel: aiPersona.growthLevel,
          lastGrowthAt: admin.firestore.Timestamp.fromDate(aiPersona.lastGrowthAt),
          publicMode: "mix", // AIはmixモードで動作
          virtue: 100, // 初期徳ポイント
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });

        aiMemberIds.push(aiPersona.id);
        console.log(`Generated AI ${i + 1}: ${aiPersona.name} (${aiPersona.id})`);
      }

      // バッチでAIユーザーを作成
      await batch.commit();

      // サークルドキュメントを更新（AI情報とメンバー数を更新）
      const currentMemberIds = circleData.memberIds || [];
      const updatedMemberIds = [...currentMemberIds, ...aiMemberIds];

      await db.collection("circles").doc(circleId).update({
        generatedAIs: generatedAIs,
        memberIds: updatedMemberIds,
        memberCount: updatedMemberIds.length,
      });

      console.log(`=== onCircleCreated SUCCESS: Added ${generatedAIs.length} AIs to ${circleId} ===`);

    } catch (error) {
      console.error(`=== onCircleCreated ERROR:`, error);
    }
  }
);

/**
 * サークル設定変更時にメンバーへ通知
 */
export const onCircleUpdated = onDocumentUpdated(
  {
    document: "circles/{circleId}",
    region: LOCATION,
  },
  async (event) => {
    const beforeData = event.data?.before?.data();
    const afterData = event.data?.after?.data();
    const circleId = event.params.circleId;

    if (!beforeData || !afterData) {
      console.log("No document data");
      return;
    }

    console.log(`=== onCircleUpdated START: ${circleId} ===`);

    try {
      // ===== 画像変更時の古い画像削除 =====
      // アイコン画像が変更された場合、古い画像を削除
      if (beforeData.iconImageUrl && beforeData.iconImageUrl !== afterData.iconImageUrl) {
        console.log(`Icon image changed, deleting old: ${beforeData.iconImageUrl}`);
        await deleteStorageFileFromUrl(beforeData.iconImageUrl);
      }

      // カバー画像が変更された場合、古い画像を削除
      if (beforeData.coverImageUrl && beforeData.coverImageUrl !== afterData.coverImageUrl) {
        console.log(`Cover image changed, deleting old: ${beforeData.coverImageUrl}`);
        await deleteStorageFileFromUrl(beforeData.coverImageUrl);
      }

      // ===== 通知すべき変更を検出 =====
      const changes: string[] = [];

      // 変更された項目をチェック
      if (beforeData.name !== afterData.name) {
        changes.push(`名前: ${beforeData.name} → ${afterData.name}`);
      }
      if (beforeData.description !== afterData.description) {
        changes.push("説明が変更されました");
      }
      if (beforeData.category !== afterData.category) {
        changes.push(`カテゴリ: ${beforeData.category} → ${afterData.category}`);
      }
      if (beforeData.goal !== afterData.goal) {
        changes.push("目標が変更されました");
      }
      if (beforeData.rules !== afterData.rules) {
        changes.push("ルールが変更されました");
      }
      if (beforeData.isPublic !== afterData.isPublic) {
        changes.push(afterData.isPublic ? "公開に変更" : "非公開に変更");
      }
      if (beforeData.isInviteOnly !== afterData.isInviteOnly) {
        changes.push(afterData.isInviteOnly ? "招待制に変更" : "招待制を解除");
      }
      if (beforeData.participationMode !== afterData.participationMode) {
        const modeLabels: { [key: string]: string } = {
          ai: "AIモード",
          mix: "MIXモード",
          human: "人間モード",
        };
        const oldMode = modeLabels[beforeData.participationMode] || beforeData.participationMode;
        const newMode = modeLabels[afterData.participationMode] || afterData.participationMode;
        changes.push(`参加モード: ${oldMode} → ${newMode}`);
      }

      // AI情報やメンバー数など内部的な更新は通知しない
      if (changes.length === 0) {
        console.log("No user-facing changes detected, skipping notification");
        return;
      }

      console.log(`Changes detected: ${changes.join(", ")}`);

      // オーナー情報を取得
      const ownerId = afterData.ownerId;
      const ownerDoc = await db.collection("users").doc(ownerId).get();
      const ownerName = ownerDoc.exists ? ownerDoc.data()?.displayName || "オーナー" : "オーナー";
      const ownerAvatarIndex = ownerDoc.exists ? ownerDoc.data()?.avatarIndex?.toString() || "0" : "0";

      // メンバー一覧を取得（オーナーとAI以外）
      const memberIds: string[] = afterData.memberIds || [];
      const circleName = afterData.name;

      // 通知メッセージ
      const notificationBody = changes.length === 1
        ? changes[0]
        : `${changes.length}件の設定が変更されました`;

      // 各メンバーに通知
      for (const memberId of memberIds) {
        if (memberId === ownerId) continue;
        if (memberId.startsWith("circle_ai_")) continue; // AIはスキップ

        try {
          // アプリ内通知を作成
          await db.collection("users").doc(memberId).collection("notifications").add({
            type: "circle_settings_changed",
            senderId: ownerId,
            senderName: ownerName,
            senderAvatarUrl: ownerAvatarIndex,
            title: "サークルが更新されました",
            body: `${circleName}: ${notificationBody}`,
            circleName: circleName,
            circleId: circleId,
            changes: changes,
            isRead: false,
            createdAt: FieldValue.serverTimestamp(),
          });
          // プッシュ通知はonNotificationCreatedトリガーで自動送信される
        } catch (notifyError) {
          console.error(`Failed to notify member ${memberId}:`, notifyError);
        }
      }

      console.log(`=== onCircleUpdated SUCCESS: Notified ${memberIds.length - 1} members ===`);

    } catch (error) {
      console.error(`=== onCircleUpdated ERROR:`, error);
    }
  }
);
