/**
 * Virtue shop callable functions
 * - getVirtueShopConfig: price config for virtue items
 * - purchaseVirtueItem: spend virtue to unlock items
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";
import { db, FieldValue } from "../helpers/firebase";
import { requireAuth } from "../helpers/auth";
import { COLLECTIONS } from "../config/collections";
import { LOCATION } from "../config/constants";
import { VIRTUE_MESSAGES } from "../config/messages";
import { AVATAR_PART_RARITY } from "../config/avatar-parts";

type VirtueShopConfig = {
    namePartCostsByRarity: Record<string, number>;
    avatarPartCostsByRarity: Record<string, number>;
    reactionCostsById: Record<string, number>;
    stampSheetCostsByRarity: Record<string, number>;
    nonPurchasableItems: Set<string>;
};

const SETTINGS_DOC_ID = "virtueShop";

function toNumberMap(value: unknown): Record<string, number> {
    if (!value || typeof value !== "object") return {};
    const result: Record<string, number> = {};
    for (const [key, raw] of Object.entries(value as Record<string, unknown>)) {
        if (typeof raw === "number" && Number.isFinite(raw)) {
            result[key] = Math.trunc(raw);
        }
    }
    return result;
}

const VALID_ITEM_TYPES = new Set(["name_part", "avatar_part", "reaction_stamp", "stamp_sheet"]);

function readNonPurchasableItems(value: unknown): Set<string> {
    if (!value || typeof value !== "object") return new Set();
    const result = new Set<string>();
    for (const [key, flag] of Object.entries(value as Record<string, unknown>)) {
        if (flag !== true) continue;
        const sepIndex = key.indexOf(":");
        if (sepIndex <= 0 || sepIndex === key.length - 1) continue;
        if (sepIndex !== key.lastIndexOf(":")) continue;
        const itemType = key.slice(0, sepIndex);
        if (!VALID_ITEM_TYPES.has(itemType)) continue;
        result.add(key);
    }
    return result;
}

function toNonPurchasableKey(itemType: string, itemId: string): string {
    return `${itemType}:${itemId}`;
}

function readVirtueShopConfig(data: Record<string, unknown> | undefined): VirtueShopConfig {
    const namePartCostsByRarity = toNumberMap(data?.namePartCostsByRarity);
    const avatarPartCostsByRarity = Object.keys(
        toNumberMap(data?.avatarPartCostsByRarity)
    ).length
        ? toNumberMap(data?.avatarPartCostsByRarity)
        : namePartCostsByRarity;
    const reactionCostsById = toNumberMap(data?.reactionCostsById);
    const stampSheetCostsByRarity = Object.keys(
        toNumberMap(data?.stampSheetCostsByRarity)
    ).length
        ? toNumberMap(data?.stampSheetCostsByRarity)
        : namePartCostsByRarity;
    const nonPurchasableItems = readNonPurchasableItems(data?.nonPurchasableItems);
    return {
        namePartCostsByRarity,
        avatarPartCostsByRarity,
        reactionCostsById,
        stampSheetCostsByRarity,
        nonPurchasableItems,
    };
}

export const getVirtueShopConfig = onCall(
  { region: LOCATION, enforceAppCheck: true },
  async (request) => {
        requireAuth(request);

        const doc = await db.collection(COLLECTIONS.SETTINGS).doc(SETTINGS_DOC_ID).get();
        if (!doc.exists) {
            throw new HttpsError("failed-precondition", "Virtue shop config not found");
        }
        const config = readVirtueShopConfig(doc.data() as Record<string, unknown>);
        return {
            namePartCostsByRarity: config.namePartCostsByRarity,
            avatarPartCostsByRarity: config.avatarPartCostsByRarity,
            reactionCostsById: config.reactionCostsById,
            stampSheetCostsByRarity: config.stampSheetCostsByRarity,
            nonPurchasableItems: Array.from(config.nonPurchasableItems),
        };
    }
);

export const purchaseVirtueItem = onCall(
  { region: LOCATION, enforceAppCheck: true },
  async (request) => {
        const userId = requireAuth(request);
        const { itemType, itemId } = request.data || {};
        logger.info("purchaseVirtueItem request", {
            userId,
            itemType,
            itemId,
        });

        if (!itemType || !itemId) {
            throw new HttpsError("invalid-argument", "itemType and itemId are required");
        }

        if (
            itemType !== "name_part" &&
            itemType !== "reaction_stamp" &&
            itemType !== "avatar_part" &&
            itemType !== "stamp_sheet"
        ) {
            throw new HttpsError("invalid-argument", "invalid itemType");
        }

        const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
        const settingsRef = db.collection(COLLECTIONS.SETTINGS).doc(SETTINGS_DOC_ID);

        return await db.runTransaction(async (transaction) => {
            const userSnap = await transaction.get(userRef);
            if (!userSnap.exists) {
                throw new HttpsError("not-found", "user not found");
            }

            const settingsSnap = await transaction.get(settingsRef);
            if (!settingsSnap.exists) {
                throw new HttpsError("failed-precondition", "Virtue shop config not found");
            }

            const config = readVirtueShopConfig(settingsSnap.data() as Record<string, unknown>);
            const userData = userSnap.data() || {};

            let cost = 0;
            let unlockField:
                "unlockedNameParts" |
                "unlockedReactionStamps" |
                "unlockedAvatarParts" |
                "unlockedStampSheets";
            let unlockValue = "";
            let purchaseKey = "";

            if (itemType === "name_part") {
                const partRef = db.collection(COLLECTIONS.NAME_PARTS).doc(itemId);
                const partSnap = await transaction.get(partRef);
                if (!partSnap.exists) {
                    throw new HttpsError("not-found", "name part not found");
                }

                const rarity = (partSnap.data()?.rarity as string) || "common";
                cost = config.namePartCostsByRarity[rarity] ?? 0;
                if (!cost || cost <= 0) {
                    throw new HttpsError("failed-precondition", "Cost not configured");
                }

                unlockField = "unlockedNameParts";
                unlockValue = partRef.id;
                purchaseKey = `virtue_name_part_${partRef.id}`;
            } else if (itemType === "reaction_stamp") {
                cost = config.reactionCostsById[itemId] ?? 0;
                if (!cost || cost <= 0) {
                    throw new HttpsError("failed-precondition", "Cost not configured");
                }

                unlockField = "unlockedReactionStamps";
                unlockValue = `reaction_${itemId}`;
                purchaseKey = `virtue_reaction_stamp_${itemId}`;
            } else if (itemType === "avatar_part") {
                const rarity = AVATAR_PART_RARITY[itemId] ?? "";
                logger.info("purchaseVirtueItem avatar lookup", {
                    userId,
                    itemId,
                    rarity,
                    knownAvatarPartCount: Object.keys(AVATAR_PART_RARITY).length,
                    avatarCostConfig: config.avatarPartCostsByRarity,
                });
                if (!rarity) {
                    logger.warn("purchaseVirtueItem avatar part not found", {
                        userId,
                        itemId,
                    });
                    throw new HttpsError("not-found", "avatar part not found");
                }
                cost = config.avatarPartCostsByRarity[rarity] ?? 0;
                if (!cost || cost <= 0) {
                    logger.warn("purchaseVirtueItem avatar cost not configured", {
                        userId,
                        itemId,
                        rarity,
                        cost,
                        avatarCostConfig: config.avatarPartCostsByRarity,
                    });
                    throw new HttpsError("failed-precondition", "Cost not configured");
                }

                unlockField = "unlockedAvatarParts";
                unlockValue = itemId;
                purchaseKey = `virtue_avatar_part_${itemId}`;
            } else {
                const catalogRef = db.collection(COLLECTIONS.SETTINGS).doc("stampSheetCatalog");
                const catalogSnap = await transaction.get(catalogRef);
                if (!catalogSnap.exists) {
                    throw new HttpsError("failed-precondition", "stamp sheet catalog not found");
                }

                const sheetsRaw = catalogSnap.data()?.sheets;
                const sheets = Array.isArray(sheetsRaw) ? sheetsRaw : [];
                const targetSheet = sheets.find(
                    (sheet) => sheet?.id === itemId && sheet?.isActive !== false
                );
                if (!targetSheet) {
                    throw new HttpsError("not-found", "stamp sheet not found");
                }

                const rarity = typeof targetSheet.rarity === "string" ? targetSheet.rarity : "common";
                if (rarity === "epic" && userData.isSubscriber !== true) {
                    throw new HttpsError("permission-denied", "epic stamp sheet requires subscription");
                }

                cost = config.stampSheetCostsByRarity[rarity] ?? 0;
                if (!cost || cost <= 0) {
                    throw new HttpsError("failed-precondition", "Cost not configured");
                }

                unlockField = "unlockedStampSheets";
                unlockValue = `sheet_${itemId}`;
                purchaseKey = `virtue_stamp_sheet_${itemId}`;
            }

            const unlockedList: string[] = userData[unlockField] || [];
            if (unlockedList.includes(unlockValue)) {
                return {
                    success: true,
                    alreadyUnlocked: true,
                    virtue: userData.virtue ?? 0,
                };
            }

            const nonPurchasableKey = toNonPurchasableKey(itemType, itemId);
            if (config.nonPurchasableItems.has(nonPurchasableKey)) {
                logger.info("purchaseVirtueItem blocked: non-purchasable", {
                    userId,
                    itemType,
                    itemId,
                    nonPurchasableKey,
                });
                throw new HttpsError(
                    "failed-precondition",
                    VIRTUE_MESSAGES.ITEM_NOT_PURCHASABLE,
                    { reason: "ITEM_NOT_PURCHASABLE" }
                );
            }

            const currentVirtue = userData.virtue ?? 0;
            if (currentVirtue < cost) {
                logger.info("purchaseVirtueItem insufficient virtue", {
                    userId,
                    itemType,
                    itemId,
                    currentVirtue,
                    cost,
                });
                throw new HttpsError("failed-precondition", "徳ポイントが足りません。");
            }

            const newVirtue = currentVirtue - cost;
            const purchaseRef = userRef.collection("purchases").doc(purchaseKey);
            const historyRef = db.collection(COLLECTIONS.VIRTUE_HISTORY).doc();

            transaction.set(
                purchaseRef,
                {
                    itemType,
                    itemId,
                    cost,
                    createdAt: FieldValue.serverTimestamp(),
                    source: "virtue_shop",
                },
                { merge: true }
            );

            transaction.set(historyRef, {
                userId,
                change: -cost,
                reason: "徳ポイント購入",
                newVirtue,
                createdAt: FieldValue.serverTimestamp(),
            });

            transaction.update(userRef, {
                virtue: newVirtue,
                [unlockField]: FieldValue.arrayUnion(unlockValue),
                updatedAt: FieldValue.serverTimestamp(),
            });

            logger.info("purchaseVirtueItem success", {
                userId,
                itemType,
                itemId,
                cost,
                newVirtue,
                unlockField,
                unlockValue,
            });

            return {
                success: true,
                newVirtue,
                cost,
                unlockKey: unlockValue,
            };
        });
    }
);
