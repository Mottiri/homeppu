/**
 * 投稿トリガー関連
 * Phase 5: index.ts から分離
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { GoogleGenerativeAI } from "@google/generative-ai";
import { CloudTasksClient } from "@google-cloud/tasks";

import { db } from "../helpers/firebase";
import { PROJECT_ID, LOCATION, QUEUE_NAME, AI_MODELS } from "../config/constants";
import { geminiApiKey } from "../config/secrets";
import { MediaItem } from "../types";
import { analyzeMediaForComment } from "../helpers/media-analysis";
import {
    Gender,
    AgeGroup,
    AIPersona,
    PERSONALITIES,
    PRAISE_STYLES,
    AI_PERSONAS,
} from "../ai/personas";

/**
 * 新規投稿時にAIコメントを生成するトリガー
 * メディア（画像・動画）がある場合は内容を分析してコメントに反映
 */
export const onPostCreated = onDocumentCreated(
    {
        document: "posts/{postId}",
        region: LOCATION,
        secrets: [geminiApiKey],
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

        console.log(`=== onPostCreated: postId=${postId}, circleId=${postData.circleId}, postMode=${postData.postMode} ===`);

        // サークル投稿かどうかを判定
        const isCirclePost = postData.circleId && postData.circleId !== "" && postData.circleId !== null;

        // 人間モードの投稿にはAIコメントを付けない
        if (postData.postMode === "human") {
            console.log("Human mode post, skipping AI comments");
            return;
        }

        // APIキーを取得
        const apiKey = geminiApiKey.value();
        if (!apiKey) {
            console.error("GEMINI_API_KEY is not set");
            return;
        }

        const genAI = new GoogleGenerativeAI(apiKey);
        const model = genAI.getGenerativeModel({ model: AI_MODELS.GEMINI_DEFAULT });

        // メディアがある場合は内容を分析
        let mediaDescriptions: string[] = [];
        const mediaItems = postData.mediaItems as MediaItem[] | undefined;

        if (mediaItems && mediaItems.length > 0) {
            console.log(`Analyzing ${mediaItems.length} media items for AI comment...`);
            try {
                mediaDescriptions = await analyzeMediaForComment(apiKey, model, mediaItems);
                console.log(`Media analysis complete: ${mediaDescriptions.length} descriptions`);
            } catch (error) {
                console.error("Media analysis failed:", error);
                // エラーでもコメント生成は続行
            }
        }

        // サークル投稿の場合はサークルAIを使用、それ以外は一般AIを使用
        let selectedPersonas: AIPersona[];
        let circleName = "";
        let circleDescription = "";
        let circleGoal = "";
        let circleRules = "";

        if (isCirclePost) {
            // サークル情報を取得
            const circleDoc = await db.collection("circles").doc(postData.circleId).get();
            if (!circleDoc.exists) {
                console.log(`Circle ${postData.circleId} not found, skipping AI comments`);
                return;
            }

            const circleData = circleDoc.data()!;

            // humanOnlyモードの場合はAIコメントをスキップ
            if (circleData.aiMode === "humanOnly") {
                console.log(`Circle ${postData.circleId} is humanOnly mode, skipping AI comments`);
                return;
            }

            const generatedAIs = circleData.generatedAIs as Array<{
                id: string;
                name: string;
                gender: Gender;
                ageGroup: AgeGroup;
                occupation: { id: string; name: string; bio: string };
                personality: { id: string; name: string; trait: string; style: string; examples?: string[] };
                avatarIndex: number;
                circleContext?: string;
            }> || [];

            if (generatedAIs.length === 0) {
                console.log(`No generated AIs for circle ${postData.circleId}, skipping AI comments`);
                return;
            }

            // サークルのgoal, rules, descriptionを取得
            circleName = circleData.name || "";
            circleDescription = circleData.description || "";
            circleGoal = circleData.goal || "";
            circleRules = circleData.rules || "";

            // サークルAIをAIPersona形式に変換
            selectedPersonas = generatedAIs.map((ai) => {
                const gender = ai.gender || "female";
                const personalityList = PERSONALITIES[gender];
                const matchedPersonality = personalityList.find(p => p.id === ai.personality?.id) || personalityList[0];

                return {
                    id: ai.id,
                    name: ai.name,
                    namePrefixId: "",
                    nameSuffixId: "",
                    gender: gender,
                    ageGroup: ai.ageGroup,
                    occupation: ai.occupation,
                    personality: {
                        ...ai.personality,
                        examples: matchedPersonality.examples,
                        reactionType: matchedPersonality.reactionType,
                        reactionGuide: matchedPersonality.reactionGuide,
                    },
                    praiseStyle: PRAISE_STYLES[Math.floor(Math.random() * PRAISE_STYLES.length)],
                    avatarIndex: ai.avatarIndex,
                    bio: "",
                };
            });

            console.log(`Using ${selectedPersonas.length} circle AIs for comments`);
        } else {
            // 一般投稿：ランダムに1〜5人のAIを選択
            const commentCount = Math.floor(Math.random() * 5) + 1;
            selectedPersonas = [...AI_PERSONAS]
                .sort(() => Math.random() - 0.5)
                .slice(0, commentCount);

            console.log(`Using ${selectedPersonas.length} general AIs for comments`);
        }

        let totalComments = 0;

        // 投稿者の名前を取得
        const posterName = postData.userDisplayName || "投稿者";

        // ランダムな遅延時間を生成
        const delays = Array.from({ length: selectedPersonas.length }, (_, i) => (i + 1) * 2 + Math.floor(Math.random() * 2))
            .sort((a, b) => a - b);

        // Cloud Tasks クライアント
        const tasksClient = new CloudTasksClient();
        const queuePath = tasksClient.queuePath(process.env.GCLOUD_PROJECT || PROJECT_ID, LOCATION, QUEUE_NAME);

        for (let i = 0; i < selectedPersonas.length; i++) {
            const persona = selectedPersonas[i];
            const delayMinutes = delays[i];

            const scheduleTime = new Date(Date.now() + delayMinutes * 60 * 1000);

            try {
                const payload = {
                    postId: postId,
                    postContent: postData.content || "",
                    userDisplayName: posterName,
                    personaId: persona.id,
                    personaName: persona.name,
                    personaGender: persona.gender,
                    personaAgeGroup: persona.ageGroup,
                    personaOccupation: persona.occupation,
                    personaPersonality: persona.personality,
                    personaPraiseStyle: persona.praiseStyle,
                    personaAvatarIndex: persona.avatarIndex,
                    mediaDescriptions: mediaDescriptions,
                    isCirclePost: isCirclePost,
                    circleName: isCirclePost ? circleName : "",
                    circleDescription: isCirclePost ? circleDescription : "",
                    circleGoal: isCirclePost ? circleGoal : "",
                    circleRules: isCirclePost ? circleRules : "",
                };

                const targetUrl = `https://${LOCATION}-${process.env.GCLOUD_PROJECT}.cloudfunctions.net/generateAICommentV1`;
                const serviceAccountEmail = `cloud-tasks-sa@${process.env.GCLOUD_PROJECT}.iam.gserviceaccount.com`;

                console.log(`Enqueuing task for ${persona.name} to ${targetUrl} with SA ${serviceAccountEmail}`);

                const task = {
                    httpRequest: {
                        httpMethod: "POST" as const,
                        url: targetUrl,
                        body: Buffer.from(JSON.stringify(payload)).toString("base64"),
                        headers: {
                            "Content-Type": "application/json",
                        },
                        oidcToken: {
                            serviceAccountEmail: serviceAccountEmail,
                        },
                    },
                    scheduleTime: {
                        seconds: Math.floor(scheduleTime.getTime() / 1000),
                    },
                };

                await tasksClient.createTask({ parent: queuePath, task });

                console.log(`Task enqueued for ${persona.name}: delay=${delayMinutes}m, time=${scheduleTime.toISOString()}`);
                totalComments++;
            } catch (error) {
                console.error(`Error enqueuing task for ${persona.name}:`, error);
            }
        }

        // ===========================================
        // 2. AIリアクションの大量投下 (5〜10件)
        // ===========================================
        const reactionCount = Math.floor(Math.random() * 6) + 5;
        console.log(`Scheduling ${reactionCount} reactions (burst)...`);

        const POSITIVE_REACTIONS = ["love", "praise", "cheer", "sparkles", "clap", "thumbsup", "smile", "flower", "fire", "nice"];

        for (let i = 0; i < reactionCount; i++) {
            const persona = AI_PERSONAS[Math.floor(Math.random() * AI_PERSONAS.length)];
            const reactionType = POSITIVE_REACTIONS[Math.floor(Math.random() * POSITIVE_REACTIONS.length)];

            const delaySeconds = Math.floor(Math.random() * 3600) + 10;
            const scheduleTime = new Date(Date.now() + delaySeconds * 1000);

            const payload = {
                postId,
                personaId: persona.id,
                personaName: persona.name,
                reactionType,
            };

            const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
            const url = `https://${LOCATION}-${project}.cloudfunctions.net/generateAIReactionV1`;
            const serviceAccountEmail = `cloud-tasks-sa@${project}.iam.gserviceaccount.com`;

            const task = {
                httpRequest: {
                    httpMethod: "POST" as const,
                    url,
                    headers: {
                        "Content-Type": "application/json",
                        "Authorization": "Bearer secret-token",
                    },
                    body: Buffer.from(JSON.stringify(payload)).toString("base64"),
                    oidcToken: {
                        serviceAccountEmail: serviceAccountEmail,
                    },
                },
                scheduleTime: {
                    seconds: Math.floor(scheduleTime.getTime() / 1000),
                },
            };

            try {
                await tasksClient.createTask({ parent: queuePath, task });
            } catch (error) {
                console.error(`Error enqueuing reaction for ${persona.name}:`, error);
            }
        }

        console.log(`Scheduled ${reactionCount} reaction tasks`);
    }
);
