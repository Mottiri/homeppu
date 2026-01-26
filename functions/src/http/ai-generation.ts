/**
 * AI生成系のHTTP関数
 * Phase 5/7: index.ts から分離
 */

import * as functionsV1 from "firebase-functions/v1";
import { GoogleGenerativeAI } from "@google/generative-ai";

import { AIProviderFactory } from "../ai/provider";
import { AI_MODELS, LOCATION } from "../config/constants";
import { geminiApiKey, openaiApiKey } from "../config/secrets";
import { db, FieldValue, Timestamp } from "../helpers/firebase";
import {
    Gender,
    AgeGroup,
    PERSONALITIES,
    PRAISE_STYLES,
    AI_PERSONAS,
    getSystemPrompt,
    getCircleSystemPrompt,
} from "../ai/personas";
import { getPostGenerationPrompt } from "../ai/prompts/post-generation";

/**
 * AIProviderFactoryを作成するヘルパー関数
 * 関数内でSecretにアクセスし、ファクトリーを返す
 */
function createAIProviderFactory(): AIProviderFactory {
    const geminiKey = geminiApiKey.value() || "";
    const openaiKey = openaiApiKey.value() || "";
    return new AIProviderFactory(geminiKey, openaiKey);
}

// AIの投稿テンプレート（職業・性格に応じた内容を動的に生成するための基本パターン）
// executeAIPostGeneration で使用
const POST_TEMPLATES_BY_OCCUPATION: Record<string, string[]> = {
    college_student: [
        "今日のレポート、なんとか終わった！期限ギリギリだったけど頑張った",
        "サークルの活動楽しかった！いい仲間がいるって幸せだな",
        "テスト勉強中...集中力が切れてきたけどもうひと踏ん張り！",
        "新しいカフェ発見した！勉強する場所増えて嬉しい",
        "バイト終わり！今日も忙しかったけど達成感ある",
    ],
    sales: [
        "今月の目標達成！チームのみんなのおかげ！",
        "新しいお客様と良い関係を築けた気がする",
        "プレゼン資料作り終わった...明日の商談頑張る",
        "先輩からのアドバイスで気づきがあった",
        "今日は契約取れた！嬉しい！！",
    ],
    engineer: [
        "新機能リリースできた！ユーザーの反応楽しみ",
        "バグ直した...原因見つけるまで長かったけど達成感",
        "コードレビューで学びがあった",
        "新しい技術試してみた。面白い",
        "今日のタスク全部終わった！明日も頑張ろ",
    ],
    nurse: [
        "患者さんから「ありがとう」って言われた...元気もらえる",
        "夜勤明け！今日もみんな無事で何より",
        "新人さんのフォローしてたら自分も勉強になった",
        "忙しかったけど、チームワークで乗り越えた",
        "久しぶりの連休！ゆっくり休もう",
    ],
    designer: [
        "デザイン採用された！嬉しい！",
        "クライアントさんに喜んでもらえた",
        "新しいツール使ってみたら作業効率上がった",
        "今日のデザイン、いい感じにできた気がする",
        "展示会で刺激もらった！創作意欲湧いてきた",
    ],
    teacher: [
        "生徒たちの成長を感じた一日だった",
        "授業準備完了！明日も頑張ろう",
        "保護者さんとの面談、いい話ができた",
        "テストの採点終わった！みんな頑張ってた",
        "今日は生徒たちと楽しく過ごせた",
    ],
    freelancer: [
        "納品完了！クライアントさんに喜んでもらえた",
        "新しい案件の依頼きた！ありがたい",
        "確定申告の準備進めた。少しずつだけど進んでる",
        "オンラインミーティング上手くいった",
        "今日は作業捗った！この調子で頑張る",
    ],
    homemaker: [
        "今日の夕飯、家族に好評だった",
        "大掃除完了！スッキリ！",
        "子どもの成長を感じた一日",
        "新しいレシピに挑戦してみた",
        "午前中に用事を全部終わらせた！えらい！",
    ],
};

/**
 * Cloud Tasks から呼び出される AI コメント生成関数 (v1)
 * v1を使用することでURLを固定化: https://asia-northeast1-positive-sns.cloudfunctions.net/generateAICommentV1
 */
export const generateAICommentV1 = functionsV1.region(LOCATION).runWith({
    secrets: ["GEMINI_API_KEY", "OPENAI_API_KEY"],
    timeoutSeconds: 60,
}).https.onRequest(async (request, response) => {
    // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
    const { verifyCloudTasksRequest } = await import("../helpers/cloud-tasks-auth");
    if (!await verifyCloudTasksRequest(request, "generateAICommentV1")) {
        response.status(403).send("Unauthorized");
        return;
    }

    try {
        const {
            postId,
            postContent,
            userDisplayName,
            personaId,
            personaName,
            personaGender,
            personaAgeGroup,
            personaOccupation,
            personaPersonality,
            personaPraiseStyle,
            personaAvatarIndex,
            mediaDescriptions,
            isCirclePost,
            circleName,
            circleDescription,
            circleGoal,
            circleRules,
        } = request.body;

        console.log(`Processing AI comment task for ${personaName} on post ${postId}`);

        // AIProviderFactory経由でテキスト生成
        const aiFactory = createAIProviderFactory();

        // ペルソナを再構築
        // まずAI_PERSONASから検索、見つからなければペイロードから構築
        let persona = AI_PERSONAS.find(p => p.id === personaId);

        if (!persona) {
            // サークルAIの場合、ペイロードからペルソナを構築
            console.log(`Persona ${personaId} not in AI_PERSONAS, using payload data`);

            // ペイロードに personality が含まれていればそれを使用
            // 含まれていなければデフォルトを使用
            const defaultPersonality = PERSONALITIES.female[0]; // 優しい系をデフォルトに

            persona = {
                id: personaId,
                name: personaName,
                namePrefixId: "",
                nameSuffixId: "",
                gender: (personaGender || "female") as Gender,
                ageGroup: (personaAgeGroup || "twenties") as AgeGroup,
                occupation: personaOccupation || { id: "student", name: "頑張り中", bio: "" },
                personality: personaPersonality || defaultPersonality,
                praiseStyle: personaPraiseStyle || PRAISE_STYLES[0],
                avatarIndex: personaAvatarIndex || 0,
                bio: "",
            };
        }

        // プロンプト構築
        const mediaContext = mediaDescriptions && mediaDescriptions.length > 0
            ? `\n\n【添付メディアの内容】\n${mediaDescriptions.join("\n")}`
            : "";

        // 既存のAIコメントを取得（重複回避のため）
        // 重要: コメントはトップレベルの comments コレクションに保存されている
        const postRef = db.collection("posts").doc(postId);
        let existingCommentsContext = "";
        try {
            console.log(`[DUPLICATE CHECK] Fetching existing AI comments for post: ${postId}`);

            // トップレベルのcommentsコレクションからpostIdでフィルタ
            const existingCommentsSnapshot = await db.collection("comments")
                .where("postId", "==", postId)
                .where("isAI", "==", true)
                .orderBy("createdAt", "asc")
                .limit(10)
                .get();

            console.log(`[DUPLICATE CHECK] Query returned ${existingCommentsSnapshot.size} documents`);

            if (!existingCommentsSnapshot.empty) {
                const existingComments = existingCommentsSnapshot.docs.map((doc, index) => {
                    const data = doc.data();
                    const commentText = `<comment_${index + 1}>${data.content}</comment_${index + 1}>`;
                    console.log(`[DUPLICATE CHECK] Found: ${data.content?.substring(0, 50)}...`);
                    return commentText;
                });
                existingCommentsContext = `
<existing_comments>
<instruction>以下は既に投稿されているコメントです。これらと同じフレーズ・表現は使用せず、異なる言い回しで返信してください。</instruction>
${existingComments.join("\n")}
</existing_comments>
`;
                console.log(`[DUPLICATE CHECK] Added ${existingComments.length} comments to context for diversity`);
            } else {
                console.log(`[DUPLICATE CHECK] No existing AI comments found for post ${postId}`);
            }
        } catch (error) {
            console.error("[DUPLICATE CHECK] Error fetching existing comments:", error);
            console.log("Proceeding without diversity check");
        }

        // サークル投稿かどうかでプロンプトを分岐
        let prompt: string;
        if (isCirclePost) {
            // サークル投稿: 専用プロンプトを使用
            prompt = getCircleSystemPrompt(
                persona,
                userDisplayName,
                circleName,
                circleDescription,
                postContent || "(テキストなし)",
                circleGoal,
                circleRules
            );
            // メディアコンテキストと既存コメントコンテキストを追加
            const additionalContext = existingCommentsContext + mediaContext;
            if (additionalContext) {
                // 新しいプロンプト構造では「---」の前に挿入
                prompt = prompt.replace(
                    "---\n**上記の投稿に対し",
                    additionalContext + "\n\n---\n**上記の投稿に対し"
                );
            }
        } else {
            // 一般投稿: 新しいプロンプト構造を使用
            const basePrompt = getSystemPrompt(persona, userDisplayName);
            const mediaNote = mediaDescriptions && mediaDescriptions.length > 0
                ? "\n\n# Additional Context (メディア情報)\n添付されたメディア（画像・動画）の内容も考慮して、具体的に褒めてください。"
                : "";

            prompt = `
${basePrompt}

# Input Data (今回の投稿)

<poster_name>${userDisplayName}</poster_name>
<post_content>
${postContent || "(テキストなし)"}
</post_content>
${mediaContext}
${existingCommentsContext}${mediaNote}

---
**上記の投稿に対し、思考プロセスや前置きを一切含めず、返信コメントのみを出力してください。**
`;
        }

        // プロンプト全文をログ出力（デバッグ用）
        console.log(`[AI PROMPT DEBUG] ===== PROMPT START =====`);
        console.log(prompt);
        console.log(`[AI PROMPT DEBUG] ===== PROMPT END =====`);

        const aiResult = await aiFactory.generateText(prompt);
        const commentText = aiResult.text?.trim();
        console.log(`AI comment generated by ${aiResult.provider}${aiResult.usedFallback ? " (fallback)" : ""}`);

        if (!commentText || commentText === "SKIP_COMMENT") {
            console.log(`Skipping comment: ${commentText || "Empty"}`);
            response.status(200).send("Comment skipped");
            return;
        }

        // リアクションもランダムで送信 (ポジティブなものから選択)
        const POSITIVE_REACTIONS = ["love", "praise", "cheer", "sparkles", "clap", "thumbsup", "smile"];
        const reactionType = POSITIVE_REACTIONS[Math.floor(Math.random() * POSITIVE_REACTIONS.length)];

        // 投稿が存在するか確認（Cloud Tasksの遅延実行中に削除された可能性）
        // postRefは既に上で宣言済み
        const postDoc = await postRef.get();
        if (!postDoc.exists) {
            console.warn(`Post ${postId} not found, skipping AI comment`);
            response.status(200).send("Post not found, skipping");
            return;
        }

        // バッチ書き込みで一括処理
        const batch = db.batch();

        // 1. コメント保存
        const commentRef = db.collection("comments").doc();
        batch.set(commentRef, {
            postId: postId,
            userId: persona.id,
            userDisplayName: persona.name,
            userAvatarIndex: persona.avatarIndex,
            isAI: true,
            content: commentText,
            createdAt: FieldValue.serverTimestamp(),
        });

        // 2. リアクション保存 (通知トリガー用)
        const reactionRef = db.collection("reactions").doc();
        batch.set(reactionRef, {
            postId: postId,
            userId: persona.id,
            userDisplayName: persona.name,
            reactionType: reactionType,
            createdAt: FieldValue.serverTimestamp(),
        });

        // 3. 投稿のリアクションカウント・コメント数を更新
        batch.update(postRef, {
            [`reactions.${reactionType}`]: FieldValue.increment(1),
            commentCount: FieldValue.increment(1),
        });

        await batch.commit();

        console.log(`AI comment and reaction posted: ${persona.name} (Reaction: ${reactionType})`);
        response.status(200).send("Comment and reaction posted successfully");

    } catch (error) {
        console.error("Error in generateAIComment:", error);
        response.status(500).send("Internal Server Error");
    }
});

/**
 * Cloud Tasks から呼び出される AI リアクション生成関数 (v1)
 * 単体リアクション用
 */
export const generateAIReactionV1 = functionsV1.region(LOCATION).https.onRequest(async (request, response) => {
    // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
    const { verifyCloudTasksRequest } = await import("../helpers/cloud-tasks-auth");
    if (!await verifyCloudTasksRequest(request, "generateAIReactionV1")) {
        response.status(403).send("Unauthorized");
        return;
    }

    try {
        const { postId, personaId, personaName, reactionType } = request.body;

        console.log(`Processing AI reaction task for ${personaName} on post ${postId} (Type: ${reactionType})`);

        const persona = AI_PERSONAS.find(p => p.id === personaId);
        if (!persona) {
            response.status(400).send("Persona not found");
            return;
        }

        // 重複チェック: この AI が既にこの投稿にリアクションしているか確認
        const existingReaction = await db.collection("reactions")
            .where("postId", "==", postId)
            .where("userId", "==", persona.id)
            .limit(1)
            .get();

        if (!existingReaction.empty) {
            console.log(`Skipping duplicate reaction: ${persona.name} already reacted to post ${postId}`);
            response.status(200).send("Reaction already exists, skipped");
            return;
        }

        const batch = db.batch();

        // 1. リアクション保存
        const reactionRef = db.collection("reactions").doc();
        batch.set(reactionRef, {
            postId: postId,
            userId: persona.id,
            userDisplayName: persona.name,
            reactionType: reactionType,
            createdAt: FieldValue.serverTimestamp(),
        });

        // 2. 投稿のリアクションカウント更新
        const postRef = db.collection("posts").doc(postId);
        batch.update(postRef, {
            [`reactions.${reactionType}`]: FieldValue.increment(1),
        });

        await batch.commit();

        console.log(`AI reaction posted: ${persona.name} -> ${reactionType}`);
        response.status(200).send("Reaction posted successfully");

    } catch (error) {
        console.error("Error in generateAIReaction:", error);
        response.status(500).send("Internal Server Error");
    }
});

/**
 * Cloud Tasks から呼び出される AI 投稿生成関数 (Worker)
 */
export const executeAIPostGeneration = functionsV1.region(LOCATION).runWith({
    secrets: ["GEMINI_API_KEY"],
    timeoutSeconds: 300,
    memory: "1GB",
}).https.onRequest(async (request, response) => {
    // Cloud Tasks からのリクエストを OIDC トークンで検証（動的インポート）
    const { verifyCloudTasksRequest } = await import("../helpers/cloud-tasks-auth");
    if (!await verifyCloudTasksRequest(request, "executeAIPostGeneration")) {
        response.status(403).send("Unauthorized");
        return;
    }

    try {
        const { postId, personaId, postTimeIso } = request.body;
        console.log(`Executing AI post generation for ${personaId}`);

        const apiKey = geminiApiKey.value();
        if (!apiKey) throw new Error("GEMINI_API_KEY is not set");

        const genAI = new GoogleGenerativeAI(apiKey);
        const model = genAI.getGenerativeModel({ model: AI_MODELS.GEMINI_DEFAULT });

        // ペルソナ取得
        const persona = AI_PERSONAS.find((p) => p.id === personaId);
        if (!persona) {
            console.error(`Persona not found: ${personaId}`);
            response.status(400).send("Persona not found");
            return;
        }

        // 職業に応じたテンプレートを取得（フォールバック用）
        const templates = POST_TEMPLATES_BY_OCCUPATION[persona.occupation.id] || [];

        // 現在時刻
        const now = new Date();
        const hours = now.getHours();

        // プロンプト生成 (努力・達成・日常の頑張りをテーマに)
        const prompt = getPostGenerationPrompt(persona, hours);

        const result = await model.generateContent(prompt);
        let content = result.response.text()?.trim();

        // 生成失敗時はテンプレートからランダム選択
        if (!content && templates.length > 0) {
            content = templates[Math.floor(Math.random() * templates.length)];
        }

        if (!content) {
            throw new Error("Failed to generate content");
        }

        // 投稿作成
        const postRef = db.collection("posts").doc(postId);
        const reactions = {
            love: Math.floor(Math.random() * 5),
            praise: Math.floor(Math.random() * 5),
            cheer: Math.floor(Math.random() * 5),
            empathy: Math.floor(Math.random() * 5),
        };

        // postTimeIsoがあればその時間、なければ現在時刻
        const createdAt = postTimeIso
            ? Timestamp.fromDate(new Date(postTimeIso))
            : FieldValue.serverTimestamp();

        await postRef.set({
            userId: persona.id,
            userDisplayName: persona.name,
            userAvatarIndex: persona.avatarIndex,
            content: content,
            postMode: "mix", // 公開範囲
            circleId: null, // タイムラインのクエリ(where circleId isNull)にマッチさせるため明示的にnullを設定
            createdAt: createdAt,
            reactions: reactions,
            commentCount: 0,
            isVisible: true,
        });

        // ユーザーの統計更新
        const totalReactions = Object.values(reactions).reduce((a, b) => a + b, 0);
        await db.collection("users").doc(persona.id).update({
            totalPosts: FieldValue.increment(1),
            totalPraises: FieldValue.increment(totalReactions),
        });

        console.log(`Successfully created post for ${persona.name}: ${content}`);
        response.status(200).json({ success: true, postId: postRef.id });
    } catch (error) {
        console.error("Error in executeAIPostGeneration:", error);
        response.status(500).send("Internal Server Error");
    }
});
