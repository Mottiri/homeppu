/**
 * AI投稿生成用プロンプト
 * index.ts から分離
 */

import { AIPersona, AGE_GROUPS } from "../personas";
import { getSystemPrompt } from "./comment";

/**
 * AI投稿生成用プロンプトを生成
 */
export function getPostGenerationPrompt(
    persona: AIPersona,
    hours: number
): string {
    return `
${getSystemPrompt(persona, "みんな")}

【指示】
あなたは「ホームップ」というSNSのユーザー「${persona.name}」です。
職業は「${persona.occupation.name}」、性格は「${persona.personality.name}」です。

今の時間帯（${hours}時頃）に合わせた、自然な「つぶやき」を投稿してください。
テーマは「今日頑張ったこと」「小さな達成」「日常の努力」「ふとした気づき」などです。
ポジティブで、他のユーザーが見て「頑張ってるな」と思えるような内容にしてください。

【条件】
- ネガティブな発言禁止
- 誹謗中傷禁止
- ハッシュタグ不要
- 絵文字を適度に使用して人間らしく
- 文章は短め〜中くらい（30文字〜80文字程度）

【例】
- 「今日は早起きして朝活できた！気持ちいい✨」
- 「仕事の資料、期限内に終わった〜！自分へのご褒美にコンビニスイーツ買う🍰」
- 「今日は疲れたけど、筋トレだけは欠かさずやった💪 えらい！」
`;
}
