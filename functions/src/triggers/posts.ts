/**
 * 投稿トリガー関連
 * Phase 5: index.ts から分離
 */

import { createHash } from "crypto";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { scheduleHttpTask } from "../helpers/cloud-tasks";
import { deterministicShuffle, generateAICommentId, generateAIReactionId } from "../helpers/ai-keys";

import { db } from "../helpers/firebase";
import { PROJECT_ID, LOCATION, QUEUE_NAME } from "../config/constants";
import { geminiApiKey, openaiApiKey } from "../config/secrets";
import { createAIProviderFactory } from "../ai/provider";
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

        console.log(`=== onPostCreated: postId=${postId}, circleId=${postData.circleId}, postMode=${postData.postMode} ===`);

        // サークル投稿かどうかを判定
        const isCirclePost = postData.circleId && postData.circleId !== "" && postData.circleId !== null;

        // 人間モードの投稿にはAIコメントを付けない
        if (postData.postMode === "human") {
            console.log("Human mode post, skipping AI comments");
            return;
        }

        // APIキーが1つも利用できない場合はスキップ
        const geminiKey = geminiApiKey.value() || "";
        const openaiKey = openaiApiKey.value() || "";
        if (!geminiKey && !openaiKey) {
            console.error("No AI API key available, skipping AI comments");
            return;
        }

        const aiFactory = createAIProviderFactory();

        // メディアがある場合は内容を分析
        let mediaDescriptions: string[] = [];
        const mediaItems = postData.mediaItems as MediaItem[] | undefined;

        if (mediaItems && mediaItems.length > 0) {
            console.log(`Analyzing ${mediaItems.length} media items for AI comment...`);
            try {
                mediaDescriptions = await analyzeMediaForComment(aiFactory, mediaItems);
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
            // 一般投稿：postIdシードのdeterministic shuffleでAIを選択
            const shuffledForComment = deterministicShuffle(AI_PERSONAS, postId);
            const commentCountHash = createHash("sha256").update(`${postId}-comment-count`).digest();
            const commentCount = (commentCountHash[0] % 5) + 1; // 1-5の範囲でdeterministic
            selectedPersonas = shuffledForComment.slice(0, commentCount);

            console.log(`Using ${selectedPersonas.length} general AIs for comments`);
        }

        // 投稿者の名前を取得
        const posterName = postData.userDisplayName || "投稿者";

        // ランダムな遅延時間を生成
        const delays = Array.from({ length: selectedPersonas.length }, (_, i) => (i + 1) * 2 + Math.floor(Math.random() * 2))
            .sort((a, b) => a - b);

        const project = process.env.GCLOUD_PROJECT || PROJECT_ID;

        // Cloud Tasks: コメントタスクを並列投入
        const commentTargetUrl = `https://${LOCATION}-${project}.cloudfunctions.net/generateAICommentV1`;

        const commentResults = await Promise.allSettled(
            selectedPersonas.map((persona, i) => {
                const delayMinutes = delays[i];
                const scheduleTime = new Date(Date.now() + delayMinutes * 60 * 1000);
                const idempotencyKey = generateAICommentId(postId, persona.id);

                return scheduleHttpTask({
                    queue: QUEUE_NAME,
                    url: commentTargetUrl,
                    payload: {
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
                        idempotencyKey,
                    },
                    scheduleTime,
                    projectId: project,
                    location: LOCATION,
                    taskId: idempotencyKey,
                });
            })
        );

        commentResults.forEach((result, i) => {
            const persona = selectedPersonas[i];
            if (result.status === "fulfilled") {
                const outcome = result.value.result;
                if (outcome === "duplicate_skipped") {
                    console.log(`Task for ${persona.name}: duplicate skipped`);
                } else {
                    console.log(`Task enqueued for ${persona.name}: delay=${delays[i]}m`);
                }
            } else {
                console.error(`Error enqueuing task for ${persona.name}:`, result.reason);
            }
        });

        // ===========================================
        // 2. AIリアクションの大量投下 (5〜10件)
        // ===========================================
        // reactionCountもpostIdから決定的に算出（リトライ間で変わらない）
        const countHash = createHash("sha256").update(`${postId}-reaction-count`).digest();
        const reactionCount = Math.min(
            (countHash[0] % 6) + 5, // 5-10の範囲でdeterministic
            AI_PERSONAS.length
        );
        console.log(`Scheduling ${reactionCount} reactions (burst)...`);

        const POSITIVE_REACTIONS = ["love", "praise", "cheer", "sparkles", "clap", "thumbsup", "smile", "flower", "fire", "nice"];

        // postIdシードのdeterministic shuffleでpersonaを選択（重複なし）
        // コメントペルソナはgenerateAICommentV1内でリアクションも作成するため除外
        const commentPersonaIds = new Set(selectedPersonas.map(p => p.id));
        const nonCommentPersonas = AI_PERSONAS.filter(p => !commentPersonaIds.has(p.id));
        const shuffled = deterministicShuffle(nonCommentPersonas, postId);
        const selectedForReaction = shuffled.slice(0, reactionCount);

        const reactionUrl = `https://${LOCATION}-${project}.cloudfunctions.net/generateAIReactionV1`;

        const reactionResults = await Promise.allSettled(
            selectedForReaction.map((persona) => {
                const reactionHash = createHash("sha256").update(`${postId}-reaction-type-${persona.id}`).digest();
                const reactionType = POSITIVE_REACTIONS[reactionHash[0] % POSITIVE_REACTIONS.length];

                const delayHash = createHash("sha256").update(`${postId}-reaction-delay-${persona.id}`).digest();
                const delaySeconds = (delayHash.readUInt16BE(0) % 3600) + 10;
                const scheduleTime = new Date(Date.now() + delaySeconds * 1000);

                const idempotencyKey = generateAIReactionId(postId, persona.id);

                return scheduleHttpTask({
                    queue: QUEUE_NAME,
                    url: reactionUrl,
                    payload: {
                        postId,
                        personaId: persona.id,
                        personaName: persona.name,
                        reactionType,
                        idempotencyKey,
                    },
                    scheduleTime,
                    headers: { "Authorization": "Bearer secret-token" },
                    projectId: project,
                    location: LOCATION,
                    taskId: idempotencyKey,
                });
            })
        );

        let reactionCreated = 0;
        let reactionDuplicates = 0;
        reactionResults.forEach((r) => {
            if (r.status === "fulfilled") {
                if (r.value.result === "duplicate_skipped") reactionDuplicates++;
                else reactionCreated++;
            } else {
                console.error("Reaction task enqueue failed:", r.reason);
            }
        });
        console.log(`Reaction tasks: ${reactionCreated} created, ${reactionDuplicates} duplicates skipped, ${reactionResults.length - reactionCreated - reactionDuplicates} failed`);
    }
);
