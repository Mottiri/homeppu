/**
 * 投稿トリガー
 * 公開済み投稿だけを AI コメント/リアクション対象にする
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";

import { LOCATION, PROJECT_ID } from "../config/constants";
import { geminiApiKey, openaiApiKey } from "../config/secrets";
import { schedulePublishedPostSideEffects } from "../helpers/post-publish";

export const onPostCreated = onDocumentCreated(
    {
        document: "posts/{postId}",
        region: LOCATION,
        secrets: [geminiApiKey, openaiApiKey],
        timeoutSeconds: 120,
        memory: "1GiB",
        serviceAccount: `cloud-tasks-sa@${PROJECT_ID}.iam.gserviceaccount.com`,
    },
    async (event) => {
        const snap = event.data;
        if (!snap) {
            console.log("No data associated with the event");
            return;
        }

        const postData = snap.data();
        const postId = event.params.postId;
        const moderationStatus = typeof postData.moderationStatus === "string" ?
            postData.moderationStatus :
            "approved";

        if (postData.isVisible !== true || moderationStatus !== "approved") {
            console.log(`Skipping unpublished post side effects: postId=${postId}, isVisible=${postData.isVisible}, moderationStatus=${moderationStatus}`);
            return;
        }

        await schedulePublishedPostSideEffects({
            postId,
            postData,
        });
    }
);
