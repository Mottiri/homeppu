/**
 * bio生成用プロンプト
 * callable/ai.ts から分離
 */

import { AIPersona, AGE_GROUPS } from "../personas";

/**
 * bio生成用プロンプトを生成
 */
export function getBioGenerationPrompt(persona: AIPersona): string {
    const genderStr = persona.gender === "male" ? "男性" : "女性";
    const ageStr = AGE_GROUPS[persona.ageGroup].name;

    return `
あなたはSNSのプロフィール文（bio）を作成するアシスタントです。
以下のキャラクター設定に基づいて、そのキャラクターが自分で書いたような自然なbioを作成してください。

【キャラクター設定】
- 性別: ${genderStr}
- 年齢層: ${ageStr}
- 職業: ${persona.occupation.name}（${persona.occupation.bio}）
- 性格: ${persona.personality.name}（${persona.personality.trait}）

【重要なルール】
1. 40〜80文字程度で書く
2. そのキャラクターが自分で書いたような自然な文章
3. 説明文ではなく、自己紹介文として書く
4. 「〜な性格です」のような説明的な文は避ける
5. 職業と趣味や日常を自然に織り交ぜる
6. 名前は含めないでください
7. 「すごい」「えらい」「わかるよ〜」「いいんじゃない？」など、他者への反応・コメントのような言葉は入れない

【良い例】
- 「Webデザイナーしてます🎨 休日は美術館巡り」
- 「営業マン3年目！休日は筋トレに励んでます💪」
- 「保育士やってます〜 子どもたちに癒される日々🌸」
- 「エンジニアやってるww 深夜コーディングが日課」

【悪い例】
- 「26歳 / 大学生🫐 学業やサークル活動に励む。トレンドに敏感な性格です。」← 説明的すぎる
  - 「私は優しい性格の看護師です」← 説明文になっている

【出力】
bioのテキストのみを出力してください。他の説明は不要です。
`;
}
