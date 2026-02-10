import { db, FieldValue } from "./firebase";

const SETTINGS_COLLECTION = "settings";
const VIRTUE_POLICY_DOC_ID = "virtuePolicy";
const POLICY_CACHE_TTL_MS = 60_000;
const JST_OFFSET_MS = 9 * 60 * 60 * 1000;

export const VIRTUE_ROUTE_KEYS = {
    postCreate: "post_create",
    reactionGiven: "reaction_given",
    reactionReceived: "reaction_received",
    goalComplete: "goal_complete",
    taskStreak: "task_streak",
} as const;

type VirtueRouteKey = typeof VIRTUE_ROUTE_KEYS[keyof typeof VIRTUE_ROUTE_KEYS];

export type VirtuePolicy = {
    postCreatePoints: number;
    postCreateDailyCap: number;
    reactionGivenPoints: number;
    reactionGivenDailyCap: number;
    reactionReceivedPoints: number;
    reactionReceivedDailyCap: number;
    goalCompletePoints: number;
    goalCompleteDailyCap: number;
    streak3Points: number;
    streak7Points: number;
    streak14Points: number;
    streak30Points: number;
    adminDeletePenaltyPoints: number;
};

const DEFAULT_VIRTUE_POLICY: VirtuePolicy = {
    postCreatePoints: 3,
    postCreateDailyCap: 30,
    reactionGivenPoints: 1,
    reactionGivenDailyCap: 10,
    reactionReceivedPoints: 1,
    reactionReceivedDailyCap: 20,
    goalCompletePoints: 8,
    goalCompleteDailyCap: 16,
    streak3Points: 10,
    streak7Points: 20,
    streak14Points: 30,
    streak30Points: 60,
    adminDeletePenaltyPoints: 10,
};

let cachedPolicy: VirtuePolicy | null = null;
let cachedAt = 0;

function toNonNegativeInt(value: unknown, fallback: number): number {
    if (typeof value !== "number" || !Number.isFinite(value)) {
        return fallback;
    }
    return Math.max(0, Math.trunc(value));
}

function toVirtuePolicy(data: Record<string, unknown> | undefined): VirtuePolicy {
    return {
        postCreatePoints: toNonNegativeInt(data?.postCreatePoints, DEFAULT_VIRTUE_POLICY.postCreatePoints),
        postCreateDailyCap: toNonNegativeInt(data?.postCreateDailyCap, DEFAULT_VIRTUE_POLICY.postCreateDailyCap),
        reactionGivenPoints: toNonNegativeInt(data?.reactionGivenPoints, DEFAULT_VIRTUE_POLICY.reactionGivenPoints),
        reactionGivenDailyCap: toNonNegativeInt(data?.reactionGivenDailyCap, DEFAULT_VIRTUE_POLICY.reactionGivenDailyCap),
        reactionReceivedPoints: toNonNegativeInt(data?.reactionReceivedPoints, DEFAULT_VIRTUE_POLICY.reactionReceivedPoints),
        reactionReceivedDailyCap: toNonNegativeInt(data?.reactionReceivedDailyCap, DEFAULT_VIRTUE_POLICY.reactionReceivedDailyCap),
        goalCompletePoints: toNonNegativeInt(data?.goalCompletePoints, DEFAULT_VIRTUE_POLICY.goalCompletePoints),
        goalCompleteDailyCap: toNonNegativeInt(data?.goalCompleteDailyCap, DEFAULT_VIRTUE_POLICY.goalCompleteDailyCap),
        streak3Points: toNonNegativeInt(data?.streak3Points, DEFAULT_VIRTUE_POLICY.streak3Points),
        streak7Points: toNonNegativeInt(data?.streak7Points, DEFAULT_VIRTUE_POLICY.streak7Points),
        streak14Points: toNonNegativeInt(data?.streak14Points, DEFAULT_VIRTUE_POLICY.streak14Points),
        streak30Points: toNonNegativeInt(data?.streak30Points, DEFAULT_VIRTUE_POLICY.streak30Points),
        adminDeletePenaltyPoints: toNonNegativeInt(
            data?.adminDeletePenaltyPoints,
            DEFAULT_VIRTUE_POLICY.adminDeletePenaltyPoints
        ),
    };
}

function getJstDateKey(now: Date): string {
    const jstNow = new Date(now.getTime() + JST_OFFSET_MS);
    return jstNow.toISOString().slice(0, 10);
}

export async function getVirtuePolicy(forceRefresh = false): Promise<VirtuePolicy> {
    const nowMs = Date.now();
    if (!forceRefresh && cachedPolicy && nowMs - cachedAt <= POLICY_CACHE_TTL_MS) {
        return cachedPolicy;
    }

    const doc = await db.collection(SETTINGS_COLLECTION).doc(VIRTUE_POLICY_DOC_ID).get();
    cachedPolicy = toVirtuePolicy(doc.data() as Record<string, unknown> | undefined);
    cachedAt = nowMs;
    return cachedPolicy;
}

export function resolveTaskStreakRewardPoints(policy: VirtuePolicy, streak: number): number {
    if (streak === 3) return policy.streak3Points;
    if (streak === 7) return policy.streak7Points;
    if (streak === 14) return policy.streak14Points;
    if (streak === 30) return policy.streak30Points;
    return 0;
}

type GrantVirtueParams = {
    userId: string;
    routeKey: VirtueRouteKey;
    points: number;
    reason: string;
    source: string;
    targetId?: string;
    dailyCap?: number;
    now?: Date;
};

export async function grantVirtue(params: GrantVirtueParams): Promise<{ granted: number; newVirtue?: number }> {
    const requestedPoints = Math.max(0, Math.trunc(params.points));
    if (requestedPoints <= 0) {
        return { granted: 0 };
    }

    const now = params.now ?? new Date();
    const nowTimestamp = FieldValue.serverTimestamp();
    const userRef = db.collection("users").doc(params.userId);
    const historyRef = db.collection("virtueHistory").doc();
    const hasDailyCap = typeof params.dailyCap === "number" && Number.isFinite(params.dailyCap);
    const normalizedDailyCap = hasDailyCap ? Math.max(0, Math.trunc(params.dailyCap as number)) : undefined;

    return db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        if (!userDoc.exists) {
            throw new Error("user not found");
        }

        let granted = requestedPoints;
        let dailyRef: FirebaseFirestore.DocumentReference | null = null;
        let nextRouteTotal = 0;
        let usedToday = 0;

        if (hasDailyCap && normalizedDailyCap !== undefined) {
            const dateKey = getJstDateKey(now);
            dailyRef = userRef.collection("virtueDaily").doc(dateKey);
            const dailyDoc = await transaction.get(dailyRef);
            usedToday = Number(
                (dailyDoc.data()?.routePoints as Record<string, unknown> | undefined)?.[params.routeKey] ?? 0
            );
            const safeUsedToday = Number.isFinite(usedToday) ? Math.max(0, Math.trunc(usedToday)) : 0;
            const remaining = Math.max(0, normalizedDailyCap - safeUsedToday);
            granted = Math.min(requestedPoints, remaining);
            nextRouteTotal = safeUsedToday + granted;
        }

        if (granted <= 0) {
            return { granted: 0 };
        }

        const currentVirtueRaw = Number(userDoc.data()?.virtue ?? 100);
        const currentVirtue = Number.isFinite(currentVirtueRaw) ? currentVirtueRaw : 100;
        const newVirtue = currentVirtue + granted;

        transaction.update(userRef, {
            virtue: newVirtue,
            updatedAt: nowTimestamp,
        });

        if (dailyRef) {
            transaction.set(dailyRef, {
                dateKey: dailyRef.id,
                routePoints: {
                    [params.routeKey]: nextRouteTotal,
                },
                updatedAt: nowTimestamp,
                createdAt: nowTimestamp,
            }, { merge: true });
        }

        transaction.set(historyRef, {
            userId: params.userId,
            change: granted,
            reason: params.reason,
            source: params.source,
            routeKey: params.routeKey,
            targetId: params.targetId ?? null,
            newVirtue,
            createdAt: nowTimestamp,
        });

        return { granted, newVirtue };
    });
}

