/**
 * 名前パーツ関連のCallable Functions
 * - initializeNameParts: 名前パーツマスタを初期化（管理者用）
 * - getNameParts: 名前パーツ一覧を取得
 * - updateUserName: ユーザー名を更新
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db, FieldValue } from "../helpers/firebase";
import { isAdmin } from "../helpers/admin";
import { NamePart, PREFIX_PARTS, SUFFIX_PARTS } from "../ai/personas";
import { LOCATION } from "../config/constants";
import {
  AUTH_ERRORS,
  RESOURCE_ERRORS,
  VALIDATION_ERRORS,
  PERMISSION_ERRORS,
  SUCCESS_MESSAGES,
} from "../config/messages";

/**
 * 名前パーツマスタを初期化する関数（管理者用）
 */
export const initializeNameParts = onCall(
  { region: LOCATION },
  async (request) => {
    // セキュリティ: 管理者権限チェック
    if (!request.auth) {
      throw new HttpsError("unauthenticated", AUTH_ERRORS.UNAUTHENTICATED);
    }
    const userIsAdmin = await isAdmin(request.auth.uid);
    if (!userIsAdmin) {
      throw new HttpsError("permission-denied", AUTH_ERRORS.ADMIN_REQUIRED);
    }

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
  { region: LOCATION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", AUTH_ERRORS.UNAUTHENTICATED);
    }

    const userId = request.auth.uid;

    // ユーザーのアンロック済みパーツを取得
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    const unlockedParts: string[] = userData?.unlockedNameParts || [];
    const isAI = userData?.isAI || false;

    // 全パーツを取得
    const partsSnapshot = await db.collection("nameParts").orderBy("order").get();

    const prefixes: (NamePart & { unlocked: boolean })[] = [];
    const suffixes: (NamePart & { unlocked: boolean })[] = [];

    partsSnapshot.docs.forEach((doc) => {
      const data = doc.data() as NamePart & { type: string };
      const partId = doc.id;

      // ノーマルは最初からアンロック、それ以外はアンロック済みリストに含まれているか確認
      const isUnlocked = data.rarity === "normal" || unlockedParts.includes(partId);

      // AIはスーパーレア以上を持てない
      if (isAI && (data.rarity === "super_rare" || data.rarity === "ultra_rare")) {
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

    return {
      prefixes,
      suffixes,
      currentPrefix: userData?.namePrefix || null,
      currentSuffix: userData?.nameSuffix || null,
    };
  }
);

/**
 * ユーザー名を更新する関数
 */
export const updateUserName = onCall(
  { region: LOCATION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", AUTH_ERRORS.UNAUTHENTICATED);
    }

    const userId = request.auth.uid;
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

    // パーツを取得
    const prefixDoc = await db.collection("nameParts").doc(prefixId).get();
    const suffixDoc = await db.collection("nameParts").doc(suffixId).get();

    if (!prefixDoc.exists || !suffixDoc.exists) {
      throw new HttpsError("not-found", RESOURCE_ERRORS.PARTS_NOT_FOUND);
    }

    const prefixData = prefixDoc.data() as NamePart;
    const suffixData = suffixDoc.data() as NamePart;

    // アンロック済みか確認（ノーマルは最初からOK）
    const prefixUnlocked = prefixData.rarity === "normal" || unlockedParts.includes(prefixId);
    const suffixUnlocked = suffixData.rarity === "normal" || unlockedParts.includes(suffixId);

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
