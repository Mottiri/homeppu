/**
 * サークル関連のFirestoreトリガー
 * - onCircleCreated: サークル作成時にAI3体を自動生成
 * - onCircleUpdated: サークル設定変更時にメンバーへ通知
 */

import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { db, FieldValue, Timestamp } from "../helpers/firebase";
import { deleteStorageFileFromUrl } from "../helpers/storage";
import { generateCircleAIPersona } from "../circle-ai/generator";
import { generateNameTokens } from "../helpers/search-tokens";
import { computeInitialCircleAIPostAt } from "../helpers/circle-scheduling";
import { LOCATION } from "../config/constants";
import { NOTIFICATION_TITLES, LABELS } from "../config/messages";

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
      return;
    }

    const circleData = snapshot.data();
    const circleId = event.params.circleId;


    // nameTokens を補完（createCircle callable経由なら既にセット済み、直接書き込みの場合のみ必要）
    try {
      const existingTokens = circleData.nameTokens;
      if (!existingTokens || existingTokens.length === 0) {
        const nameTokens = generateNameTokens(circleData.name || "");
        if (nameTokens.length > 0) {
          await db.collection("circles").doc(circleId).update({ nameTokens });
        }
      }
    } catch (tokenError) {
      console.error(`Failed to set nameTokens for circle ${circleId}:`, tokenError);
      // nameTokens失敗はAI生成をブロックしない
    }

    // humanOnlyモードの場合はAIを生成しないが、hasSpaceは設定する
    if (circleData.aiMode === "humanOnly") {
      const maxMembers: number = circleData.maxMembers ?? 20;
      const currentMemberIds = circleData.memberIds || [];
      await db.collection("circles").doc(circleId).update({
        generatedAICount: 0,
        aiPostingEnabled: false,
        nextCircleAIPostAt: null,
        hasSpace: currentMemberIds.length < maxMembers,
      });
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
          lastGrowthAt: Timestamp.fromDate(aiPersona.lastGrowthAt),
          publicMode: "mix", // AIはmixモードで動作
          virtue: 100, // 初期徳ポイント
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });

        aiMemberIds.push(aiPersona.id);
      }

      // バッチでAIユーザーを作成
      await batch.commit();

      // サークルドキュメントを更新（AI情報とメンバー数を更新）
      const currentMemberIds = circleData.memberIds || [];
      const updatedMemberIds = [...currentMemberIds, ...aiMemberIds];

      const maxMembers: number = circleData.maxMembers ?? 20;
      const createdAt = circleData.createdAt?.toDate?.() || new Date();
      await db.collection("circles").doc(circleId).update({
        generatedAIs: generatedAIs,
        generatedAICount: generatedAIs.length,
        aiPostingEnabled: generatedAIs.length > 0,
        nextCircleAIPostAt: Timestamp.fromDate(computeInitialCircleAIPostAt(createdAt)),
        memberIds: updatedMemberIds,
        memberCount: updatedMemberIds.length,
        hasSpace: updatedMemberIds.length < maxMembers,
      });
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
      return;
    }

    try {
      // ===== 名前変更時のnameTokens更新 =====
      if (beforeData.name !== afterData.name) {
        const nameTokens = generateNameTokens(afterData.name || "");
        await db.collection("circles").doc(circleId).update({ nameTokens });
      }

      // ===== 画像変更時の古い画像削除 =====
      // アイコン画像が変更された場合、古い画像を削除
      if (beforeData.iconImageUrl && beforeData.iconImageUrl !== afterData.iconImageUrl) {
        await deleteStorageFileFromUrl(beforeData.iconImageUrl);
      }

      // カバー画像が変更された場合、古い画像を削除
      if (beforeData.coverImageUrl && beforeData.coverImageUrl !== afterData.coverImageUrl) {
        await deleteStorageFileFromUrl(beforeData.coverImageUrl);
      }

      // ===== 通知すべき変更を検出 =====
      const changes: string[] = [];

      // 変更された項目をチェック
      if (beforeData.name !== afterData.name) {
        changes.push(`名前: ${beforeData.name} → ${afterData.name}`);
      }
      if (beforeData.description !== afterData.description) {
        changes.push(LABELS.CHANGE_DESCRIPTION);
      }
      if (beforeData.category !== afterData.category) {
        changes.push(`カテゴリ: ${beforeData.category} → ${afterData.category}`);
      }
      if (beforeData.goal !== afterData.goal) {
        changes.push(LABELS.CHANGE_GOAL);
      }
      if (beforeData.rules !== afterData.rules) {
        changes.push(LABELS.CHANGE_RULES);
      }
      if (beforeData.isPublic !== afterData.isPublic) {
        changes.push(afterData.isPublic ? LABELS.CHANGE_PUBLIC : LABELS.CHANGE_PRIVATE);
      }
      if (beforeData.isInviteOnly !== afterData.isInviteOnly) {
        changes.push(afterData.isInviteOnly ? LABELS.CHANGE_INVITE_ONLY : LABELS.CHANGE_INVITE_DISABLED);
      }
      if (beforeData.participationMode !== afterData.participationMode) {
        const modeLabels: { [key: string]: string } = {
          ai: LABELS.MODE_AI,
          mix: LABELS.MODE_MIX,
          human: LABELS.MODE_HUMAN,
        };
        const oldMode = modeLabels[beforeData.participationMode] || beforeData.participationMode;
        const newMode = modeLabels[afterData.participationMode] || afterData.participationMode;
        changes.push(`参加モード: ${oldMode} → ${newMode}`);
      }

      // AI情報やメンバー数など内部的な更新は通知しない
      if (changes.length === 0) {
        return;
      }

      // オーナー情報を取得
      const ownerId = afterData.ownerId;
      const ownerDoc = await db.collection("users").doc(ownerId).get();
      const ownerName = ownerDoc.exists ? ownerDoc.data()?.displayName || LABELS.OWNER : LABELS.OWNER;
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
            title: NOTIFICATION_TITLES.CIRCLE_UPDATED,
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
    } catch (error) {
      console.error(`=== onCircleUpdated ERROR:`, error);
    }
  }
);
