import { onDocumentCreated, onDocumentDeleted, onDocumentUpdated } from "firebase-functions/v2/firestore";

import { db, FieldValue } from "../helpers/firebase";
import { LOCATION } from "../config/constants";
import { buildPublicUserData } from "../helpers/public-users";
import { COLLECTIONS } from "../config/collections";

const SUBSCRIPTION_FALLBACK_DOC_ID = "subscriptionFallback";
const DEFAULT_SUBSCRIPTION_FALLBACK = {
  namePrefix: "prefix_01",
  nameSuffix: "suffix_01",
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

async function getNamePartRarity(partId: string | null): Promise<string | null> {
  if (!partId) return null;
  const doc = await db.collection(COLLECTIONS.NAME_PARTS).doc(partId).get();
  if (!doc.exists) return null;
  const rarity = (doc.data()?.rarity as string) || null;
  return rarity;
}

async function applySubscriptionFallbackIfNeeded(
  userId: string,
  data: Record<string, unknown>
): Promise<boolean> {
  const namePrefix = toStringOrNull(data.namePrefix);
  const nameSuffix = toStringOrNull(data.nameSuffix);
  const avatarParts = (data.avatarParts ?? {}) as Record<string, unknown>;

  const [prefixRarity, suffixRarity] = await Promise.all([
    getNamePartRarity(namePrefix),
    getNamePartRarity(nameSuffix),
  ]);

  const fallback = await loadSubscriptionFallback();
  const updates: Record<string, unknown> = {};

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

  if (Object.keys(updates).length === 0) {
    return false;
  }

  updates.updatedAt = FieldValue.serverTimestamp();
  await db.collection(COLLECTIONS.USERS).doc(userId).update(updates);
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

    const wasSubscriber = beforeData.isSubscriber === true;
    const isSubscriber = afterData.isSubscriber === true;

    if (wasSubscriber && !isSubscriber) {
      const applied = await applySubscriptionFallbackIfNeeded(userId, afterData);
      if (applied) {
        return;
      }
    }

    const publicData = buildPublicUserData(afterData);
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
