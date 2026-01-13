/**
 * AI投稿スケジューラー関連
 * Phase 5: index.ts から分離
 */

import * as functionsV1 from "firebase-functions/v1";
import { CloudTasksClient } from "@google-cloud/tasks";

import { db, FieldValue } from "../helpers/firebase";
import { PROJECT_ID, LOCATION } from "../config/constants";
import { AI_PERSONAS } from "../ai/personas";

const MAX_AI_POSTS_PER_DAY = 5; // 1日あたりの投稿AI数

/**
 * AI投稿の自動スケジューラー（Cloud Scheduler用）
 * 毎日朝10時に実行、5人のAIをランダムに選んで投稿
 */
export const scheduleAIPosts = functionsV1.region(LOCATION).runWith({
    timeoutSeconds: 60,
}).pubsub.schedule("0 10 * * *").timeZone("Asia/Tokyo").onRun(async () => {
    console.log("=== scheduleAIPosts START ===");

    // ============================================
    // 一時的にAI自動投稿を無効化 (2026-01-05)
    // 有効にする場合はこのブロックをコメントアウトしてください
    // ============================================
    console.log("=== scheduleAIPosts DISABLED (temporary) ===");
    return;
    // ============================================

    try {
        const tasksClient = new CloudTasksClient();
        const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
        const queue = "generate-ai-posts";

        // 昨日の日付を取得（除外用）
        const yesterday = new Date();
        yesterday.setDate(yesterday.getDate() - 1);
        const yesterdayStr = yesterday.toISOString().split("T")[0];

        // 昨日投稿したAI IDリストを取得
        const historyDoc = await db.collection("aiPostHistory").doc(yesterdayStr).get();
        const excludedAIIds: string[] = historyDoc.exists ? (historyDoc.data()?.aiIds || []) : [];
        console.log(`Excluding ${excludedAIIds.length} AIs from yesterday`);

        // 除外されていないAIをフィルタリング
        const eligibleAIs = AI_PERSONAS.filter(p => !excludedAIIds.includes(p.id));
        console.log(`Eligible AIs: ${eligibleAIs.length}`);

        // ランダムに最大MAX_AI_POSTS_PER_DAY人選択
        const shuffled = eligibleAIs.sort(() => Math.random() - 0.5);
        const selectedAIs = shuffled.slice(0, MAX_AI_POSTS_PER_DAY);
        console.log(`Selected ${selectedAIs.length} AIs for posting`);

        const todayStr = new Date().toISOString().split("T")[0];
        const postedAIIds: string[] = [];

        const url = `https://${LOCATION}-${project}.cloudfunctions.net/executeAIPostGeneration`;
        const parent = tasksClient.queuePath(project, LOCATION, queue);

        for (const persona of selectedAIs) {
            // 0〜6時間後のランダムな時間にスケジュール
            const delayMinutes = Math.floor(Math.random() * 360);
            const scheduleTime = new Date(Date.now() + delayMinutes * 60 * 1000);

            const postId = db.collection("posts").doc().id;
            const payload = {
                postId,
                personaId: persona.id,
                postTimeIso: scheduleTime.toISOString(),
            };

            const task = {
                httpRequest: {
                    httpMethod: "POST" as const,
                    url: url,
                    body: Buffer.from(JSON.stringify(payload)).toString("base64"),
                    headers: {
                        "Content-Type": "application/json",
                        "Authorization": "Bearer internal-token",
                    },
                },
                scheduleTime: {
                    seconds: Math.floor(scheduleTime.getTime() / 1000),
                },
            };

            try {
                await tasksClient.createTask({ parent, task });
                console.log(`Scheduled post for ${persona.name} at ${scheduleTime.toISOString()}`);
                postedAIIds.push(persona.id);
            } catch (error) {
                console.error(`Error scheduling task for ${persona.name}:`, error);
            }
        }

        // 今日の投稿履歴を保存（明日の除外用）
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
