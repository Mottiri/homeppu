import { onRequest } from "firebase-functions/v2/https";
import * as crypto from "crypto";

import { db, FieldValue } from "../helpers/firebase";
import { LOCATION } from "../config/constants";
import { COLLECTIONS } from "../config/collections";
import { revenueCatWebhookSecret } from "../config/secrets";

type RevenueCatEvent = {
    app_user_id?: string;
    appUserId?: string;
    original_app_user_id?: string;
    aliases?: string[];
    transferred_to?: string[];
    transferred_from?: string[];
    type?: string;
    product_id?: string;
    expiration_at_ms?: number;
    expires_date_ms?: number;
    entitlements?: Record<string, { expires_date_ms?: number }>;
};

function getSignatureHeader(headers: Record<string, string | string[] | undefined>): string | null {
    const candidates = [
        "x-revcat-signature",
        "x-revenuecat-signature",
        "x-revenue-cat-signature",
        "x-signature",
    ];
    for (const key of candidates) {
        const raw = headers[key] ?? headers[key.toLowerCase()];
        if (typeof raw === "string" && raw.trim()) return raw.trim();
        if (Array.isArray(raw) && raw.length > 0) return String(raw[0]).trim();
    }
    return null;
}

function getAuthorizationHeader(headers: Record<string, string | string[] | undefined>): string | null {
    const raw = headers.authorization ?? headers.Authorization;
    if (typeof raw === "string" && raw.trim()) return raw.trim();
    if (Array.isArray(raw) && raw.length > 0) return String(raw[0]).trim();
    return null;
}

function isValidAuthorizationHeader(authHeader: string, secret: string): boolean {
    const trimmed = authHeader.trim();
    return trimmed === secret || trimmed === `Bearer ${secret}`;
}

function isValidSignature(rawBody: Buffer, signature: string, secret: string): boolean {
    const hmac = crypto.createHmac("sha256", secret);
    hmac.update(rawBody);
    const digestHex = hmac.digest("hex");
    const digestBase64 = crypto.createHmac("sha256", secret).update(rawBody).digest("base64");
    return signature === digestHex || signature === digestBase64;
}

function toNumber(value: unknown): number | null {
    if (typeof value === "number" && Number.isFinite(value)) return value;
    if (typeof value === "string") {
        const parsed = Number(value);
        if (Number.isFinite(parsed)) return parsed;
    }
    return null;
}

function resolveSubscriberStatus(event: RevenueCatEvent): boolean | null {
    const nowMs = Date.now();

    // イベント直接のexpiration（単一商品イベント）
    const directExpMs =
        toNumber(event.expiration_at_ms) ??
        toNumber(event.expires_date_ms);

    if (directExpMs != null) {
        return directExpMs > nowMs;
    }

    // entitlements全体を走査し、1つでも有効なら購読中と判定
    // （Callable側 subscription.ts の判定ロジックと統一）
    if (event.entitlements && Object.keys(event.entitlements).length > 0) {
        return Object.values(event.entitlements).some((entitlement) => {
            const exp = toNumber(entitlement?.expires_date_ms);
            if (exp != null) return exp > nowMs;
            // expires_date_msがない = 無期限エンタイトルメント
            return true;
        });
    }

    const type = (event.type || "").toUpperCase();
    const activeTypes = new Set([
        "INITIAL_PURCHASE",
        "RENEWAL",
        "PRODUCT_CHANGE",
        "UNCANCELLATION",
        "NON_RENEWING_PURCHASE",
    ]);
    const inactiveTypes = new Set([
        "CANCELLATION",
        "EXPIRATION",
        "BILLING_ISSUE",
        "SUBSCRIPTION_PAUSED",
    ]);

    if (activeTypes.has(type)) return true;
    if (inactiveTypes.has(type)) return false;
    return null;
}

export const revenueCatWebhook = onRequest(
    { region: LOCATION, secrets: [revenueCatWebhookSecret] },
    async (req, res) => {
        if (req.method !== "POST") {
            res.status(405).send("Method Not Allowed");
            return;
        }

        const secret = revenueCatWebhookSecret.value();
        if (!secret) {
            console.error("REVENUECAT_WEBHOOK_SECRET is not set");
            res.status(500).send("Server Misconfigured");
            return;
        }

        const signature = getSignatureHeader(req.headers);
        const authHeader = getAuthorizationHeader(req.headers);
        const hasValidAuthHeader = authHeader ? isValidAuthorizationHeader(authHeader, secret) : false;

        if (!signature && !hasValidAuthHeader) {
            res.status(401).send("Missing signature");
            return;
        }

        const rawBody = req.rawBody;
        const hasValidSignature = signature ? !!rawBody && isValidSignature(rawBody, signature, secret) : false;
        if (!hasValidSignature && !hasValidAuthHeader) {
            res.status(401).send("Invalid signature");
            return;
        }

        const payload = req.body as Record<string, unknown>;
        const event = (payload?.event ?? payload) as RevenueCatEvent;
        const transferredTo = event.transferred_to ?? [];
        const transferredUser =
            transferredTo.find((value) => value && !value.startsWith("$RCAnonymousID:")) ??
            transferredTo[0];
        const userId = String(
            event.app_user_id ??
                event.appUserId ??
                event.original_app_user_id ??
                event.aliases?.[0] ??
                transferredUser ??
                ""
        );

        if (!userId) {
            if ((event.type || "").toUpperCase() === "TRANSFER") {
                res.status(200).send("Ignored");
                return;
            }
            res.status(400).send("Missing app_user_id");
            return;
        }

        const isSubscriber = resolveSubscriberStatus(event);
        if (isSubscriber === null) {
            console.warn(`RevenueCat webhook ignored: unsupported event type ${event.type}`);
            res.status(200).send("Ignored");
            return;
        }

        // レースコンディション防止: isSubscriber=false に変更する場合、
        // 直近でisSubscriber=trueが書き込まれていないか確認する。
        // INITIAL_PURCHASE と EXPIRATION が同時に届く場合、
        // EXPIRATION（旧サブスク）がINITIAL_PURCHASE（新サブスク）を上書きするのを防ぐ。
        if (!isSubscriber) {
            const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
            if (userDoc.exists) {
                const userData = userDoc.data();
                const currentIsSubscriber = userData?.isSubscriber === true;
                const lastSyncedAt = userData?.subscriptionLastSyncedAt?.toDate?.();
                if (currentIsSubscriber && lastSyncedAt) {
                    const elapsedMs = Date.now() - lastSyncedAt.getTime();
                    if (elapsedMs < 10000) {
                        // 10秒以内にisSubscriber=trueが書き込まれた → EXPIRATION上書きを防止
                        res.status(200).send("OK");
                        return;
                    }
                }
            }
        }

        await db.collection(COLLECTIONS.USERS).doc(userId).set(
            {
                isSubscriber,
                subscriptionLastSyncedAt: FieldValue.serverTimestamp(),
                subscriptionSource: "webhook",
                updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true }
        );

        res.status(200).send("OK");
    }
);
