/**
 * Virtue shop callable functions
 * - getVirtueShopConfig: price config for virtue items
 * - purchaseVirtueItem: spend virtue to unlock items
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db, FieldValue } from "../helpers/firebase";
import { requireAuth } from "../helpers/auth";
import { COLLECTIONS } from "../config/collections";
import { LOCATION } from "../config/constants";

type VirtueItemType = "name_part" | "reaction_stamp";

type VirtueShopConfig = {
    namePartCostsByRarity: Record<string, number>;
    reactionCostsById: Record<string, number>;
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

function readVirtueShopConfig(data: Record<string, unknown> | undefined): VirtueShopConfig {
    const namePartCostsByRarity = toNumberMap(data?.namePartCostsByRarity);
    const reactionCostsById = toNumberMap(data?.reactionCostsById);
    return { namePartCostsByRarity, reactionCostsById };
}

export const getVirtueShopConfig = onCall(
    { region: LOCATION },
    async (request) => {
        requireAuth(request);

        const doc = await db.collection(COLLECTIONS.SETTINGS).doc(SETTINGS_DOC_ID).get();
        if (!doc.exists) {
            throw new HttpsError("failed-precondition", "Virtue shop config not found");
        }
        const config = readVirtueShopConfig(doc.data() as Record<string, unknown>);
        return {
            namePartCostsByRarity: config.namePartCostsByRarity,
            reactionCostsById: config.reactionCostsById,
        };
    }
);

export const purchaseVirtueItem = onCall(
    { region: LOCATION },
    async (request) => {
        const userId = requireAuth(request);
        const { itemType, itemId } = request.data || {};

        if (!itemType || !itemId) {
            throw new HttpsError("invalid-argument", "itemType and itemId are required");
        }

        if (itemType !== "name_part" && itemType !== "reaction_stamp") {
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
            let unlockField: "unlockedNameParts" | "unlockedReactionStamps";
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
            } else {
                cost = config.reactionCostsById[itemId] ?? 0;
                if (!cost || cost <= 0) {
                    throw new HttpsError("failed-precondition", "Cost not configured");
                }

                unlockField = "unlockedReactionStamps";
                unlockValue = `reaction_${itemId}`;
                purchaseKey = `virtue_reaction_stamp_${itemId}`;
            }

            const unlockedList: string[] = userData[unlockField] || [];
            if (unlockedList.includes(unlockValue)) {
                return {
                    success: true,
                    alreadyUnlocked: true,
                    virtue: userData.virtue ?? 0,
                };
            }

            const currentVirtue = userData.virtue ?? 0;
            if (currentVirtue < cost) {
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

            return {
                success: true,
                newVirtue,
                cost,
                unlockKey: unlockValue,
            };
        });
    }
);
