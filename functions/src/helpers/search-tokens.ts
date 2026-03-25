/**
 * 検索トークン生成ヘルパー
 * サークル名をプレフィックストークンに分割し、array-containsによる前方一致検索を実現
 */

/**
 * サークル名からプレフィックストークン配列を生成する
 * 先頭から1文字ずつ伸ばしたプレフィックスをすべて生成（小文字化済み）
 *
 * トークン数は O(n) で増加し、サークル名は最大30文字程度（UIバリデーション）
 * のため30文字で最大30トークン（Firestore上限40,000に対して十分余裕あり）
 *
 * 例: "毎日ダイエット部" → ["毎", "毎日", "毎日ダ", ..., "毎日ダイエット部"]
 */
export function generateNameTokens(name: string): string[] {
  const lower = name.toLowerCase().trim();
  // Array.fromでUnicode文字単位に分割（絵文字のサロゲートペア対応）
  const chars = Array.from(lower);
  if (chars.length < 1) return [];

  const tokens = new Set<string>();

  // 先頭からのプレフィックスを生成
  for (let len = 1; len <= chars.length; len++) {
    tokens.add(chars.slice(0, len).join(""));
  }

  return Array.from(tokens);
}
