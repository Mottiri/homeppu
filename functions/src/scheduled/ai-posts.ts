/**
 * AI post scheduler (currently disabled).
 */

import * as functionsV1 from "firebase-functions/v1";
import { scheduleHttpTask } from "../helpers/cloud-tasks";

import { db, FieldValue } from "../helpers/firebase";
import { PROJECT_ID, LOCATION } from "../config/constants";
import { AI_PERSONAS } from "../ai/personas";

const MAX_AI_POSTS_PER_DAY = 5; // 1譌･縺ゅ◆繧翫・謚慕ｨｿAI謨ｰ

/**
 * AI謚慕ｨｿ縺ｮ閾ｪ蜍輔せ繧ｱ繧ｸ繝･繝ｼ繝ｩ繝ｼ・・loud Scheduler逕ｨ・・
 * 豈取律譛・0譎ゅ↓螳溯｡後・莠ｺ縺ｮAI繧偵Λ繝ｳ繝繝縺ｫ驕ｸ繧薙〒謚慕ｨｿ
 */
export const scheduleAIPosts = functionsV1.region(LOCATION).runWith({
    timeoutSeconds: 60,
}).pubsub.schedule("0 10 * * *").timeZone("Asia/Tokyo").onRun(async () => {
    return;

    try {
        const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
        const queue = "generate-ai-posts";

        // 譏ｨ譌･縺ｮ譌･莉倥ｒ蜿門ｾ暦ｼ磯勁螟也畑・・
        const yesterday = new Date();
        yesterday.setDate(yesterday.getDate() - 1);
        const yesterdayStr = yesterday.toISOString().split("T")[0];

        // 譏ｨ譌･謚慕ｨｿ縺励◆AI ID繝ｪ繧ｹ繝医ｒ蜿門ｾ・
        const historyDoc = await db.collection("aiPostHistory").doc(yesterdayStr).get();
        const excludedAIIds: string[] = historyDoc.exists ? (historyDoc.data()?.aiIds || []) : [];
        console.log(`Excluding ${excludedAIIds.length} AIs from yesterday`);

        // 髯､螟悶＆繧後※縺・↑縺БI繧偵ヵ繧｣繝ｫ繧ｿ繝ｪ繝ｳ繧ｰ
        const eligibleAIs = AI_PERSONAS.filter(p => !excludedAIIds.includes(p.id));
        console.log(`Eligible AIs: ${eligibleAIs.length}`);

        // 繝ｩ繝ｳ繝繝縺ｫ譛螟ｧMAX_AI_POSTS_PER_DAY莠ｺ驕ｸ謚・
        const shuffled = eligibleAIs.sort(() => Math.random() - 0.5);
        const selectedAIs = shuffled.slice(0, MAX_AI_POSTS_PER_DAY);
        console.log(`Selected ${selectedAIs.length} AIs for posting`);

        const todayStr = new Date().toISOString().split("T")[0];
        const postedAIIds: string[] = [];

        const url = `https://${LOCATION}-${project}.cloudfunctions.net/executeAIPostGeneration`;
        for (const persona of selectedAIs) {
            // 0縲・譎る俣蠕後・繝ｩ繝ｳ繝繝縺ｪ譎る俣縺ｫ繧ｹ繧ｱ繧ｸ繝･繝ｼ繝ｫ
            const delayMinutes = Math.floor(Math.random() * 360);
            const scheduleTime = new Date(Date.now() + delayMinutes * 60 * 1000);

            const postId = db.collection("posts").doc().id;
            const payload = {
                postId,
                personaId: persona.id,
                postTimeIso: scheduleTime.toISOString(),
            };

            try {
                await scheduleHttpTask({
                    queue,
                    url,
                    payload,
                    scheduleTime,
                    headers: { "Authorization": "Bearer internal-token" },
                    projectId: project,
                    location: LOCATION,
                });
                console.log(`Scheduled post for ${persona.name} at ${scheduleTime.toISOString()}`);
                postedAIIds.push(persona.id);
            } catch (error) {
                console.error(`Error scheduling task for ${persona.name}:`, error);
            }
        }

        // 莉頑律縺ｮ謚慕ｨｿ螻･豁ｴ繧剃ｿ晏ｭ假ｼ域・譌･縺ｮ髯､螟也畑・・
        if (postedAIIds.length > 0) {
            const historyRef = db.collection("aiPostHistory").doc(todayStr);
            const existingHistory = await historyRef.get();
            const existingIds: string[] = existingHistory.exists ? (existingHistory.data()?.aiIds || []) : [];
            const mergedIds = [...new Set([...existingIds, ...postedAIIds])];

            await historyRef.set({
                date: todayStr,
                aiIds: mergedIds,
                updatedAt: FieldValue.serverTimestamp(),
            });
            console.log(`Saved ${mergedIds.length} AI IDs to history for ${todayStr}`);
        }

        console.log(`=== scheduleAIPosts COMPLETE: Scheduled ${postedAIIds.length} posts ===`);

    } catch (error) {
        console.error("=== scheduleAIPosts ERROR:", error);
    }
});

