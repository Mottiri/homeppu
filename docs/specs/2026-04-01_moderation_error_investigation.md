# モデレーションエラー調査メモ 2026-04-01

## 目的

投稿作成時にコンテンツ自体は正常に作成される一方で、`moderationErrors` に
`SyntaxError: Unterminated string in JSON ...` が記録される事象について、
現状実装の確認結果と今後の対策方針をまとめる。

## 結論

- 今回のエラーは、AI モデレーション応答を `JSON.parse` している箇所で、
  Gemini の返答が厳密な JSON 形式にならずパースに失敗したことが原因。
- 現状の投稿モデレーションは `Fail Open` 設計のため、
  モデレーション失敗時でも投稿は許可され、`moderationErrors` のみ残る。
- コメント側にも JSON 抽出とパースに依存する類似ロジックがあり、
  失敗形は少し違うが、同系統の不安定さを抱えている。
- 根本対策は、`自由文から JSON を抜き出す` 方針をやめ、
  Gemini の structured output を使ってモデレーション専用の schema を強制すること。

## 今回確認した事象

### 症状

- Firestore `moderationErrors` に以下のようなドキュメントが作成される。
- `error`: `SyntaxError: Unterminated string in JSON at position ...`
- `rawResponse`: Gemini が返した長文の JSON 風テキスト
- 投稿自体は正常に作成される

### 影響

- 投稿作成 UX は継続する
- モデレーション判定が実質スキップされる
- `moderationErrors` が増え続けると運用監視ノイズになる
- モデレーション品質上は「本来止めたい投稿を通す」可能性がある

## 現状実装

### 投稿のテキストモデレーション

対象:

- `functions/src/callable/posts.ts`
- `functions/src/helpers/text-moderation.ts`

流れ:

1. `createPostWithModeration` から `moderateText(...)` を呼ぶ
2. `helpers/text-moderation.ts` が Gemini/OpenAI 共通の `AIProviderFactory.generateText(...)` を呼ぶ
3. 応答文字列から `extractJson(...)` で JSON 部分らしき範囲を抜き出す
4. `JSON.parse(...)` で `ModerationResult` に変換する
5. 例外時は `moderationErrors` に保存し、`blocked: false, flagged: false` を返す

重要な点:

- 投稿側は `Fail Open`
- 例外は Firestore に記録される
- 投稿作成自体は継続する

### コメントのテキストモデレーション

対象:

- `functions/src/callable/comments.ts`

流れ:

1. `createCommentWithModeration` 内のローカル `moderateText(...)` を呼ぶ
2. `AIProviderFactory.generateText(...)` を呼ぶ
3. 正規表現 `\{[\s\S]*\}` で JSON らしき部分を抽出する
4. `JSON.parse(...)` する
5. 失敗時はログ出力のみで、`isNegative: false` を返す

重要な点:

- コメント側も実質 `Fail Open`
- ただし `moderationErrors` への保存はしていない
- 投稿側と実装が重複している
- エラー時の監視性が投稿側と揃っていない

## 原因分析

### 直接原因

今回の `SyntaxError: Unterminated string` は、
Gemini が返した文字列が「JSON っぽいが厳密な JSON ではない」ために起きる。

典型例:

- 文字列内の `"` が未エスケープ
- 改行が文字列リテラル内にそのまま入る
- JSON の前後に説明文が混ざる
- コードブロックや補足文が混ざる
- 応答途中で打ち切られ、閉じカッコや閉じ引用符が不足する

### 構造的な原因

1. 現状は `generateText()` で自由文生成をしている
2. その結果を `extractJson()` や正規表現で無理に JSON 化している
3. schema validation がない
4. モデレーション専用の structured output 経路がない
5. コメント側と投稿側でモデレーション実装が二重化している

## なぜ投稿は成功したのか

`functions/src/helpers/text-moderation.ts` は、AI 失敗時に
`Moderation failed for post, allowing (fail-open)` の挙動を取る。

つまり今回の結果は以下。

1. Gemini 応答をパースしようとして失敗
2. `moderationErrors` に記録
3. モデレーション結果を「問題なし」とみなして返却
4. 投稿保存はそのまま継続

このため「モデレーションエラーは出たが投稿はできた」という状態になる。

## リスク整理

### セキュリティ・安全性

- 不適切投稿を止められないケースが増える
- 特に AI 応答が不安定な時間帯や長文入力で抜けが発生し得る

### 運用

- `moderationErrors` が増え、運用監視ノイズになる
- 原因が AI 側なのかプロンプト側なのかコード側なのかを切り分けづらい

### 品質

- 投稿とコメントで挙動が揃っていない
- 将来の調整時に片方だけ修正されるリスクがある

## 対策方針

### 優先度 A: Gemini structured output へ移行

最優先の根本対策。

やること:

- モデレーション専用の返却 schema を定義する
- Gemini 呼び出しに `application/json` と schema を指定する
- `text-moderation.ts` は自由文の JSON 抽出をやめて、
  schema 準拠の構造化レスポンスを受ける
- コメント側も同じ経路に統一する

期待効果:

- フォーマット崩れを大幅に減らせる
- `extractJson()` と正規表現抽出を廃止できる
- 投稿/コメントの判定品質を揃えられる

注意点:

- structured output でも 100% 無故障にはならない
- API エラー、拒否、タイムアウト、途中終了は別途考慮が必要

### 優先度 B: schema validation をサーバー側で必須化

structured output へ移行しても、受信結果の validation は残す。

やること:

- `isNegative`
- `category`
- `confidence`
- `reason`
- `suggestion`

について必須・型・許容値をチェックする。

期待効果:

- 「JSON としては valid だが、意味的に不正」な応答を弾ける

### 優先度 C: 軽い再試行を 1 回入れる

一時的な応答崩れに対しては、1 回だけ再試行を入れる価値がある。

推奨:

- 同一リクエスト内で 1 回のみ再試行
- 2 回目も失敗したら記録して既存方針へ移る

注意点:

- 再試行回数を増やしすぎると遅延とコストが増える

### 優先度 D: 投稿とコメントのモデレーションを共通化

現状は投稿が `helpers/text-moderation.ts`、コメントが `callable/comments.ts` の
ローカル関数で分かれている。

やること:

- コメントも `helpers/text-moderation.ts` を使う
- モデレーション失敗時の記録方式を統一する
- 返却型と判定閾値を一元化する

期待効果:

- 二重修正漏れを防げる
- 運用ログの見方を揃えられる

### 優先度 E: ログ・監視の整備

やること:

- `moderationErrors` に `provider`, `usedFallback`, `type`, `parseStage` を保存
- 同一種別エラーの件数を日別に追えるようにする
- `rawResponse` は必要最小限にする

期待効果:

- 「Gemini 応答崩れ」か「コード不備」かを切り分けやすくなる
- ログ量過多も抑制できる

## Fail Open / Fail Closed の判断

現状:

- 投稿テキスト: `Fail Open`
- コメントテキスト: 実質 `Fail Open`
- 投稿作成前の API キー未設定だけは `Fail Closed`

当面の推奨:

- まずは `Fail Open` を維持
- ただし structured output + validation + 1 回再試行を入れて、
  そもそもの失敗率を先に下げる

理由:

- いきなり `Fail Closed` にすると、AI 側の一時障害で通常投稿まで止まる
- 現状は UX 影響が大きすぎる

再検討条件:

- structured output 化後も失敗率が高い
- もしくは安全性優先で投稿ブロックを強める意思決定が入る

## 推奨実装ステップ

### Phase 1

- Gemini モデレーション専用 schema を設計
- Gemini structured output を呼ぶ専用メソッドを `AIProvider` に追加
- 投稿側の `helpers/text-moderation.ts` を置き換える

### Phase 2

- コメント側のローカル `moderateText(...)` を廃止
- 投稿とコメントを同じ helper に統一
- `moderationErrors` の記録項目を整理

### Phase 3

- 1 回だけ再試行を追加
- 失敗率監視を整備
- 必要なら fail-open の継続可否を見直す

## 対象ファイル

- `functions/src/helpers/text-moderation.ts`
- `functions/src/callable/comments.ts`
- `functions/src/ai/provider.ts`
- `functions/src/types.ts`
- `functions/src/config/messages.ts`
- `functions/src/config/collections.ts`

必要に応じて:

- `docs/design/moderation_feature_design.md`
- `docs/cloud_functions_reference.md`

## 想定される実装後の確認観点

- 長文投稿でも `moderationErrors` が発生しないか
- 日本語テキストで schema 準拠 JSON が安定して返るか
- 投稿とコメントで同じ閾値・同じ保存先・同じ例外方針になっているか
- Gemini 失敗時に fallback 使用有無がログで追えるか
- `rawResponse` の保存量が過剰でないか

## 今回の整理

### 何が分かったか

- 原因は AI 応答の非構造化 JSON
- 現状は投稿成功を優先する fail-open 設計
- コメント側にも類似の不安定な実装がある

### 今回は何をしないか

- 実装変更
- fail-open / fail-closed の即時変更
- Gemini SDK 差し替え

### 次に着手するなら

- Gemini structured output 化
- 投稿/コメントのモデレーション共通化
- `moderationErrors` 記録項目の改善
