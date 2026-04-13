/**
 * テキストモデレーション共通ヘルパー
 * 投稿・サークル作成等で共通のテキストモデレーションロジックを提供
 */

import { db, FieldValue } from "./firebase";
import { createAIProviderFactory } from "../ai/provider";
import { logAIProviderUsage } from "./ai-usage";
import { NG_WORDS } from "./virtue";
import { ModerationResult } from "../types";
import { MODERATION_MESSAGES } from "../config/messages";
import { COLLECTIONS } from "../config/collections";
import { HttpsError } from "firebase-functions/v2/https";

/** モデレーション結果 */
export interface TextModerationOutcome {
  /** ブロック（confidence >= 0.7）された場合 true */
  blocked: boolean;
  /** 曖昧判定（0.5-0.7）でフラグ付きの場合 true */
  flagged: boolean;
  /** フラグ時の理由テキスト */
  flagReason?: string;
  /** AIからの判定結果（解析成功時） */
  result?: ModerationResult;
}

/** モデレーション対象のコンテキスト */
interface ModerationContext {
  /** ログ用の種別（"post", "circle_create" 等） */
  type: string;
  /** ユーザーID */
  userId: string;
  /** プロンプトに含めるコンテンツ説明 */
  contentDescription: string;
  /** プロンプトに含めるコンテンツ本文 */
  contentBody: string;
}

/**
 * モデレーション用AIプロンプトを生成
 */
function buildModerationPrompt(description: string, body: string): string {
  return `
あなたはSNS「ほめっぷ」のコンテンツモデレーターです。
「ほめっぷ」は「世界一優しいSNS」を目指しています。

以下の${description}を分析して、不適切な表現があるかどうか厳格に判定してください。

【ブロック対象（isNegative: true）】
- harassment: 他者への誹謗中傷、人格攻撃、悪口
- hate_speech: 差別、ヘイトスピーチ
- profanity: 暴言、罵倒、汚い言葉（「死ね」「殺す」などは対象なしでもNG）
- violence: 暴力的な表現、脅迫
- self_harm: 自傷行為の助長
- spam: スパム、宣伝
- sexual: 性的な表現、アダルトコンテンツ

上記に該当しない場合は isNegative: false としてください。

【重要な判定基準】
⚠️ 暴力的な言葉（殺す、死ね、殴るなど）は、対象が特定されていなくても「profanity」または「violence」としてブロックしてください。
⚠️ 「他者を攻撃しているか」は厳しく見てください。

【内容】
${body}

【回答形式】
必ず以下のJSON形式で回答してください。他の文字は含めないでください。
{"isNegative": true/false, "category": "harassment"|"hate_speech"|"profanity"|"violence"|"self_harm"|"spam"|"sexual"|"none", "confidence": 0-1, "reason": "判定理由", "suggestion": "より良い表現の提案"}
`;
}

/**
 * AIレスポンスからJSONを抽出
 */
function extractJson(responseText: string): string {
  // コードブロック内のJSON
  const codeBlockMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
  if (codeBlockMatch && codeBlockMatch[1]) {
    return codeBlockMatch[1].trim();
  }
  // 生のJSON
  const firstBrace = responseText.indexOf("{");
  const lastBrace = responseText.lastIndexOf("}");
  if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
    return responseText.substring(firstBrace, lastBrace + 1);
  }
  return responseText;
}

/**
 * NGワードチェック
 * 該当あれば HttpsError をスローする
 */
export function checkNGWords(text: string): void {
  const hasNgWord = NG_WORDS.some((word) => text.includes(word));
  if (hasNgWord) {
    throw new HttpsError("invalid-argument", MODERATION_MESSAGES.NG_WORD_USED);
  }
}

/**
 * テキストモデレーション（NGワードチェック + AIモデレーション）
 *
 * NGワード検出時は即座にHttpsErrorをスロー。
 * AIモデレーションでブロック判定時もHttpsErrorをスロー。
 * AIエラー時はFail Open（許可）。
 *
 * @returns blocked=false, flagged=false の場合は通過。
 *          flagged=true の場合は呼び出し元で needsReview フラグを立てる。
 */
export async function moderateText(ctx: ModerationContext): Promise<TextModerationOutcome> {
  // 1. 静的NGワードチェック
  checkNGWords(ctx.contentBody);

  // 2. AIモデレーション
  let rawResponseText = "";
  try {
    const aiFactory = createAIProviderFactory();
    const prompt = buildModerationPrompt(ctx.contentDescription, ctx.contentBody);

    const result = await aiFactory.generateText(prompt);
    const responseText = result.text.trim();
    rawResponseText = responseText;
    logAIProviderUsage(`${ctx.type}_text_moderation`, result, { userId: ctx.userId });

    const jsonText = extractJson(responseText);
    const modResult = JSON.parse(jsonText) as ModerationResult;

    // 曖昧判定 (0.5-0.7) → フラグ付き
    if (modResult.isNegative && modResult.confidence >= 0.5 && modResult.confidence < 0.7) {
      return {
        blocked: false,
        flagged: true,
        flagReason: `テキスト: ${modResult.category} (confidence: ${modResult.confidence})`,
        result: modResult,
      };
    }

    // 明確NG (>= 0.7) → ブロック
    if (modResult.isNegative && modResult.confidence >= 0.7) {
      console.warn(`[MODERATION NG] ${ctx.type} rejected:`, JSON.stringify({
        category: modResult.category,
        confidence: modResult.confidence,
        reason: modResult.reason,
      }));
      await db.collection(COLLECTIONS.MODERATED_CONTENT).add({
        userId: ctx.userId,
        content: ctx.contentBody.substring(0, 500),
        type: ctx.type,
        category: modResult.category,
        confidence: modResult.confidence,
        reason: modResult.reason,
        createdAt: FieldValue.serverTimestamp(),
      });
      throw new HttpsError(
        "invalid-argument",
        MODERATION_MESSAGES.suggestionWithReason(modResult.reason, modResult.suggestion)
      );
    }

    // 問題なし
    return { blocked: false, flagged: false, result: modResult };
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error(`${ctx.type} text moderation error:`, error);

    try {
      await db.collection(COLLECTIONS.MODERATION_ERRORS).add({
        userId: ctx.userId,
        content: ctx.contentBody.substring(0, 100),
        error: String(error),
        rawResponse: rawResponseText ? rawResponseText.substring(0, 500) : "empty",
        createdAt: FieldValue.serverTimestamp(),
      });
    } catch (firestoreError) {
      console.error("Failed to save moderation error:", firestoreError);
    }

    // Fail Open
    console.warn(`Moderation failed for ${ctx.type}, allowing (fail-open)`);
    return { blocked: false, flagged: false };
  }
}
