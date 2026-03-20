import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db, FieldValue } from "../helpers/firebase";
import { requireAuth } from "../helpers/auth";
import { LOCATION } from "../config/constants";
import { COLLECTIONS } from "../config/collections";
import { revenueCatServerApiKey } from "../config/secrets";
import { SYSTEM_ERRORS, SUBSCRIPTION_ERRORS } from "../config/messages";

export const syncSubscriptionStatus = onCall(
    {
        region: LOCATION,
        enforceAppCheck: true,
        secrets: [revenueCatServerApiKey],
        timeoutSeconds: 30,
        memory: "256MiB",
    },
    async (request) => {
        const userId = requireAuth(request);

        const apiKey = revenueCatServerApiKey.value();
        if (!apiKey) {
            console.error("REVENUECAT_SERVER_API_KEY is not set");
            throw new HttpsError("internal", SYSTEM_ERRORS.INTERNAL);
        }

        const response = await fetch(
            `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`,
            {
                headers: {
                    "Authorization": `Bearer ${apiKey}`,
                    "Content-Type": "application/json",
                },
            }
        );

        if (response.status === 404) {
            // ユーザーがRevenueCatに存在しない（未購入）
            // Firestore更新なし: 404は一時的なalias/restore問題の可能性あり
            // 購読状態の権威的変更はWebhookに委譲する
            return { isSubscriber: false };
        }

        if (!response.ok) {
            console.error(`RevenueCat API error: ${response.status} ${response.statusText}`);
            throw new HttpsError("internal", SUBSCRIPTION_ERRORS.SYNC_FAILED);
        }

        const data = await response.json();

        if (!data?.subscriber) {
            console.error(`RevenueCat API: unexpected response structure for userId=${userId}`);
            throw new HttpsError("internal", SUBSCRIPTION_ERRORS.SYNC_FAILED);
        }

        const entitlements = data.subscriber.entitlements ?? {};
        const nowMs = Date.now();
        const isSubscriber = Object.values(entitlements).some((e: any) => {
            const expiresMs = e.expires_date ? new Date(e.expires_date).getTime() : null;
            if (expiresMs !== null && Number.isNaN(expiresMs)) return false;
            return expiresMs === null || expiresMs > nowMs;
        });

        // 既存値と比較し、変更がある場合のみFirestoreを更新（write amplification防止）
        const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
        const currentIsSubscriber = userDoc.exists ? userDoc.data()?.isSubscriber === true : false;

        if (currentIsSubscriber !== isSubscriber) {
            await db.collection(COLLECTIONS.USERS).doc(userId).set(
                {
                    isSubscriber,
                    subscriptionLastSyncedAt: FieldValue.serverTimestamp(),
                    subscriptionSource: "callable",
                    updatedAt: FieldValue.serverTimestamp(),
                },
                { merge: true }
            );
        }

        return { isSubscriber };
    }
);
