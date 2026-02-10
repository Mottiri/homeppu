/**
 * リアクション関連のFirestoreトリガー
 * Phase 5: index.ts から分離
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";

import { db, FieldValue } from "../helpers/firebase";
import { getVirtuePolicy, grantVirtue, VIRTUE_ROUTE_KEYS } from "../helpers/virtue-policy";
import { LOCATION } from "../config/constants";

/**
 * リアクション追加時に投稿者のtotalPraisesをインクリメント
 */
export const onReactionCreated = onDocumentCreated(
    {
        document: "reactions/{reactionId}",
        region: LOCATION,
    },
    async (event) => {
        const snapshot = event.data;
        if (!snapshot) {
            console.log("No reaction data");
            return;
        }

        const reactionData = snapshot.data();
        const postId = reactionData.postId;
        const reactorId = reactionData.userId;

        console.log(`=== onReactionCreated: postId=${postId}, reactor=${reactorId} ===`);

        try {
            // 投稿を取得して投稿者IDを取得
            const postDoc = await db.collection("posts").doc(postId).get();
            if (!postDoc.exists) {
                console.log("Post not found:", postId);
                return;
            }

            const postData = postDoc.data()!;
            const postOwnerId = postData.userId;

            // 自分へのリアクションはカウントしない
            if (postOwnerId === reactorId) {
                console.log("Self-reaction, skipping totalPraises update");
                return;
            }

            // 投稿者のtotalPraisesをインクリメント
            await db.collection("users").doc(postOwnerId).update({
                totalPraises: FieldValue.increment(1),
            });

            console.log(`Incremented totalPraises for user: ${postOwnerId}`);

            // 徳ポイント付与（人間ユーザー同士のみ）
            const [reactorDoc, postOwnerDoc] = await Promise.all([
                db.collection("users").doc(reactorId).get(),
                db.collection("users").doc(postOwnerId).get(),
            ]);
            const reactorIsAI = reactorDoc.data()?.isAI === true;
            const postOwnerIsAI = postOwnerDoc.data()?.isAI === true;

            if (!reactorIsAI && !postOwnerIsAI) {
                const virtuePolicy = await getVirtuePolicy();
                await Promise.all([
                    grantVirtue({
                        userId: reactorId,
                        routeKey: VIRTUE_ROUTE_KEYS.reactionGiven,
                        points: virtuePolicy.reactionGivenPoints,
                        dailyCap: virtuePolicy.reactionGivenDailyCap,
                        reason: "リアクション送信",
                        source: "reaction_given",
                        targetId: postId,
                    }),
                    grantVirtue({
                        userId: postOwnerId,
                        routeKey: VIRTUE_ROUTE_KEYS.reactionReceived,
                        points: virtuePolicy.reactionReceivedPoints,
                        dailyCap: virtuePolicy.reactionReceivedDailyCap,
                        reason: "リアクション受信",
                        source: "reaction_received",
                        targetId: postId,
                    }),
                ]);
            }

        } catch (error) {
            console.error("onReactionCreated ERROR:", error);
        }
    }
);
