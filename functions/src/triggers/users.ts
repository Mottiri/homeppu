import { onDocumentCreated, onDocumentDeleted, onDocumentUpdated } from "firebase-functions/v2/firestore";

import { db, FieldValue, storage } from "../helpers/firebase";
import { LOCATION } from "../config/constants";
import { buildPublicUserData } from "../helpers/public-users";
import { COLLECTIONS } from "../config/collections";
import { deleteStorageFileFromUrl } from "../helpers/storage";

const SUBSCRIPTION_FALLBACK_DOC_ID = "subscriptionFallback";
const DEFAULT_SUBSCRIPTION_FALLBACK = {
  namePrefix: "prefix_01",
  nameSuffix: "suffix_01",
  stampSheetId: "spring",
  avatarParts: {
    hairId: "hair_01",
    eyesId: "eyes_01",
    mouthId: "mouth_01",
    eyebrowsId: "eyebrows_01",
  },
};

const AVATAR_PART_RARITY: Record<string, string> = {
  hair_01: "common",
  hair_02: "common",
  hair_03: "epic",
  hair_04: "rare",
  eyebrows_01: "common",
  eyebrows_02: "common",
  eyebrows_03: "common",
  eyebrows_04: "epic",
  eyebrows_05: "rare",
  eyebrows_06: "rare",
  eyes_01: "common",
  eyes_02: "common",
  eyes_03: "epic",
  eyes_04: "rare",
  eyes_05: "rare",
  mouth_01: "common",
  mouth_02: "common",
  mouth_03: "epic",
  mouth_04: "rare",
  mouth_05: "rare",
};

type SubscriptionFallbackConfig = typeof DEFAULT_SUBSCRIPTION_FALLBACK;

function toStringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

async function loadSubscriptionFallback(): Promise<SubscriptionFallbackConfig> {
  const doc = await db
    .collection(COLLECTIONS.SETTINGS)
    .doc(SUBSCRIPTION_FALLBACK_DOC_ID)
    .get();

  if (!doc.exists) {
    return DEFAULT_SUBSCRIPTION_FALLBACK;
  }

  const data = doc.data() as Record<string, unknown>;
  const avatarParts = (data.avatarParts ?? {}) as Record<string, unknown>;

  return {
    namePrefix: toStringOrNull(data.namePrefix) ?? DEFAULT_SUBSCRIPTION_FALLBACK.namePrefix,
    nameSuffix: toStringOrNull(data.nameSuffix) ?? DEFAULT_SUBSCRIPTION_FALLBACK.nameSuffix,
    stampSheetId: toStringOrNull(data.stampSheetId) ?? DEFAULT_SUBSCRIPTION_FALLBACK.stampSheetId,
    avatarParts: {
      hairId:
        toStringOrNull(avatarParts.hairId) ?? DEFAULT_SUBSCRIPTION_FALLBACK.avatarParts.hairId,
      eyesId:
        toStringOrNull(avatarParts.eyesId) ?? DEFAULT_SUBSCRIPTION_FALLBACK.avatarParts.eyesId,
      mouthId:
        toStringOrNull(avatarParts.mouthId) ?? DEFAULT_SUBSCRIPTION_FALLBACK.avatarParts.mouthId,
      eyebrowsId:
        toStringOrNull(avatarParts.eyebrowsId) ??
        DEFAULT_SUBSCRIPTION_FALLBACK.avatarParts.eyebrowsId,
    },
  };
}

function parseStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
}

function normalizeRarity(value: unknown): "common" | "rare" | "epic" {
  if (value === "rare" || value === "epic") return value;
  return "common";
}

function isStampSheetUsableForNonSubscriber(
  sheetId: string,
  rarityById: Map<string, "common" | "rare" | "epic">,
  unlocked: Set<string>
): boolean {
  const rarity = rarityById.get(sheetId);
  if (!rarity) return false;
  if (rarity === "common") return true;
  if (rarity === "rare") return unlocked.has(`sheet_${sheetId}`);
  return false;
}

async function resolveStampSheetFallbackId(
  preferredSheetId: string,
  unlockedSheetKeys: Set<string>
): Promise<string | null> {
  const catalogDoc = await db.collection(COLLECTIONS.SETTINGS).doc("stampSheetCatalog").get();
  if (!catalogDoc.exists) {
    return preferredSheetId || "default";
  }

  const sheetsRaw = catalogDoc.data()?.sheets;
  const sheets = Array.isArray(sheetsRaw) ? sheetsRaw : [];
  const rarityById = new Map<string, "common" | "rare" | "epic">();
  const activeSheetIds: string[] = [];

  for (const raw of sheets) {
    if (!raw || typeof raw !== "object") continue;
    const map = raw as Record<string, unknown>;
    if (map.isActive === false) continue;
    const id = toStringOrNull(map.id);
    if (!id) continue;
    rarityById.set(id, normalizeRarity(map.rarity));
    activeSheetIds.push(id);
  }

  const candidates = [preferredSheetId, "default"];
  for (const candidate of candidates) {
    if (!candidate) continue;
    if (isStampSheetUsableForNonSubscriber(candidate, rarityById, unlockedSheetKeys)) {
      return candidate;
    }
  }

  for (const sheetId of activeSheetIds) {
    if (isStampSheetUsableForNonSubscriber(sheetId, rarityById, unlockedSheetKeys)) {
      return sheetId;
    }
  }

  return null;
}

function buildNamePartIdCandidates(partId: string): string[] {
  const trimmed = partId.trim();
  const candidates = new Set<string>([partId, trimmed]);

  if (trimmed.startsWith("prefix_pre_")) {
    const base = trimmed.replace("prefix_pre_", "");
    candidates.add(`prefix_${base}`);
  } else if (trimmed.startsWith("suffix_suf_")) {
    const base = trimmed.replace("suffix_suf_", "");
    candidates.add(`suffix_${base}`);
  } else if (trimmed.startsWith("prefix_") && !trimmed.startsWith("prefix_pre_")) {
    const base = trimmed.replace("prefix_", "");
    candidates.add(`prefix_pre_${base}`);
    candidates.add(`prefix_pre_${base} `);
  } else if (trimmed.startsWith("suffix_") && !trimmed.startsWith("suffix_suf_")) {
    const base = trimmed.replace("suffix_", "");
    candidates.add(`suffix_suf_${base}`);
    candidates.add(`suffix_suf_${base} `);
  }

  return Array.from(candidates);
}

async function getNamePartDoc(partId: string | null) {
  if (!partId) return null;
  for (const candidate of buildNamePartIdCandidates(partId)) {
    const doc = await db.collection(COLLECTIONS.NAME_PARTS).doc(candidate).get();
    if (doc.exists) {
      return doc;
    }
  }
  return null;
}

async function getNamePartRarity(partId: string | null): Promise<string | null> {
  const doc = await getNamePartDoc(partId);
  if (!doc) return null;
  const rarity = (doc.data()?.rarity as string) || null;
  return rarity;
}

async function getNamePartText(partId: string | null): Promise<string | null> {
  const doc = await getNamePartDoc(partId);
  if (!doc) return null;
  const text = (doc.data()?.text as string) || null;
  return text;
}

async function applySubscriptionFallbackIfNeeded(
  userId: string,
  data: Record<string, unknown>,
  options?: {
    forceStampSheetFallback?: boolean;
  }
): Promise<boolean> {
  const namePrefix = toStringOrNull(data.namePrefix);
  const nameSuffix = toStringOrNull(data.nameSuffix);
  const activeStampSheetId = toStringOrNull(data.activeStampSheetId);
  const avatarParts = (data.avatarParts ?? {}) as Record<string, unknown>;

  const [prefixRarity, suffixRarity] = await Promise.all([
    getNamePartRarity(namePrefix),
    getNamePartRarity(nameSuffix),
  ]);

  const fallback = await loadSubscriptionFallback();
  const updates: Record<string, unknown> = {};
  const forceStampSheetFallback = options?.forceStampSheetFallback === true;

  if (prefixRarity === "epic") {
    updates.namePrefix = fallback.namePrefix;
  }
  if (suffixRarity === "epic") {
    updates.nameSuffix = fallback.nameSuffix;
  }

  const currentAvatarParts: Record<string, string> = {};
  const hair = toStringOrNull(avatarParts.hairId);
  const eyes = toStringOrNull(avatarParts.eyesId);
  const mouth = toStringOrNull(avatarParts.mouthId);
  const eyebrows = toStringOrNull(avatarParts.eyebrowsId);
  if (hair) currentAvatarParts.hairId = hair;
  if (eyes) currentAvatarParts.eyesId = eyes;
  if (mouth) currentAvatarParts.mouthId = mouth;
  if (eyebrows) currentAvatarParts.eyebrowsId = eyebrows;

  const avatarUpdates: Record<string, string> = {};
  if (hair && AVATAR_PART_RARITY[hair] === "epic") {
    avatarUpdates.hairId = fallback.avatarParts.hairId;
  }
  if (eyes && AVATAR_PART_RARITY[eyes] === "epic") {
    avatarUpdates.eyesId = fallback.avatarParts.eyesId;
  }
  if (mouth && AVATAR_PART_RARITY[mouth] === "epic") {
    avatarUpdates.mouthId = fallback.avatarParts.mouthId;
  }
  if (eyebrows && AVATAR_PART_RARITY[eyebrows] === "epic") {
    avatarUpdates.eyebrowsId = fallback.avatarParts.eyebrowsId;
  }

  if (Object.keys(avatarUpdates).length > 0) {
    updates.avatarParts = { ...currentAvatarParts, ...avatarUpdates };
  }

  if (forceStampSheetFallback) {
    const unlockedSheetKeys = new Set(parseStringArray(data.unlockedStampSheets));
    const fallbackSheetId = await resolveStampSheetFallbackId(
      fallback.stampSheetId,
      unlockedSheetKeys
    );
    if (fallbackSheetId && fallbackSheetId !== activeStampSheetId) {
      updates.activeStampSheetId = fallbackSheetId;

      // サブスク解除による強制切替で旧シートが見えなくなるため、
      // 旧アクティブシートに押されていたスタンプ分のクレジットを返却する。
      if (activeStampSheetId) {
        const oldSheetStampSnap = await db
          .collection(COLLECTIONS.USERS)
          .doc(userId)
          .collection("stampSheet")
          .where("sheetId", "==", activeStampSheetId)
          .get();

        const refundCount = oldSheetStampSnap.size;
        if (refundCount > 0) {
          updates.thanksStampCredits = FieldValue.increment(refundCount);
          updates.stampSheetVersion = FieldValue.increment(1);
        }
      }
    }
  }

  if (Object.keys(updates).length === 0) {
    return false;
  }

  const nextPrefixId = (updates.namePrefix as string | undefined) ?? namePrefix ?? null;
  const nextSuffixId = (updates.nameSuffix as string | undefined) ?? nameSuffix ?? null;
  if (nextPrefixId && nextSuffixId) {
    const [prefixText, suffixText] = await Promise.all([
      getNamePartText(nextPrefixId),
      getNamePartText(nextSuffixId),
    ]);
    if (prefixText && suffixText) {
      updates.displayName = `${prefixText}${suffixText}`;
    }
  }

  const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
  updates.updatedAt = FieldValue.serverTimestamp();
  await userRef.update(updates);

  // 返却対象がある場合は旧シートの押印データを削除して二重取得を防ぐ
  // （解除後に再加入しても同じ押印でクレジットを重複取得させない）
  if (Object.prototype.hasOwnProperty.call(updates, "thanksStampCredits") && activeStampSheetId) {
    const oldSheetStampSnap = await userRef
      .collection("stampSheet")
      .where("sheetId", "==", activeStampSheetId)
      .get();
    if (!oldSheetStampSnap.empty) {
      const batch = db.batch();
      for (const doc of oldSheetStampSnap.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
    }
  }
  return true;
}

function toProfileVisualMode(value: unknown): "icon" | "avatar" | "image" {
  return value === "avatar" || value === "image" ? value : "icon";
}

async function deleteProfileImageIfExists(
  profileImageStoragePath: string | null,
  profileImageUrl: string | null
) {
  try {
    if (profileImageStoragePath) {
      await storage.bucket().file(profileImageStoragePath).delete();
      return;
    }
    if (profileImageUrl) {
      await deleteStorageFileFromUrl(profileImageUrl);
    }
  } catch (error) {
    console.warn("Failed to delete profile image:", error);
  }
}

async function applyProfileImageSubscriptionFallbackIfNeeded(
  userId: string,
  beforeData: Record<string, unknown>,
  afterData: Record<string, unknown>,
  isSubscriber: boolean
): Promise<boolean> {
  if (isSubscriber) return false;

  const mode = toProfileVisualMode(afterData.profileVisualMode);
  const profileImageUrl = toStringOrNull(afterData.profileImageUrl);
  const profileImageStoragePath = toStringOrNull(afterData.profileImageStoragePath);

  if (mode !== "image" && !profileImageUrl && !profileImageStoragePath) {
    return false;
  }

  const beforeStoragePath = toStringOrNull(beforeData.profileImageStoragePath);
  const beforeImageUrl = toStringOrNull(beforeData.profileImageUrl);
  const deleteStoragePath = profileImageStoragePath ?? beforeStoragePath;
  const deleteImageUrl = profileImageUrl ?? beforeImageUrl;

  await deleteProfileImageIfExists(deleteStoragePath, deleteImageUrl);

  await db.collection(COLLECTIONS.USERS).doc(userId).update({
    profileVisualMode: "icon",
    profileImageUrl: FieldValue.delete(),
    profileImageStoragePath: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return true;
}

async function applyHeaderImageSubscriptionFallbackIfNeeded(
  userId: string,
  afterData: Record<string, unknown>,
  isSubscriber: boolean
): Promise<boolean> {
  if (isSubscriber) return false;

  const headerImageUrl = toStringOrNull(afterData.headerImageUrl);
  if (!headerImageUrl) return false;

  try {
    await deleteStorageFileFromUrl(headerImageUrl);
  } catch (error) {
    console.warn("Failed to delete header image:", error);
  }

  await db.collection(COLLECTIONS.USERS).doc(userId).update({
    headerImageUrl: FieldValue.delete(),
    headerPrimaryColor: FieldValue.delete(),
    headerSecondaryColor: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return true;
}

export const onUserCreated = onDocumentCreated(
  {
    document: "users/{userId}",
    region: LOCATION,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const userId = event.params.userId;
    const data = snap.data() as Record<string, unknown>;
    const publicData = buildPublicUserData(data);

    await db.collection("publicUsers").doc(userId).set(publicData, { merge: true });
  }
);

export const onUserUpdated = onDocumentUpdated(
  {
    document: "users/{userId}",
    region: LOCATION,
  },
  async (event) => {
    const afterSnap = event.data?.after;
    const beforeSnap = event.data?.before;
    if (!afterSnap || !beforeSnap) return;

    const userId = event.params.userId;
    const afterData = afterSnap.data() as Record<string, unknown>;
    const beforeData = beforeSnap.data() as Record<string, unknown>;

    const isSubscriber = afterData.isSubscriber === true;
    const wasSubscriber = beforeData.isSubscriber === true;

    let publicSource = afterData;
    let requiresRefresh = false;

    if (wasSubscriber && !isSubscriber) {
      // 購読→非購読への遷移時のみフォールバック処理を実行
      // 元々非購読者やcallable-404による更新では画像削除しない
      const appliedSubscriptionFallback = await applySubscriptionFallbackIfNeeded(userId, afterData, {
        forceStampSheetFallback: true,
      });
      const appliedProfileImageFallback = await applyProfileImageSubscriptionFallbackIfNeeded(
        userId,
        beforeData,
        afterData,
        isSubscriber
      );
      const appliedHeaderImageFallback = await applyHeaderImageSubscriptionFallbackIfNeeded(
        userId,
        afterData,
        isSubscriber
      );
      requiresRefresh = appliedSubscriptionFallback || appliedProfileImageFallback || appliedHeaderImageFallback;
    }

    if (requiresRefresh) {
      const refreshed = await db.collection(COLLECTIONS.USERS).doc(userId).get();
      if (refreshed.exists) {
        publicSource = refreshed.data() as Record<string, unknown>;
      }
    }

    const publicData = buildPublicUserData(publicSource);
    await db.collection("publicUsers").doc(userId).set(publicData, { merge: true });
  }
);

export const onUserDeleted = onDocumentDeleted(
  {
    document: "users/{userId}",
    region: LOCATION,
  },
  async (event) => {
    const userId = event.params.userId;
    await db.collection("publicUsers").doc(userId).delete();
  }
);
