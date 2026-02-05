/**
 * 名前パーツ関連のCallable Functions
 * - initializeNameParts: 名前パーツマスタを初期化（管理者用）
 * - getNameParts: 名前パーツ一覧を取得
 * - updateUserName: ユーザー名を更新
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db, FieldValue } from "../helpers/firebase";
import { requireAdmin, requireAuth } from "../helpers/auth";
import { NamePart, PREFIX_PARTS, SUFFIX_PARTS } from "../ai/personas";
import { LOCATION } from "../config/constants";
import {
  RESOURCE_ERRORS,
  VALIDATION_ERRORS,
  PERMISSION_ERRORS,
  SUCCESS_MESSAGES,
} from "../config/messages";

/**
 * 名前パーツマスタを初期化する関数（管理者用）
 */
export const initializeNameParts = onCall(
  { region: LOCATION, enforceAppCheck: true },
  async (request) => {
    // セキュリティ: 管理者権限チェック
    await requireAdmin(request);

    const batch = db.batch();
    let prefixCount = 0;
    let suffixCount = 0;

    // 形容詞パーツを追加
    for (const part of PREFIX_PARTS) {
      const docRef = db.collection("nameParts").doc(`prefix_${part.id} `);
      batch.set(docRef, {
        ...part,
        type: "prefix",
        createdAt: FieldValue.serverTimestamp(),
      });
      prefixCount++;
    }

    // 名詞パーツを追加
    for (const part of SUFFIX_PARTS) {
      const docRef = db.collection("nameParts").doc(`suffix_${part.id} `);
      batch.set(docRef, {
        ...part,
        type: "suffix",
        createdAt: FieldValue.serverTimestamp(),
      });
      suffixCount++;
    }

    await batch.commit();

    console.log(`Initialized ${prefixCount} prefix parts and ${suffixCount} suffix parts`);

    return {
      success: true,
      message: SUCCESS_MESSAGES.NAME_PARTS_INITIALIZED,
      prefixCount,
      suffixCount,
    };
  }
);

/**
 * 名前パーツ一覧を取得する関数
 */
export const getNameParts = onCall(
  { region: LOCATION, enforceAppCheck: true },
  async (request) => {
    const userId = requireAuth(request);

    // ユーザーのアンロック済みパーツを取得
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    const unlockedParts: string[] = userData?.unlockedNameParts || [];
    const isAI = userData?.isAI || false;
    const isSubscriber = userData?.isSubscriber === true;

    // 全パーツを取得
    const partsSnapshot = await db.collection("nameParts").orderBy("order").get();

    const prefixes: (NamePart & { unlocked: boolean })[] = [];
    const suffixes: (NamePart & { unlocked: boolean })[] = [];

    partsSnapshot.docs.forEach((doc) => {
      const data = doc.data() as NamePart & { type: string };
      const partId = doc.id;

      // ノーマルは最初からアンロック、それ以外はアンロック済みリストに含まれているか確認
      const isUnlocked =
        data.rarity === "common" ||
        unlockedParts.includes(partId) ||
        (isSubscriber && data.rarity === "epic");

      // AIはスーパーレア以上を持てない
      if (isAI && data.rarity === "epic") {
        return;
      }

      const partWithUnlock = {
        ...data,
        id: partId,
        unlocked: isUnlocked,
      };

      if (data.type === "prefix") {
        prefixes.push(partWithUnlock);
      } else {
        suffixes.push(partWithUnlock);
      }
    });

    const prefixIdSet = new Set(prefixes.map((part) => part.id));
    const suffixIdSet = new Set(suffixes.map((part) => part.id));

    const resolvedPrefix = resolveCurrentPartId(userData?.namePrefix, prefixIdSet);
    const resolvedSuffix = resolveCurrentPartId(userData?.nameSuffix, suffixIdSet);

    return {
      prefixes,
      suffixes,
      currentPrefix: resolvedPrefix ?? null,
      currentSuffix: resolvedSuffix ?? null,
    };
  }
);

function resolveCurrentPartId(
  currentId: string | null | undefined,
  candidates: Set<string>
): string | null {
  if (!currentId) return null;
  const trimmed = currentId.trim();
  const checks = new Set<string>([currentId, trimmed]);

  if (trimmed.startsWith("prefix_pre_")) {
    const base = trimmed.replace("prefix_pre_", "");
    checks.add(`prefix_${base}`);
  } else if (trimmed.startsWith("suffix_suf_")) {
    const base = trimmed.replace("suffix_suf_", "");
    checks.add(`suffix_${base}`);
  } else if (trimmed.startsWith("prefix_") && !trimmed.startsWith("prefix_pre_")) {
    const base = trimmed.replace("prefix_", "");
    checks.add(`prefix_pre_${base}`);
    checks.add(`prefix_pre_${base} `);
  } else if (trimmed.startsWith("suffix_") && !trimmed.startsWith("suffix_suf_")) {
    const base = trimmed.replace("suffix_", "");
    checks.add(`suffix_suf_${base}`);
    checks.add(`suffix_suf_${base} `);
  }

  for (const id of checks) {
    if (candidates.has(id)) return id;
  }
  return null;
}

/**
 * ユーザー名を更新する関数
 */
export const updateUserName = onCall(
  { region: LOCATION, enforceAppCheck: true },
  async (request) => {
    const userId = requireAuth(request);
    const { prefixId, suffixId } = request.data;

    if (!prefixId || !suffixId) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.PARTS_ID_REQUIRED);
    }

    // ユーザー情報を取得
    const userRef = db.collection("users").doc(userId);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      throw new HttpsError("not-found", RESOURCE_ERRORS.USER_NOT_FOUND);
    }

    const userData = userDoc.data()!;
    const unlockedParts: string[] = userData.unlockedNameParts || [];
    const isSubscriber = userData.isSubscriber === true;

    // パーツを取得
    const prefixDoc = await db.collection("nameParts").doc(prefixId).get();
    const suffixDoc = await db.collection("nameParts").doc(suffixId).get();

    if (!prefixDoc.exists || !suffixDoc.exists) {
      throw new HttpsError("not-found", RESOURCE_ERRORS.PARTS_NOT_FOUND);
    }

    const prefixData = prefixDoc.data() as NamePart;
    const suffixData = suffixDoc.data() as NamePart;

    // アンロック済みか確認（ノーマルは最初からOK）
    const prefixUnlocked =
      prefixData.rarity === "common" ||
      unlockedParts.includes(prefixId) ||
      (isSubscriber && prefixData.rarity === "epic");
    const suffixUnlocked =
      suffixData.rarity === "common" ||
      unlockedParts.includes(suffixId) ||
      (isSubscriber && suffixData.rarity === "epic");

    if (!prefixUnlocked || !suffixUnlocked) {
      throw new HttpsError("permission-denied", PERMISSION_ERRORS.PARTS_NOT_UNLOCKED);
    }

    // 新しい表示名を生成
    const newDisplayName = `${prefixData.text}${suffixData.text} `;

    // 更新
    await userRef.update({
      namePrefix: prefixId,
      nameSuffix: suffixId,
      displayName: newDisplayName,
      lastNameChangeAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    console.log(`User ${userId} changed name to: ${newDisplayName} `);

    return {
      success: true,
      displayName: newDisplayName,
      message: SUCCESS_MESSAGES.nameChanged(newDisplayName),
    };
  }
);
