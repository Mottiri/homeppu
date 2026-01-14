/**
 * AI管理関連のCallable関数
 * Phase 5: index.ts から分離
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { GoogleGenerativeAI } from "@google/generative-ai";
import { CloudTasksClient } from "@google-cloud/tasks";

import { db, FieldValue } from "../helpers/firebase";
import { PROJECT_ID, LOCATION } from "../config/constants";
import { geminiApiKey } from "../config/secrets";
import { isAdmin } from "../helpers/admin";
import {
    AIPersona,
    AI_PERSONAS,
    AGE_GROUPS,
} from "../ai/personas";
import { getBioGenerationPrompt } from "../ai/prompts/bio-generation";

/**
 * Gemini APIを使ってキャラクターに合ったbioを生成
 */
async function generateBioWithGemini(
    model: ReturnType<GoogleGenerativeAI["getGenerativeModel"]>,
    persona: AIPersona
): Promise<string> {
    const prompt = getBioGenerationPrompt(persona);

    try {
        const result = await model.generateContent(prompt);
        const bio = result.response.text()?.trim();

        if (bio && bio.length > 0 && bio.length <= 100) {
            return bio;
        }

        // 長すぎる場合は切り詰め
        if (bio && bio.length > 100) {
            return bio.substring(0, 100);
        }

        // 生成失敗時のフォールバック
        return `${persona.occupation.name} してます！よろしくね✨`;
    } catch (error) {
        console.error(`Bio generation error for ${persona.name}: `, error);
        return `${persona.occupation.name} してます！よろしくね✨`;
    }
}

/**
 * AIアカウントを初期化する関数（管理者用）
 * 既存のアカウントも更新します
 * ランダム組み合わせ方式で20体のAIアカウントを生成
 * Gemini APIでキャラクターに合ったbioを動的生成
 */
export const initializeAIAccounts = onCall(
    { region: LOCATION, secrets: [geminiApiKey], timeoutSeconds: 300 },
    async (request) => {
        // セキュリティ: 管理者権限チェック
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "ログインが必要です");
        }
        const userIsAdmin = await isAdmin(request.auth.uid);
        if (!userIsAdmin) {
            throw new HttpsError("permission-denied", "管理者権限が必要です");
        }

        const apiKey = geminiApiKey.value();
        if (!apiKey) {
            return { success: false, message: "GEMINI_API_KEY is not set" };
        }

        const genAI = new GoogleGenerativeAI(apiKey);
        const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

        let createdCount = 0;
        let updatedCount = 0;
        const generatedBios: { name: string; bio: string }[] = [];

        console.log(`Initializing ${AI_PERSONAS.length} AI accounts with Gemini - generated bios...`);

        for (const persona of AI_PERSONAS) {
            const docRef = db.collection("users").doc(persona.id);
            const doc = await docRef.get();

            // Gemini APIでbioを生成
            console.log(`Generating bio for ${persona.name}...`);
            const generatedBio = await generateBioWithGemini(model, persona);
            console.log(`  Generated: "${generatedBio}"`);
            generatedBios.push({ name: persona.name, bio: generatedBio });

            // AIキャラ設定を保存
            const aiCharacterSettings = {
                gender: persona.gender,
                ageGroup: persona.ageGroup,
                occupationId: persona.occupation.id,
                personalityId: persona.personality.id,
                praiseStyleId: persona.praiseStyle.id,
            };

            const userData = {
                email: `${persona.id} @ai.homeppu.local`,
                displayName: persona.name,
                namePrefix: persona.namePrefixId,
                nameSuffix: persona.nameSuffixId,
                bio: generatedBio,
                avatarIndex: persona.avatarIndex,
                postMode: "ai",
                virtue: 100,
                isAI: true,
                aiCharacterSettings: aiCharacterSettings,
                updatedAt: FieldValue.serverTimestamp(),
                isBanned: false,
            };

            if (!doc.exists) {
                await docRef.set({
                    ...userData,
                    createdAt: FieldValue.serverTimestamp(),
                    totalPosts: 0,
                    totalPraises: 0,
                    following: [],
                    followers: [],
                    followingCount: 0,
                    followersCount: 0,
                });
                createdCount++;
                console.log(`Created AI account: ${persona.name} (${persona.id})`);
            } else {
                await docRef.update({
                    displayName: persona.name,
                    namePrefix: persona.namePrefixId,
                    nameSuffix: persona.nameSuffixId,
                    bio: generatedBio,
                    avatarIndex: persona.avatarIndex,
                    aiCharacterSettings: aiCharacterSettings,
                    updatedAt: FieldValue.serverTimestamp(),
                });
                updatedCount++;
                console.log(`Updated AI account: ${persona.name} (${persona.id})`);
            }

            // API呼び出しの間隔を空ける
            await new Promise((resolve) => setTimeout(resolve, 500));
        }

        // AIアカウントの一覧をログ出力
        console.log("AI Account Summary:");
        AI_PERSONAS.forEach((p, i) => {
            console.log(`  ${i + 1}. ${p.name} - ${p.gender === "male" ? "男" : "女"} /${AGE_GROUPS[p.ageGroup].name}/${p.occupation.name} /${p.personality.name}/${p.praiseStyle.name} `);
        });

        return {
            success: true,
            message: `AIアカウントを作成 / 更新しました（Gemini APIでbio生成: ${AI_PERSONAS.length} 体）`,
            created: createdCount,
            updated: updatedCount,
            totalAccounts: AI_PERSONAS.length,
            accounts: AI_PERSONAS.map((p, i) => ({
                id: p.id,
                name: p.name,
                gender: p.gender,
                ageGroup: AGE_GROUPS[p.ageGroup].name,
                occupation: p.occupation.name,
                personality: p.personality.name,
                praiseStyle: p.praiseStyle.name,
                bio: generatedBios[i]?.bio || "",
            })),
        };
    }
);

/**
 * AI投稿生成のディスパッチャー（手動トリガー用）
 */
export const generateAIPosts = onCall(
    { region: LOCATION },
    async (request) => {
        // セキュリティ: 管理者権限チェック
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "ログインが必要です");
        }
        const userIsAdmin = await isAdmin(request.auth.uid);
        if (!userIsAdmin) {
            throw new HttpsError("permission-denied", "管理者権限が必要です");
        }

        const tasksClient = new CloudTasksClient();
        const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
        const queue = "generate-ai-posts";
        const parent = tasksClient.queuePath(project, LOCATION, queue);

        const url = `https://${LOCATION}-${project}.cloudfunctions.net/executeAIPostGeneration`;

        let taskCount = 0;

        for (const persona of AI_PERSONAS) {
            const delaySeconds = Math.floor(Math.random() * (600 - 60 + 1)) + 60;
            const scheduleTime = new Date(Date.now() + delaySeconds * 1000);

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

            await tasksClient.createTask({ parent, task });
            taskCount++;
        }

        return {
            success: true,
            message: `AI投稿タスクを${taskCount}件スケジュールしました。\nすべて完了するまでに1分〜10分ほどかかります。`,
        };
    }
);
