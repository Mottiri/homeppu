import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as admin from "firebase-admin";
import {GoogleGenerativeAI} from "@google/generative-ai";

admin.initializeApp();
const db = admin.firestore();

// ===============================================
// 徳システム設定
// ===============================================
const VIRTUE_CONFIG = {
  initial: 100,           // 初期徳ポイント
  maxDaily: 50,           // 1日の最大獲得量
  banThreshold: 0,        // BAN閾値
  lossPerNegative: 15,    // ネガティブ発言1回あたりの減少
  lossPerReport: 20,      // 通報1回あたりの減少
  gainPerPraise: 5,       // 称賛1回あたりの増加
  warningThreshold: 30,   // 警告表示閾値
};

// ネガティブ判定のカテゴリ
type NegativeCategory =
  | "harassment"      // 誹謗中傷
  | "hate_speech"     // ヘイトスピーチ
  | "profanity"       // 不適切な言葉
  | "self_harm"       // 自傷行為の助長
  | "spam"            // スパム
  | "none";           // 問題なし

interface ModerationResult {
  isNegative: boolean;
  category: NegativeCategory;
  confidence: number;    // 0-1の確信度
  reason: string;        // 判定理由（ユーザーへの説明用）
  suggestion: string;    // 改善提案
}

// APIキーをSecretsから取得
const geminiApiKey = defineSecret("GEMINI_API_KEY");

// AIペルソナ定義（より人間らしく）
const AI_PERSONAS = [
  {
    id: "ai_yuuki",
    name: "ゆうき",
    avatarIndex: 0,
    bio: "大学3年/心理学専攻📚 カフェ巡りとバスケが趣味🏀 毎日ポジティブに！✨",
    personality: "明るく元気な大学生。絵文字を多用する。",
    speechStyle: "カジュアルでフレンドリー。「〜だね！」「すごい！」をよく使う。絵文字を2〜3個使う。",
    effort: "心理学の勉強とバスケ部の活動",
  },
  {
    id: "ai_sakura",
    name: "さくら",
    avatarIndex: 1,
    bio: "都内でWebデザイナーしてます🌸 休日は読書と料理。最近ヨガ始めました",
    personality: "優しくて穏やかな社会人女性。共感力が高い。",
    speechStyle: "丁寧だけど堅くない。「わかるよ〜」「素敵だね」をよく使う。絵文字は控えめに1個程度。",
    effort: "Webデザインのスキルアップとヨガ",
  },
  {
    id: "ai_kenta",
    name: "けんた",
    avatarIndex: 2,
    bio: "IT企業で営業やってます！週末はジムで筋トレ💪 目指せベンチプレス100kg！",
    personality: "熱血で応援好きな社会人男性。ポジティブ思考。",
    speechStyle: "励まし上手。「がんばってるね！」「最高！」をよく使う。「！」を多用する。",
    effort: "営業成績トップと筋トレ",
  },
  {
    id: "ai_mio",
    name: "みお",
    avatarIndex: 3,
    bio: "金融系で働いています。趣味は美術館巡りと紅茶。資格の勉強中です。",
    personality: "知的で落ち着いた大人の女性。的確に褒める。",
    speechStyle: "丁寧語を基本とする。具体的に褒める。絵文字はほぼ使わない。",
    effort: "ファイナンシャルプランナーの資格取得",
  },
  {
    id: "ai_souta",
    name: "そうた",
    avatarIndex: 4,
    bio: "ゲーム配信してる22歳🎮 深夜ラーメンがやめられないw 推しはVtuber",
    personality: "面白くて明るい若者。ノリが良い。",
    speechStyle: "超フランク。「まじで」「やば」「草」「神」をよく使う。wや草を語尾に付ける。",
    effort: "ゲーム配信のフォロワー増やす",
  },
  {
    id: "ai_hana",
    name: "はな",
    avatarIndex: 5,
    bio: "保育士5年目🌷 子どもたちに元気もらってます。お菓子作りが癒し時間",
    personality: "癒し系で優しいお姉さん。包容力がある。",
    speechStyle: "温かみのある言葉。「えらいね〜」「すごいなぁ」をよく使う。ひらがな多め。",
    effort: "保育の仕事とお菓子作り",
  },
];

/**
 * システムプロンプトを生成
 */
function getSystemPrompt(
  persona: typeof AI_PERSONAS[0],
  posterName: string
): string {
  return `
あなたは「ほめっぷ」というSNSのユーザー「${persona.name}」です。
性格: ${persona.personality}
話し方: ${persona.speechStyle}

【投稿者の情報】
投稿者の名前: ${posterName}

【重要なルール】
1. 投稿者「${posterName}」さんを褒めてください（あなた自身「${persona.name}」ではありません）
2. 投稿内容を読んで、${posterName}さんの努力や良いところを具体的に称賛してください
3. ネガティブなことは一切言わないでください
4. 短めの返信（50〜100文字程度）にしてください
5. 自然な日本語で、人間らしく返信してください
6. 「AI」「ボット」という言葉は使わないでください
7. 相手の気持ちに寄り添い、共感を示してください
8. 投稿者の名前を呼ぶ場合は「${posterName}さん」と呼んでください
`;
}

/**
 * 新規投稿時にAIコメントを生成するトリガー
 */
export const onPostCreated = onDocumentCreated(
  {
    document: "posts/{postId}",
    region: "asia-northeast1",
    secrets: [geminiApiKey],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      console.log("No data associated with the event");
      return;
    }

    const postData = snap.data();
    const postId = event.params.postId;

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
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});

    // ランダムに1〜3人のAIを選択
    const commentCount = Math.floor(Math.random() * 3) + 1;
    const shuffledPersonas = [...AI_PERSONAS]
      .sort(() => Math.random() - 0.5)
      .slice(0, commentCount);

    const batch = db.batch();
    let totalComments = 0;

    // 投稿者の名前を取得
    const posterName = postData.userDisplayName || "投稿者";

    for (const persona of shuffledPersonas) {
      try {
        const prompt = `
${getSystemPrompt(persona, posterName)}

【${posterName}さんの投稿】
${postData.content}

【あなた（${persona.name}）の返信】
`;

        const result = await model.generateContent(prompt);
        const commentText = result.response.text()?.trim();

        if (!commentText) continue;

        // ランダムな遅延時間（1〜30分後）をシミュレート
        const delayMinutes = Math.floor(Math.random() * 29) + 1;
        const commentTime = new Date(Date.now() + delayMinutes * 60 * 1000);

        const commentRef = db.collection("comments").doc();
        batch.set(commentRef, {
          postId: postId,
          userId: persona.id,
          userDisplayName: persona.name,
          userAvatarIndex: persona.avatarIndex,
          isAI: true,
          content: commentText,
          createdAt: admin.firestore.Timestamp.fromDate(commentTime),
        });

        totalComments++;
        console.log(`AI comment created: ${persona.name} (delayed ${delayMinutes}m)`);
      } catch (error) {
        console.error(`Error generating comment for ${persona.name}:`, error);
      }
    }

    // コメント数を更新
    if (totalComments > 0) {
      batch.update(snap.ref, {
        commentCount: admin.firestore.FieldValue.increment(totalComments),
      });
      await batch.commit();
    }
  }
);

// AIの投稿テンプレート（頑張っていることに沿った内容）
const AI_POST_TEMPLATES: Record<string, string[]> = {
  ai_yuuki: [
    "心理学のテスト終わった〜！！めっちゃ勉強したから手応えあり✨✨ 今日はご褒美にカフェ行く🎵",
    "バスケの練習きつかったけど、シュート決まると最高に気持ちいい🏀💪",
    "新しくできたカフェ行ってきた☕✨ ラテアートかわいすぎて写真撮りまくったww",
    "明日レポート提出だけど、まだ手つけてない😇 今から頑張る...！！",
    "バスケ部の先輩にフォーム褒められた〜！！嬉しすぎる😭✨ 練習頑張ってよかった！！",
  ],
  ai_sakura: [
    "今日は新しいデザインツールに挑戦してみた。難しいけど、できることが増えると嬉しいな",
    "朝ヨガ続けて3週間。少しずつ体が柔らかくなってきた気がする🧘‍♀️",
    "クライアントさんに「素敵なデザインですね」って言ってもらえた。この仕事やっててよかった",
    "休日は読書三昧。窓辺で紅茶を飲みながら本を読む時間が一番好き",
    "新しいレシピに挑戦。見た目はいまいちだったけど、味は美味しくできた🍳",
  ],
  ai_kenta: [
    "ベンチプレス85kg上がった！！100kgまであと少し！絶対達成するぞ💪🔥",
    "今月の営業目標達成！！チームのみんなのおかげ！来月はもっと上を目指す！！",
    "朝5時起きでジム行ってから出社！この習慣続けて半年！めっちゃ調子いい！",
    "後輩の商談同行した！成長してて嬉しかったな〜！俺も負けてられない！",
    "週末は久しぶりに山登り！頂上からの景色最高だった！疲れも吹っ飛ぶ！",
  ],
  ai_mio: [
    "FPの勉強、今日は投資信託の章を終えました。複利の力は本当にすごいですね。",
    "仕事帰りに美術館へ。モネの睡蓮を見ていると、心が穏やかになります。",
    "資格の模擬試験を受けてみました。まだまだ課題はありますが、着実に前進している実感があります。",
    "ダージリンのファーストフラッシュを手に入れました。香りが華やかで、贅沢な時間です。",
    "今日学んだ金融知識を、友人にわかりやすく説明できました。人に教えることで自分の理解も深まりますね。",
  ],
  ai_souta: [
    "今日の配信5時間やったわww 見てくれた人ありがとう〜！フォロワー増えてきて嬉しい",
    "新作ゲームのレビュー動画上げたら結構伸びてる！やっぱ発売日に上げるの大事だな",
    "深夜3時のラーメンうますぎて草 ダイエット？知らない子ですね",
    "推しのVtuberの新衣装やばすぎるwww 限界化してる",
    "配信機材新しくしたら画質めっちゃ良くなった！投資した甲斐あったわ",
  ],
  ai_hana: [
    "今日は子どもたちとお絵描きした🎨 みんなの発想力ってすごいなぁ。元気もらえる",
    "シフォンケーキ焼いてみた🍰 ふわふわにできて満足。誰かに食べてほしいな",
    "園児さんが「せんせいだいすき」って言ってくれた。この仕事やっててよかった😢💕",
    "新しいクッキーのレシピ試してみたよ🍪 ちょっと焦げちゃったけど、味は美味しくできた",
    "今日はゆっくりお風呂に浸かって、明日も頑張ろう。みんなもお疲れ様だよ🌙",
  ],
};

/**
 * AIアカウントを初期化する関数（管理者用）
 * 既存のアカウントも更新します
 */
export const initializeAIAccounts = onCall(
  {region: "asia-northeast1"},
  async () => {
    let createdCount = 0;
    let updatedCount = 0;

    for (const persona of AI_PERSONAS) {
      const docRef = db.collection("users").doc(persona.id);
      const doc = await docRef.get();

      const userData = {
        email: `${persona.name}@ai.homeppu.local`,
        displayName: persona.name,
        bio: persona.bio,
        avatarIndex: persona.avatarIndex,
        postMode: "ai",
        virtue: 100,
        isAI: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        isBanned: false,
      };

      if (!doc.exists) {
        await docRef.set({
          ...userData,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          totalPosts: 0,
          totalPraises: 0,
          following: [],
          followers: [],
          followingCount: 0,
          followersCount: 0,
        });
        createdCount++;
        console.log(`Created AI account: ${persona.name}`);
      } else {
        // 既存アカウントのbioとavatarIndexを更新
        await docRef.update({
          bio: persona.bio,
          avatarIndex: persona.avatarIndex,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        updatedCount++;
        console.log(`Updated AI account: ${persona.name}`);
      }
    }

    return {
      success: true,
      message: "AIアカウントを作成/更新しました",
      created: createdCount,
      updated: updatedCount,
    };
  }
);

/**
 * AIアカウントの過去投稿を生成する関数（管理者用）
 */
export const generateAIPosts = onCall(
  {region: "asia-northeast1", secrets: [geminiApiKey]},
  async () => {
    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      return {success: false, message: "GEMINI_API_KEY is not set"};
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});

    let totalPosts = 0;
    let totalComments = 0;
    let totalReactions = 0;

    for (const persona of AI_PERSONAS) {
      // 既存の投稿数をチェック
      const existingPosts = await db
        .collection("posts")
        .where("userId", "==", persona.id)
        .get();

      if (existingPosts.size >= 5) {
        console.log(`${persona.name} already has ${existingPosts.size} posts, skipping`);
        continue;
      }

      // 投稿テンプレートを取得
      const templates = AI_POST_TEMPLATES[persona.id] || [];

      // 過去1〜7日間にランダムな時間で投稿を作成
      for (let i = 0; i < templates.length; i++) {
        const daysAgo = Math.floor(Math.random() * 7) + 1;
        const hoursAgo = Math.floor(Math.random() * 24);
        const postTime = new Date(
          Date.now() - daysAgo * 24 * 60 * 60 * 1000 - hoursAgo * 60 * 60 * 1000
        );

        // 投稿を作成
        const postRef = db.collection("posts").doc();
        const reactions = {
          love: Math.floor(Math.random() * 10),
          praise: Math.floor(Math.random() * 8),
          cheer: Math.floor(Math.random() * 6),
          empathy: Math.floor(Math.random() * 5),
        };

        await postRef.set({
          userId: persona.id,
          userDisplayName: persona.name,
          userAvatarIndex: persona.avatarIndex,
          content: templates[i],
          postMode: "mix",
          createdAt: admin.firestore.Timestamp.fromDate(postTime),
          reactions: reactions,
          commentCount: 0,
          isVisible: true,
        });

        totalPosts++;
        totalReactions += Object.values(reactions).reduce((a, b) => a + b, 0);

        // 他のAIからコメントを生成（1〜2件）
        const commentCount = Math.floor(Math.random() * 2) + 1;
        const otherPersonas = AI_PERSONAS.filter((p) => p.id !== persona.id)
          .sort(() => Math.random() - 0.5)
          .slice(0, commentCount);

        for (const commenter of otherPersonas) {
          try {
            const prompt = `
あなたは「ほめっぷ」というSNSのユーザー「${commenter.name}」です。
性格: ${commenter.personality}
話し方: ${commenter.speechStyle}

【投稿者の情報】
投稿者の名前: ${persona.name}

【重要なルール】
1. ${persona.name}さんを褒めてください
2. 短めの返信（30〜60文字程度）にしてください
3. 自然な日本語で返信してください
4. 「AI」「ボット」という言葉は使わないでください

【${persona.name}さんの投稿】
${templates[i]}

【あなた（${commenter.name}）の返信】
`;

            const result = await model.generateContent(prompt);
            const commentText = result.response.text()?.trim();

            if (commentText) {
              const commentTime = new Date(
                postTime.getTime() + Math.floor(Math.random() * 60) * 60 * 1000
              );

              await db.collection("comments").add({
                postId: postRef.id,
                userId: commenter.id,
                userDisplayName: commenter.name,
                userAvatarIndex: commenter.avatarIndex,
                isAI: true,
                content: commentText,
                createdAt: admin.firestore.Timestamp.fromDate(commentTime),
              });

              totalComments++;

              // 投稿のコメント数を更新
              await postRef.update({
                commentCount: admin.firestore.FieldValue.increment(1),
              });
            }
          } catch (error) {
            console.error(`Error generating comment:`, error);
          }
        }
      }

      // ユーザーの投稿数を更新
      await db.collection("users").doc(persona.id).update({
        totalPosts: admin.firestore.FieldValue.increment(templates.length),
        totalPraises: admin.firestore.FieldValue.increment(
          Math.floor(Math.random() * 20)
        ),
      });
    }

    return {
      success: true,
      message: "AI投稿を生成しました",
      posts: totalPosts,
      comments: totalComments,
      reactions: totalReactions,
    };
  }
);

/**
 * レート制限付きの投稿作成（スパム対策）
 */
export const createPostWithRateLimit = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "ログインが必要です"
      );
    }

    const userId = request.auth.uid;
    const data = request.data;

    // レート制限チェック（1分間に5投稿まで）
    const oneMinuteAgo = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 60000)
    );
    const recentPosts = await db
      .collection("posts")
      .where("userId", "==", userId)
      .where("createdAt", ">", oneMinuteAgo)
      .get();

    if (recentPosts.size >= 5) {
      throw new HttpsError(
        "resource-exhausted",
        "投稿が多すぎるよ！少し待ってからまた投稿してね"
      );
    }

    // 投稿を作成
    const postRef = db.collection("posts").doc();
    await postRef.set({
      ...data,
      userId: userId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      reactions: {love: 0, praise: 0, cheer: 0, empathy: 0},
      commentCount: 0,
      isVisible: true,
    });

    // ユーザーの投稿数を更新
    await db.collection("users").doc(userId).update({
      totalPosts: admin.firestore.FieldValue.increment(1),
    });

    return {success: true, postId: postRef.id};
  }
);

// ===============================================
// コンテンツモデレーション機能
// ===============================================

/**
 * コンテンツをモデレーションする関数
 * Gemini AIでネガティブ発言を検出
 */
export const moderateContent = onCall(
  {region: "asia-northeast1", secrets: [geminiApiKey]},
  async (request): Promise<ModerationResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const {content} = request.data;
    if (!content || typeof content !== "string") {
      throw new HttpsError("invalid-argument", "コンテンツが必要です");
    }

    const apiKey = geminiApiKey.value();
    if (!apiKey) {
      console.error("GEMINI_API_KEY is not set");
      // APIキーがない場合はモデレーションをスキップ
      return {
        isNegative: false,
        category: "none",
        confidence: 0,
        reason: "",
        suggestion: "",
      };
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});

    const prompt = `
あなたはSNS「ほめっぷ」のコンテンツモデレーターです。
「ほめっぷ」は「世界一優しいSNS」を目指しています。

以下の投稿内容を分析して、「他者への攻撃」があるかどうか判定してください。

【ブロック対象（isNegative: true）】
- harassment: 他者への誹謗中傷、人格攻撃、悪口
- hate_speech: 差別、ヘイトスピーチ、特定の属性への攻撃
- profanity: 他者への暴言、罵倒
- self_harm: 自傷行為の助長（※これは安全上ブロック）
- spam: スパム、宣伝

【許可する内容（isNegative: false）】
- 個人の感情表現：「悲しい」「辛い」「落ち込んだ」「疲れた」「しんどい」
- 自分自身への愚痴：「自分ダメだな」「失敗した」「うまくいかない」
- 日常の不満：「雨だ〜」「電車遅れた」「眠い」
- 頑張りや努力の共有
- 共感を求める投稿

【重要な判定基準】
⚠️ 「他者を攻撃しているか」が最重要ポイントです
⚠️ 自分の気持ちを素直に表現することは許可します
⚠️ 誰かを傷つける意図がない限り「none」と判定してください

【投稿内容】
${content}

【回答形式】
必ず以下のJSON形式で回答してください。他の文字は含めないでください。
{
  "isNegative": true または false,
  "category": "harassment" | "hate_speech" | "profanity" | "self_harm" | "spam" | "none",
  "confidence": 0から1の数値,
  "reason": "判定理由（ユーザーに見せる優しい説明）",
  "suggestion": "より良い表現の提案"
}
`;

    try {
      const result = await model.generateContent(prompt);
      const responseText = result.response.text().trim();

      // JSONを抽出（マークダウンコードブロックを考慮）
      let jsonText = responseText;
      const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
      if (jsonMatch) {
        jsonText = jsonMatch[1];
      }

      const parsed = JSON.parse(jsonText) as ModerationResult;

      // 結果をログに記録
      console.log("Moderation result:", {
        content: content.substring(0, 50) + "...",
        result: parsed,
      });

      return parsed;
    } catch (error) {
      console.error("Moderation error:", error);
      // エラー時は安全側に倒す（投稿を許可）
      return {
        isNegative: false,
        category: "none",
        confidence: 0,
        reason: "",
        suggestion: "",
      };
    }
  }
);

/**
 * 徳ポイントを減少させる（ネガティブ発言検出時）
 */
async function decreaseVirtue(
  userId: string,
  reason: string,
  amount: number = VIRTUE_CONFIG.lossPerNegative
): Promise<{newVirtue: number; isBanned: boolean}> {
  const userRef = db.collection("users").doc(userId);
  const userDoc = await userRef.get();

  if (!userDoc.exists) {
    throw new Error("User not found");
  }

  const userData = userDoc.data()!;
  const currentVirtue = userData.virtue || VIRTUE_CONFIG.initial;
  const newVirtue = Math.max(0, currentVirtue - amount);
  const isBanned = newVirtue <= VIRTUE_CONFIG.banThreshold;

  // 徳ポイントを更新
  await userRef.update({
    virtue: newVirtue,
    isBanned: isBanned,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // 徳ポイント変動履歴を記録
  await db.collection("virtueHistory").add({
    userId: userId,
    change: -amount,
    reason: reason,
    newVirtue: newVirtue,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`Virtue decreased for ${userId}: ${currentVirtue} -> ${newVirtue}, banned: ${isBanned}`);

  return {newVirtue, isBanned};
}

/**
 * モデレーション付き投稿作成
 * ネガティブな内容は投稿を拒否し、徳を減少
 */
export const createPostWithModeration = onCall(
  {region: "asia-northeast1", secrets: [geminiApiKey]},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const {content, userDisplayName, userAvatarIndex, postMode, circleId} = request.data;

    // ユーザーがBANされているかチェック
    const userDoc = await db.collection("users").doc(userId).get();
    if (userDoc.exists && userDoc.data()?.isBanned) {
      throw new HttpsError(
        "permission-denied",
        "申し訳ありませんが、現在投稿できません。運営にお問い合わせください。"
      );
    }

    // コンテンツモデレーション
    const apiKey = geminiApiKey.value();
    if (apiKey) {
      const genAI = new GoogleGenerativeAI(apiKey);
      const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});

      const prompt = `
あなたはSNS「ほめっぷ」のコンテンツモデレーターです。
「ほめっぷ」は「世界一優しいSNS」を目指しています。

以下の投稿内容を分析して、「他者への攻撃」があるかどうか判定してください。

【ブロック対象（isNegative: true）】
- harassment: 他者への誹謗中傷、人格攻撃、悪口
- hate_speech: 差別、ヘイトスピーチ、特定の属性への攻撃
- profanity: 他者への暴言、罵倒
- self_harm: 自傷行為の助長（※これは安全上ブロック）
- spam: スパム、宣伝

【許可する内容（isNegative: false）】
- 個人の感情表現：「悲しい」「辛い」「落ち込んだ」「疲れた」「しんどい」
- 自分自身への愚痴：「自分ダメだな」「失敗した」「うまくいかない」
- 日常の不満：「雨だ〜」「電車遅れた」「眠い」
- 頑張りや努力の共有
- 共感を求める投稿

【重要な判定基準】
⚠️ 「他者を攻撃しているか」が最重要ポイントです
⚠️ 自分の気持ちを素直に表現することは許可します
⚠️ 誰かを傷つける意図がない限り「none」と判定してください

【投稿内容】
${content}

【回答形式】
必ず以下のJSON形式で回答してください。他の文字は含めないでください。
{
  "isNegative": true または false,
  "category": "harassment" | "hate_speech" | "profanity" | "self_harm" | "spam" | "none",
  "confidence": 0から1の数値,
  "reason": "判定理由（ユーザーに見せる優しい説明）",
  "suggestion": "より良い表現の提案"
}
`;

      try {
        const result = await model.generateContent(prompt);
        const responseText = result.response.text().trim();

        let jsonText = responseText;
        const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
        if (jsonMatch) {
          jsonText = jsonMatch[1];
        }

        const modResult = JSON.parse(jsonText) as ModerationResult;

        if (modResult.isNegative && modResult.confidence >= 0.7) {
          // 徳ポイントを減少
          const virtueResult = await decreaseVirtue(
            userId,
            `ネガティブ投稿検出: ${modResult.category}`,
            VIRTUE_CONFIG.lossPerNegative
          );

          // 投稿を記録（非表示として）
          await db.collection("moderatedContent").add({
            userId: userId,
            content: content,
            type: "post",
            category: modResult.category,
            confidence: modResult.confidence,
            reason: modResult.reason,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          throw new HttpsError(
            "invalid-argument",
            `${modResult.reason}\n\n💡 提案: ${modResult.suggestion}\n\n(徳ポイント: ${virtueResult.newVirtue})`
          );
        }
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }
        console.error("Moderation error:", error);
        // エラー時は投稿を許可
      }
    }

    // レート制限チェック
    const oneMinuteAgo = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 60000)
    );
    const recentPosts = await db
      .collection("posts")
      .where("userId", "==", userId)
      .where("createdAt", ">", oneMinuteAgo)
      .get();

    if (recentPosts.size >= 5) {
      throw new HttpsError(
        "resource-exhausted",
        "投稿が多すぎるよ！少し待ってからまた投稿してね"
      );
    }

    // 投稿を作成
    const postRef = db.collection("posts").doc();
    await postRef.set({
      userId: userId,
      userDisplayName: userDisplayName,
      userAvatarIndex: userAvatarIndex,
      content: content,
      postMode: postMode,
      circleId: circleId || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      reactions: {love: 0, praise: 0, cheer: 0, empathy: 0},
      commentCount: 0,
      isVisible: true,
    });

    // ユーザーの投稿数を更新
    await db.collection("users").doc(userId).update({
      totalPosts: admin.firestore.FieldValue.increment(1),
    });

    return {success: true, postId: postRef.id};
  }
);

/**
 * モデレーション付きコメント作成
 */
export const createCommentWithModeration = onCall(
  {region: "asia-northeast1", secrets: [geminiApiKey]},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const {postId, content, userDisplayName, userAvatarIndex} = request.data;

    // ユーザーがBANされているかチェック
    const userDoc = await db.collection("users").doc(userId).get();
    if (userDoc.exists && userDoc.data()?.isBanned) {
      throw new HttpsError(
        "permission-denied",
        "申し訳ありませんが、現在コメントできません。"
      );
    }

    // コンテンツモデレーション
    const apiKey = geminiApiKey.value();
    if (apiKey) {
      const genAI = new GoogleGenerativeAI(apiKey);
      const model = genAI.getGenerativeModel({model: "gemini-2.0-flash"});

      const prompt = `
あなたはSNS「ほめっぷ」のコンテンツモデレーターです。
以下のコメント内容を分析して、「他者への攻撃」があるかどうか判定してください。

【ブロック対象（isNegative: true）】
- harassment: 他者への誹謗中傷、人格攻撃、悪口
- hate_speech: 差別、ヘイトスピーチ
- profanity: 他者への暴言、罵倒
- none: 問題なし

【許可する内容（isNegative: false）】
- 共感のコメント：「わかる」「大変だったね」「頑張ったね」
- 感情の共有：「私も同じ気持ち」「辛いよね」
- 応援のコメント

【重要】
⚠️ 「他者を攻撃しているか」が最重要ポイントです
⚠️ 誰かを傷つける意図がない限り「none」と判定してください

【コメント内容】
${content}

【回答形式】
{
  "isNegative": boolean,
  "category": string,
  "confidence": number,
  "reason": "理由",
  "suggestion": "提案"
}
`;

      try {
        const result = await model.generateContent(prompt);
        const responseText = result.response.text().trim();

        let jsonText = responseText;
        const jsonMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
        if (jsonMatch) {
          jsonText = jsonMatch[1];
        }

        const modResult = JSON.parse(jsonText) as ModerationResult;

        if (modResult.isNegative && modResult.confidence >= 0.7) {
          await decreaseVirtue(
            userId,
            `ネガティブコメント検出: ${modResult.category}`,
            VIRTUE_CONFIG.lossPerNegative
          );

          throw new HttpsError(
            "invalid-argument",
            `${modResult.reason}\n\n💡 ${modResult.suggestion}`
          );
        }
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }
        console.error("Moderation error:", error);
      }
    }

    // コメントを作成
    const commentRef = db.collection("comments").doc();
    await commentRef.set({
      postId: postId,
      userId: userId,
      userDisplayName: userDisplayName,
      userAvatarIndex: userAvatarIndex,
      isAI: false,
      content: content,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 投稿のコメント数を更新
    await db.collection("posts").doc(postId).update({
      commentCount: admin.firestore.FieldValue.increment(1),
    });

    return {success: true, commentId: commentRef.id};
  }
);

// ===============================================
// 通報機能
// ===============================================

/**
 * コンテンツを通報する
 */
export const reportContent = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const reporterId = request.auth.uid;
    const {contentId, contentType, reason, targetUserId} = request.data;

    if (!contentId || !contentType || !reason || !targetUserId) {
      throw new HttpsError("invalid-argument", "必要な情報が不足しています");
    }

    // 自分自身を通報できない
    if (reporterId === targetUserId) {
      throw new HttpsError("invalid-argument", "自分自身を通報することはできません");
    }

    // 既に同じ内容を通報していないかチェック
    const existingReport = await db
      .collection("reports")
      .where("reporterId", "==", reporterId)
      .where("contentId", "==", contentId)
      .get();

    if (!existingReport.empty) {
      throw new HttpsError("already-exists", "既にこの内容を通報しています");
    }

    // 通報を記録
    const reportRef = await db.collection("reports").add({
      reporterId: reporterId,
      targetUserId: targetUserId,
      contentId: contentId,
      contentType: contentType,  // "post" | "comment"
      reason: reason,
      status: "pending",  // pending, reviewed, resolved, dismissed
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 対象ユーザーの通報カウントを増加
    const targetUserRef = db.collection("users").doc(targetUserId);
    await targetUserRef.update({
      reportCount: admin.firestore.FieldValue.increment(1),
    });

    // 通報が3件以上溜まったら自動で徳を減少
    const reportsCount = await db
      .collection("reports")
      .where("targetUserId", "==", targetUserId)
      .where("status", "==", "pending")
      .get();

    if (reportsCount.size >= 3) {
      const virtueResult = await decreaseVirtue(
        targetUserId,
        "複数の通報を受けたため",
        VIRTUE_CONFIG.lossPerReport
      );

      // 通報をreviewedに更新
      const batch = db.batch();
      reportsCount.docs.forEach((doc) => {
        batch.update(doc.ref, {status: "reviewed"});
      });
      await batch.commit();

      console.log(`Auto virtue decrease for ${targetUserId}: ${virtueResult.newVirtue}`);
    }

    return {
      success: true,
      reportId: reportRef.id,
      message: "通報を受け付けました。ご協力ありがとうございます。",
    };
  }
);

/**
 * 徳ポイント履歴を取得
 */
export const getVirtueHistory = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;

    const history = await db
      .collection("virtueHistory")
      .where("userId", "==", userId)
      .orderBy("createdAt", "desc")
      .limit(20)
      .get();

    return {
      history: history.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
        createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
      })),
    };
  }
);

/**
 * 徳ポイントの現在値と設定を取得
 */
export const getVirtueStatus = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const userDoc = await db.collection("users").doc(userId).get();

    if (!userDoc.exists) {
      throw new HttpsError("not-found", "ユーザーが見つかりません");
    }

    const userData = userDoc.data()!;

    return {
      virtue: userData.virtue || VIRTUE_CONFIG.initial,
      isBanned: userData.isBanned || false,
      warningThreshold: VIRTUE_CONFIG.warningThreshold,
      maxVirtue: VIRTUE_CONFIG.initial,
    };
  }
);

// ===============================================
// タスク管理機能
// ===============================================

// タスク完了時の徳ポイント設定
const TASK_VIRTUE_CONFIG = {
  dailyCompletion: 5,    // デイリータスク完了: +5
  goalCompletion: 20,    // 目標タスク完了: +20
  streakBonus: 2,        // 連続ボーナス: +2/日
  maxStreakBonus: 20,    // 連続ボーナス上限: +20
};

/**
 * 徳ポイントを増加させる関数
 */
async function increaseVirtue(
  userId: string,
  reason: string,
  amount: number
): Promise<{newVirtue: number}> {
  const userRef = db.collection("users").doc(userId);
  const userDoc = await userRef.get();
  
  if (!userDoc.exists) {
    throw new HttpsError("not-found", "ユーザーが見つかりません");
  }
  
  const userData = userDoc.data()!;
  const currentVirtue = userData.virtue || VIRTUE_CONFIG.initial;
  const newVirtue = Math.min(currentVirtue + amount, VIRTUE_CONFIG.initial); // 上限を超えない
  
  await userRef.update({virtue: newVirtue});
  
  // 履歴を記録
  await db.collection("virtueHistory").add({
    userId: userId,
    type: "increase",
    amount: amount,
    reason: reason,
    beforeVirtue: currentVirtue,
    afterVirtue: newVirtue,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  
  return {newVirtue};
}

/**
 * タスクを作成する
 */
export const createTask = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const {content, type} = request.data;

    if (!content || typeof content !== "string") {
      throw new HttpsError("invalid-argument", "タスク内容が必要です");
    }

    if (!type || (type !== "daily" && type !== "goal")) {
      throw new HttpsError("invalid-argument", "タスクタイプは'daily'または'goal'です");
    }

    const taskRef = db.collection("tasks").doc();
    await taskRef.set({
      userId: userId,
      content: content,
      type: type,
      isCompleted: false,
      streak: 0,
      lastCompletedAt: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {success: true, taskId: taskRef.id};
  }
);

/**
 * タスクを完了する
 */
export const completeTask = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const {taskId} = request.data;

    if (!taskId) {
      throw new HttpsError("invalid-argument", "タスクIDが必要です");
    }

    const taskRef = db.collection("tasks").doc(taskId);
    const taskDoc = await taskRef.get();

    if (!taskDoc.exists) {
      throw new HttpsError("not-found", "タスクが見つかりません");
    }

    const taskData = taskDoc.data()!;

    if (taskData.userId !== userId) {
      throw new HttpsError("permission-denied", "このタスクを完了する権限がありません");
    }

    // 既に完了している場合
    if (taskData.type === "goal" && taskData.isCompleted) {
      throw new HttpsError("failed-precondition", "この目標は既に完了しています");
    }

    // デイリータスクの場合、今日既に完了しているかチェック
    if (taskData.type === "daily" && taskData.lastCompletedAt) {
      const lastCompleted = taskData.lastCompletedAt.toDate();
      const today = new Date();
      if (
        lastCompleted.getFullYear() === today.getFullYear() &&
        lastCompleted.getMonth() === today.getMonth() &&
        lastCompleted.getDate() === today.getDate()
      ) {
        throw new HttpsError("failed-precondition", "今日は既にこのタスクを完了しています");
      }
    }

    // 連続日数を計算
    let newStreak = 1;
    if (taskData.type === "daily" && taskData.lastCompletedAt) {
      const lastCompleted = taskData.lastCompletedAt.toDate();
      const today = new Date();
      const diffTime = today.getTime() - lastCompleted.getTime();
      const diffDays = Math.floor(diffTime / (1000 * 60 * 60 * 24));
      
      if (diffDays === 1) {
        newStreak = (taskData.streak || 0) + 1;
      } else if (diffDays === 0) {
        newStreak = taskData.streak || 1;
      }
    }

    // 徳ポイント計算
    let virtueGain = taskData.type === "goal"
      ? TASK_VIRTUE_CONFIG.goalCompletion
      : TASK_VIRTUE_CONFIG.dailyCompletion;

    // 連続ボーナス
    const streakBonus = Math.min(
      newStreak * TASK_VIRTUE_CONFIG.streakBonus,
      TASK_VIRTUE_CONFIG.maxStreakBonus
    );
    virtueGain += streakBonus;

    // 徳ポイントを増加
    const virtueResult = await increaseVirtue(
      userId,
      `タスク完了: ${taskData.content}`,
      virtueGain
    );

    // タスクを更新
    await taskRef.update({
      isCompleted: taskData.type === "goal" ? true : taskData.isCompleted,
      streak: newStreak,
      lastCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      virtueGain: virtueGain,
      newVirtue: virtueResult.newVirtue,
      streak: newStreak,
      streakBonus: streakBonus,
    };
  }
);

/**
 * タスクの完了を取り消す
 */
export const uncompleteTask = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const {taskId} = request.data;

    if (!taskId) {
      throw new HttpsError("invalid-argument", "タスクIDが必要です");
    }

    const taskRef = db.collection("tasks").doc(taskId);
    const taskDoc = await taskRef.get();

    if (!taskDoc.exists) {
      throw new HttpsError("not-found", "タスクが見つかりません");
    }

    const taskData = taskDoc.data()!;

    if (taskData.userId !== userId) {
      throw new HttpsError("permission-denied", "このタスクの完了を取り消す権限がありません");
    }

    // 既に未完了の場合は何もしない
    if (taskData.type === "goal" && !taskData.isCompleted) {
      throw new HttpsError("failed-precondition", "この目標は既に未完了です");
    }
    // デイリータスクの場合、lastCompletedAtがnullなら未完了
    if (taskData.type === "daily" && !taskData.lastCompletedAt) {
      throw new HttpsError("failed-precondition", "このデイリータスクは既に未完了です");
    }

    // 徳ポイント減少量を計算 (完了時と同額を減らす)
    let virtueLoss = taskData.type === "goal"
      ? TASK_VIRTUE_CONFIG.goalCompletion
      : TASK_VIRTUE_CONFIG.dailyCompletion;

    // 連続ボーナスも減少
    const currentStreak = taskData.streak || 0;
    const streakBonus = Math.min(
      currentStreak * TASK_VIRTUE_CONFIG.streakBonus,
      TASK_VIRTUE_CONFIG.maxStreakBonus
    );
    virtueLoss += streakBonus;

    // 徳ポイントを減少
    const virtueResult = await decreaseVirtue(
      userId,
      `タスク完了取り消し: ${taskData.content}`,
      virtueLoss
    );

    // タスクを更新
    await taskRef.update({
      isCompleted: false,
      streak: taskData.type === "daily" ? Math.max(0, currentStreak - 1) : 0,
      lastCompletedAt: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      virtueLoss: virtueLoss,
      newVirtue: virtueResult.newVirtue,
      newStreak: taskData.type === "daily" ? Math.max(0, currentStreak - 1) : 0,
    };
  }
);

/**
 * タスクを削除する
 */
export const deleteTask = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const {taskId} = request.data;

    if (!taskId) {
      throw new HttpsError("invalid-argument", "タスクIDが必要です");
    }

    const taskRef = db.collection("tasks").doc(taskId);
    const taskDoc = await taskRef.get();

    if (!taskDoc.exists) {
      throw new HttpsError("not-found", "タスクが見つかりません");
    }

    const taskData = taskDoc.data()!;

    if (taskData.userId !== userId) {
      throw new HttpsError("permission-denied", "このタスクを削除する権限がありません");
    }

    await taskRef.delete();

    return {success: true};
  }
);

/**
 * タスク一覧を取得する
 */
export const getTasks = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const userId = request.auth.uid;
    const {type} = request.data;

    let query = db.collection("tasks").where("userId", "==", userId);

    if (type && (type === "daily" || type === "goal")) {
      query = query.where("type", "==", type);
    }

    const tasksSnapshot = await query.orderBy("createdAt", "asc").get();

    // 今日の日付を取得（日本時間 JST = UTC+9）
    const now = new Date(); // UTC時間
    const jstOffsetMs = 9 * 60 * 60 * 1000; // 9時間をミリ秒で

    // 現在時刻をJSTに変換して、年月日を取得（getUTC*を使用して確実にUTC基準で計算）
    const nowJst = new Date(now.getTime() + jstOffsetMs);
    const jstYear = nowJst.getUTCFullYear();
    const jstMonth = nowJst.getUTCMonth();
    const jstDay = nowJst.getUTCDate();

    // JSTの今日0:00をUTC時間で表現
    // Date.UTCで確実にUTC時間を作成し、-9時間でJSTの0:00のUTC表現を得る
    const todayStart = new Date(Date.UTC(jstYear, jstMonth, jstDay) - jstOffsetMs);

    return {
      tasks: tasksSnapshot.docs.map((doc) => {
        const data = doc.data();
        const lastCompletedAt = data.lastCompletedAt?.toDate?.();
        
        // デイリータスクの場合、今日完了したかどうかを判定
        let isCompletedToday = false;
        if (data.type === "daily" && lastCompletedAt) {
          isCompletedToday = lastCompletedAt >= todayStart;
        }

        return {
          id: doc.id,
          ...data,
          isCompletedToday: isCompletedToday,
          createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
          updatedAt: data.updatedAt?.toDate?.()?.toISOString() || null,
          lastCompletedAt: lastCompletedAt?.toISOString() || null,
        };
      }),
    };
  }
);

// ===============================================
// フォロー機能
// ===============================================

/**
 * ユーザーをフォローする
 */
export const followUser = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const followerId = request.auth.uid;
    const {targetUserId} = request.data;

    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "フォロー対象のユーザーIDが必要です");
    }

    if (followerId === targetUserId) {
      throw new HttpsError("invalid-argument", "自分自身をフォローすることはできません");
    }

    // 対象ユーザーの存在確認
    const targetUserDoc = await db.collection("users").doc(targetUserId).get();
    if (!targetUserDoc.exists) {
      throw new HttpsError("not-found", "ユーザーが見つかりません");
    }

    // 既にフォローしているかチェック
    const followRef = db.collection("follows").doc(`${followerId}_${targetUserId}`);
    const followDoc = await followRef.get();

    if (followDoc.exists) {
      throw new HttpsError("already-exists", "既にフォローしています");
    }

    // フォローを作成
    await followRef.set({
      followerId: followerId,
      followingId: targetUserId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // フォロワー数・フォロー数を更新
    await db.collection("users").doc(followerId).update({
      followingCount: admin.firestore.FieldValue.increment(1),
    });
    await db.collection("users").doc(targetUserId).update({
      followersCount: admin.firestore.FieldValue.increment(1),
    });

    return {success: true};
  }
);

/**
 * フォローを解除する
 */
export const unfollowUser = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const followerId = request.auth.uid;
    const {targetUserId} = request.data;

    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "フォロー解除対象のユーザーIDが必要です");
    }

    const followRef = db.collection("follows").doc(`${followerId}_${targetUserId}`);
    const followDoc = await followRef.get();

    if (!followDoc.exists) {
      throw new HttpsError("not-found", "フォローしていません");
    }

    // フォローを削除
    await followRef.delete();

    // フォロワー数・フォロー数を更新
    await db.collection("users").doc(followerId).update({
      followingCount: admin.firestore.FieldValue.increment(-1),
    });
    await db.collection("users").doc(targetUserId).update({
      followersCount: admin.firestore.FieldValue.increment(-1),
    });

    return {success: true};
  }
);

/**
 * フォロー状態を確認する
 */
export const getFollowStatus = onCall(
  {region: "asia-northeast1"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const followerId = request.auth.uid;
    const {targetUserId} = request.data;

    if (!targetUserId) {
      throw new HttpsError("invalid-argument", "対象ユーザーIDが必要です");
    }

    const followRef = db.collection("follows").doc(`${followerId}_${targetUserId}`);
    const followDoc = await followRef.get();

    return {isFollowing: followDoc.exists};
  }
);
