/**
 * 検索トークン生成ヘルパー
 * サークル名をN-gramトークンに分割し、array-containsによる部分一致検索を実現
 */

/**
 * サークル名からN-gramトークン配列を生成する
 * 2文字以上の連続部分文字列をすべて生成（小文字化済み）
 *
 * トークン数は O(n^2) で増加するが、サークル名は最大30文字程度（UIバリデーション）
 * のため実用上問題ない（30文字で最大435トークン、Fistore上限40,000に対して十分余裕あり）
 *
 * 例: "毎日ダイエット部" → ["毎日", "日ダ", "ダイ", ..., "毎日ダイエット部"]
 */
export function generateNameTokens(name: string): string[] {
  const lower = name.toLowerCase().trim();
  // Array.fromでUnicode文字単位に分割（絵文字のサロゲートペア対応）
  const chars = Array.from(lower);
  if (chars.length < 1) return [];

  const tokens = new Set<string>();

  // 1文字〜全文字のN-gramを生成
  for (let len = 1; len <= chars.length; len++) {
    for (let start = 0; start <= chars.length - len; start++) {
      tokens.add(chars.slice(start, start + len).join(""));
    }
  }

  return Array.from(tokens);
}
