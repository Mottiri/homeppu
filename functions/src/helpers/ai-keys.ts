/**
 * AI系処理の冪等性キー生成ヘルパー
 * S1: Cloud Functions idempotency key 導入
 */

import { createHash } from "crypto";

/**
 * AI投稿の業務キーベースpostIdを生成
 * 同一persona・同一日付で常に同じIDを返す（リトライ安全）
 */
export function generateAIPostId(personaId: string, dateStr?: string): string {
  const todayStr = dateStr ?? new Date().toISOString().split("T")[0];
  return `ai-post-${personaId}-${todayStr}`;
}

/**
 * postIdをシードにしたdeterministic shuffle
 * リトライ間で同一の結果を返す（Math.random()を使わない）
 */
/**
 * AIコメントの決定的ドキュメントIDを生成
 */
export function generateAICommentId(postId: string, personaId: string): string {
  return `ai-comment-${postId}-${personaId}`;
}

/**
 * AIリアクションの決定的ドキュメントIDを生成
 */
export function generateAIReactionId(postId: string, personaId: string): string {
  return `ai-reaction-${postId}-${personaId}`;
}

/**
 * postIdをシードにしたdeterministic shuffle
 * リトライ間で同一の結果を返す（Math.random()を使わない）
 */
export function deterministicShuffle<T>(items: T[], seed: string): T[] {
  const hashed = items.map((item, index) => {
    const hash = createHash("sha256")
      .update(`${seed}-${index}`)
      .digest("hex");
    return { item, hash };
  });
  hashed.sort((a, b) => a.hash.localeCompare(b.hash));
  return hashed.map((h) => h.item);
}
