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
- violence: 実際の暴力写真、血液、怪我、残虐な内容、血まみれ
- hate: ヘイトシンボル、差別的な画像
- dangerous: 違法行為、麻薬、薬

【許容（isInappropriate: false）】
- ゲーム、アニメ、漫画、映画、ドラマ等のフィクション作品の画像・カバーアート・スクリーンショット（戦闘シーンやアクションシーンを含む場合でも、フィクション作品であれば許容）
- ただし、フィクション作品であっても性的な内容（adult）は許容しない

上記ブロック対象に該当せず、許容条件を満たす場合は isInappropriate: false としてください。

【回答形式】
JSON形式のみで回答:
{"isInappropriate": true/false, "category": "adult"|"violence"|"hate"|"dangerous"|"none", "confidence": 0-1, "reason": "理由"}
`;

/**
 * 画像モデレーション用プロンプト（Callable用も共通利用）
 */
export const IMAGE_MODERATION_CALLABLE_PROMPT = IMAGE_MODERATION_PROMPT;

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
