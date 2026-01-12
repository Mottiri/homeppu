/**
 * モデレーション関連の型定義
 */

// ネガティブカテゴリ
export type NegativeCategory =
  | "harassment"      // 誹謗中傷
  | "hate_speech"     // ヘイトスピーチ
  | "profanity"       // 不適切な言葉
  | "self_harm"       // 自傷行為の助長
  | "spam"            // スパム
  | "none";           // 問題なし

// テキストモデレーション結果
export interface ModerationResult {
  isNegative: boolean;
  category: NegativeCategory;
  confidence: number;    // 0-1の確信度
  reason: string;        // 判定理由（ユーザーへの説明用）
  suggestion: string;    // 改善提案
}

// メディアモデレーション結果
export interface MediaModerationResult {
  isInappropriate: boolean;
  category: "adult" | "violence" | "hate" | "dangerous" | "none";
  confidence: number;
  reason: string;
}

// メディアアイテムの型
export interface MediaItem {
  url: string;
  type: "image" | "video" | "file";
  fileName?: string;
  mimeType?: string;
  fileSize?: number;
  thumbnailUrl?: string;
}
