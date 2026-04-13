import { onCall, HttpsError } from "firebase-functions/v2/https";

import { db, Timestamp } from "../helpers/firebase";
import { requireAuth } from "../helpers/auth";
import { LOCATION } from "../config/constants";
import { RESOURCE_ERRORS, VALIDATION_ERRORS } from "../config/messages";

const EPIC_REACTIONS = new Set(["rainbow", "hundred", "confetti"]);
const REWARDED_USES = 25;
const REWARDED_HOURS = 24;

function parseExpiresAt(raw: any): Date | null {
    if (!raw) return null;
    if (raw.toDate && typeof raw.toDate === "function") {
        return raw.toDate();
    }
    if (raw instanceof Date) {
        return raw;
    }
    const parsed = new Date(raw);
    if (Number.isNaN(parsed.getTime())) return null;
    return parsed;
}

export const grantRewardedReactionUnlock = onCall(
    { region: LOCATION, enforceAppCheck: true },
    async (request) => {
        const userId = requireAuth(request);
        const { reactionType } = request.data ?? {};

        if (!reactionType || !EPIC_REACTIONS.has(reactionType)) {
            throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
        }

        const userRef = db.collection("users").doc(userId);
        const now = new Date();
        const expiresAt = new Date(now.getTime() + REWARDED_HOURS * 60 * 60 * 1000);

        const result = await db.runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new HttpsError("not-found", RESOURCE_ERRORS.USER_NOT_FOUND);
            }

            const data = userDoc.data() || {};
            if (data.isSubscriber === true) {
                return { remaining: REWARDED_USES, expiresAt };
            }

            const unlocks = data.rewardedReactionUnlocks || {};
            const current = unlocks[reactionType];

            let remaining = REWARDED_USES;
            let nextExpiresAt = expiresAt;

            if (current) {
                const currentRemaining = Number(current.remaining ?? 0);
                const currentExpiresAt = parseExpiresAt(current.expiresAt);
                if (currentExpiresAt && currentExpiresAt.getTime() > now.getTime()) {
                    remaining = currentRemaining + REWARDED_USES;
                    nextExpiresAt = currentExpiresAt;
                }
            }

            transaction.update(userRef, {
                [`rewardedReactionUnlocks.${reactionType}`]: {
                    remaining,
                    expiresAt: Timestamp.fromDate(nextExpiresAt),
                },
            });

            return { remaining, expiresAt: nextExpiresAt };
        });

        return {
            success: true,
            remaining: result.remaining,
            expiresAt: result.expiresAt,
        };
    }
);
