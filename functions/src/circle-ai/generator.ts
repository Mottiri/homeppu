/**
 * サークルAI生成モジュール
 * サークル作成時に自動生成されるAIペルソナの生成ロジック
 */

import {
  Gender,
  AgeGroup,
  OCCUPATIONS,
  PERSONALITIES,
  BIO_TEMPLATES,
  AI_USABLE_PREFIXES,
  AI_USABLE_SUFFIXES,
} from "../ai/personas";

/**
 * サークル専用AIペルソナを生成する関数
 * サークルの説明からテーマ・レベル感を抽出してペルソナに反映
 */
export function generateCircleAIPersona(
  circleInfo: { name: string; description: string; category: string },
  index: number
): {
  id: string;
  name: string;
  namePrefixId: string;
  nameSuffixId: string;
  gender: Gender;
  ageGroup: AgeGroup;
  occupation: { id: string; name: string; bio: string };
  personality: { id: string; name: string; trait: string; style: string };
  avatarIndex: number;
  bio: string;
  circleContext: string;
  growthLevel: number;
  lastGrowthAt: Date;
} {
  // 性別を決定（インデックスで分散）
  const gender: Gender = index % 2 === 0 ? "female" : "male";

  // 各カテゴリをランダムに選択
  const occupations = OCCUPATIONS[gender];
  const personalities = PERSONALITIES[gender];

  const occupation = occupations[(index * 7) % occupations.length];
  const personality = personalities[(index * 3) % personalities.length];
  const ageGroup: AgeGroup = (["late_teens", "twenties", "thirties"] as const)[index % 3];

  // 名前パーツからランダム選択
  const prefixIndex = (index * 13) % AI_USABLE_PREFIXES.length;
  const suffixIndex = (index * 17) % AI_USABLE_SUFFIXES.length;
  const namePrefix = AI_USABLE_PREFIXES[prefixIndex];
  const nameSuffix = AI_USABLE_SUFFIXES[suffixIndex];
  const name = `${namePrefix.text}${nameSuffix.text}`;

  // アバターインデックス
  const avatarIndex = (index * 11) % 10;

  // サークルのコンテキストを生成
  const circleContext = `サークル「${circleInfo.name}」のメンバー。${circleInfo.description}`;

  // 一般AIと同じbio生成ロジックを使用
  const occupationBios = BIO_TEMPLATES[occupation.id] || {};
  const personalityBios = occupationBios[personality.id] || [];

  // bioが見つからない場合はデフォルト
  let bio: string;
  if (personalityBios.length > 0) {
    bio = personalityBios[index % personalityBios.length];
  } else {
    // フォールバック：シンプルだけど自然なbio
    const defaultBios = [
      `${occupation.name} してます！よろしくね✨`,
      `${occupation.name} やってます。毎日頑張ってる`,
      `${occupation.name} です。趣味は読書と散歩`,
    ];
    bio = defaultBios[index % defaultBios.length];
  }

  return {
    id: `circle_ai_${Date.now()}_${index}`,
    name: name.trim(),
    namePrefixId: `prefix_${namePrefix.id}`,
    nameSuffixId: `suffix_${nameSuffix.id}`,
    gender,
    ageGroup,
    occupation,
    personality,
    avatarIndex,
    bio,
    circleContext,
    growthLevel: 0, // 初期成長レベル（初心者）
    lastGrowthAt: new Date(),
  };
}
