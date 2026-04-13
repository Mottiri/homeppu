import { createHash } from "crypto";
import { scheduleHttpTask } from "./cloud-tasks";
import { deterministicShuffle, generateAICommentId, generateAIReactionId } from "./ai-keys";
import { db } from "./firebase";
import { PROJECT_ID, LOCATION, QUEUE_NAME } from "../config/constants";
import { createAIProviderFactory } from "../ai/provider";
import { MediaItem } from "../types";
import { analyzeMediaForComment } from "./media-analysis";
import {
    Gender,
    AgeGroup,
    AIPersona,
    PERSONALITIES,
    PRAISE_STYLES,
    AI_PERSONAS,
} from "../ai/personas";

export async function schedulePublishedPostSideEffects(params: {
    postId: string;
    postData: Record<string, any>;
}): Promise<void> {
    const { postId, postData } = params;

    const isCirclePost = postData.circleId && postData.circleId !== "" && postData.circleId !== null;

    if (postData.postMode === "human") {
        return;
    }

    const aiFactory = createAIProviderFactory();

    let mediaDescriptions: string[] = [];
    const mediaItems = postData.mediaItems as MediaItem[] | undefined;

    if (mediaItems && mediaItems.length > 0) {
        try {
            mediaDescriptions = await analyzeMediaForComment(aiFactory, mediaItems);
        } catch (error) {
            console.error("Media analysis failed:", error);
        }
    }

    let selectedPersonas: AIPersona[];
    let circleName = "";
    let circleDescription = "";
    let circleGoal = "";
    let circleRules = "";

    if (isCirclePost) {
        const circleDoc = await db.collection("circles").doc(postData.circleId).get();
        if (!circleDoc.exists) {
            return;
        }

        const circleData = circleDoc.data()!;
        if (circleData.aiMode === "humanOnly") {
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
            return;
        }

        circleName = circleData.name || "";
        circleDescription = circleData.description || "";
        circleGoal = circleData.goal || "";
        circleRules = circleData.rules || "";

        selectedPersonas = generatedAIs.map((ai) => {
            const gender = ai.gender || "female";
            const personalityList = PERSONALITIES[gender];
            const matchedPersonality = personalityList.find((p) => p.id === ai.personality?.id) || personalityList[0];

            return {
                id: ai.id,
                name: ai.name,
                namePrefixId: "",
                nameSuffixId: "",
                gender,
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
    } else {
        const shuffledForComment = deterministicShuffle(AI_PERSONAS, postId);
        const commentCountHash = createHash("sha256").update(`${postId}-comment-count`).digest();
        const commentCount = (commentCountHash[0] % 5) + 1;
        selectedPersonas = shuffledForComment.slice(0, commentCount);
    }

    const posterName = postData.userDisplayName || "投稿者";

    const MIN_DELAY_MINUTES = 1;
    const MAX_DELAY_MINUTES = 720;
    const FIRST_COMMENT_MAX_MINUTES = 30;

    const personaDelays = selectedPersonas.map((persona) => {
        const hash = createHash("sha256")
            .update(`${postId}-comment-delay-${persona.id}`)
            .digest();
        const delay = MIN_DELAY_MINUTES +
            (hash.readUInt16BE(0) % (MAX_DELAY_MINUTES - MIN_DELAY_MINUTES + 1));
        return { persona, delay };
    }).sort((a, b) => a.delay - b.delay);

    if (personaDelays.length > 0) {
        personaDelays[0].delay = Math.min(personaDelays[0].delay, FIRST_COMMENT_MAX_MINUTES);
    }

    const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
    const commentTargetUrl = `https://${LOCATION}-${project}.cloudfunctions.net/generateAICommentV1`;

    const commentResults = await Promise.allSettled(
        personaDelays.map(({ persona, delay: delayMinutes }) => {
            const scheduleTime = new Date(Date.now() + delayMinutes * 60 * 1000);
            const idempotencyKey = generateAICommentId(postId, persona.id);

            return scheduleHttpTask({
                queue: QUEUE_NAME,
                url: commentTargetUrl,
                payload: {
                    postId,
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
                    mediaDescriptions,
                    isCirclePost,
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

    let commentCreated = 0;
    let commentDuplicates = 0;
    let commentFailed = 0;
    commentResults.forEach((result) => {
        if (result.status === "fulfilled") {
            const outcome = result.value.result;
            if (outcome === "duplicate_skipped") {
                commentDuplicates++;
            } else {
                commentCreated++;
            }
        } else {
            commentFailed++;
            console.error("Error enqueuing comment task:", result.reason);
        }
    });

    const countHash = createHash("sha256").update(`${postId}-reaction-count`).digest();
    const reactionCount = Math.min((countHash[0] % 6) + 5, AI_PERSONAS.length);
    const POSITIVE_REACTIONS = ["love", "praise", "cheer", "sparkles", "clap", "thumbsup", "smile", "flower", "fire", "nice"];
    const commentPersonaIds = new Set(selectedPersonas.map((p) => p.id));
    const nonCommentPersonas = AI_PERSONAS.filter((p) => !commentPersonaIds.has(p.id));
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
    reactionResults.forEach((result) => {
        if (result.status === "fulfilled") {
            if (result.value.result === "duplicate_skipped") {
                reactionDuplicates++;
            } else {
                reactionCreated++;
            }
        } else {
            console.error("Reaction task enqueue failed:", result.reason);
        }
    });
    console.log(
        `schedulePublishedPostSideEffects complete: postId=${postId} ` +
        `comments={created:${commentCreated}, duplicates:${commentDuplicates}, failed:${commentFailed}} ` +
        `reactions={created:${reactionCreated}, duplicates:${reactionDuplicates}, failed:${reactionResults.length - reactionCreated - reactionDuplicates}}`
    );
}
