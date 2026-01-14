/**
 * モデレーション用プロンプト
 * helpers/moderation.ts, index.ts から分離
 */

/**
 * 画像モデレーション用プロンプト
 */
export const IMAGE_MODERATION_PROMPT = `
この画像がSNSへの投稿として適切かどうか判定してください。

【ブロック対象（isInappropriate: true）】
- adult: 成人向けコンテンツ、露出の多い画像、性的な内容
- violence: 暴力的な画像、血液、怪我、残虐な内容、血まみれ
- hate: ヘイトシンボル、差別的な画像
- dangerous: 危険な行為、違法行為、武器

上記に該当しない場合は isInappropriate: false としてください。

【回答形式】
JSON形式のみで回答:
{"isInappropriate": true/false, "category": "adult"|"violence"|"hate"|"dangerous"|"none", "confidence": 0-1, "reason": "理由"}
`;

/**
 * 動画モデレーション用プロンプト
 */
export const VIDEO_MODERATION_PROMPT = `
この動画がSNSへの投稿として適切かどうか判定してください。

【ブロック対象（isInappropriate: true）】
- adult: 成人向けコンテンツ、露出の多い映像、性的な内容
- violence: 暴力的な映像、血液、怪我、残虐な内容
- hate: ヘイトシンボル、差別的な内容
- dangerous: 危険な行為、違法行為、武器

上記に該当しない場合は isInappropriate: false としてください。

【回答形式】
必ず以下のJSON形式のみで回答してください：
{"isInappropriate": true/false, "category": "adult"|"violence"|"hate"|"dangerous"|"none", "confidence": 0-1, "reason": "判定理由"}
`;

/**
 * 画像モデレーション用プロンプト（Callable版 - より詳細）
 */
export const IMAGE_MODERATION_CALLABLE_PROMPT = `
この画像がSNSへの投稿として適切かどうか判定してください。

【ブロック対象（isInappropriate: true）】
- adult: 成人向けコンテンツ、露出の多い画像、性的な内容
- violence: 暴力的な画像、血液、怪我、残虐な内容
- hate: ヘイトシンボル、差別的な画像
- dangerous: 危険な行為、違法行為、武器

【許可する内容（isInappropriate: false）】
- 通常の人物写真（水着でも一般的なものはOK）
- 風景、食べ物、ペット
- 趣味の写真
- 芸術作品（明らかにアダルトでない限り）

【回答形式】
必ず以下のJSON形式のみで回答してください：
{
  "isInappropriate": true または false,
  "category": "adult" | "violence" | "hate" | "dangerous" | "none",
  "confidence": 0から1の数値,
  "reason": "判定理由"
}
`;

/**
 * テキストモデレーション用プロンプトを生成
 */
export function getTextModerationPrompt(text: string, postContent: string = ""): string {
    return `
あなたはSNSのコミュニティマネージャーです。以下のテキストが、ポジティブで優しいSNS「ほめっぷ」にふさわしいかどうか（攻撃的、誹謗中傷、不適切でないか）を判定してください。
文脈として、ユーザーは「投稿内容」に対して「コメント」をしようとしています。
たとえ一見普通の言葉でも、文脈によって嫌味や攻撃になる場合はネガティブと判定してください。
特に「死ね」「殺す」「きもい」などの直接的な暴言・攻撃は厳しく判定してください。

【投稿内容】
"${postContent}"

【コメントしようとしている内容】
"${text}"

以下のJSON形式のみで回答してください:
{
  "isNegative": boolean, // ネガティブ（不適切）ならtrue
  "category": "harassment" | "hate_speech" | "profanity" | "self_harm" | "spam" | "none",
  "confidence": number, // 0.0〜1.0 (確信度)
  "reason": "判定理由（ユーザーに簡潔に伝える用）",
  "suggestion": "より優しい言い方の提案（もしあれば）"
}
`;
}
