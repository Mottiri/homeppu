---
name: codex-review
description: Codex CLI（read-only）を用いて、レビュー→Claude Code修正→再レビュー（ok: true まで）を反復し収束させるレビューゲート。仕様書/SPEC/PRD/要件定義/設計、実装計画（PLANS.md等）の作成・更新直後、major step（>=5 files / 新規モジュール / 公開API / infra・config変更）完了後、および git commit / PR / merge / release 前に使用する。キーワード: Codexレビュー, codex review, レビューゲート.
---

# Codex反復レビュー

## フロー
規模判定 → Codex規模別レビュー → Claude Code修正 → 再レビュー（`ok: true`まで反復）

```
[規模判定]
→ small: diff ──────────────────→ [修正ループ]
→ medium: arch → diff ───────────→ [修正ループ]
→ large: arch → diff並列 → cross-check → [修正ループ]
```

- Codex: read-onlyでレビュー（監査役）
- Claude Code: 修正担当

## ほめっぷ固有のレビュー観点

このプロジェクトでは、以下の追加観点を必ずレビューに含めること：

### 1. コンセプト準拠
- CONCEPT.md に沿った実装か確認
- 「安全な空間」「適度な距離感」「AIバレ防止」の設計原則に反していないか

### 2. 仕様準拠
- FEATURES.md に記載された仕様通りの実装か
- 仕様変更時、旧仕様のコード残骸（コメント、変数、ロジック）が残っていないか

### 3. コード品質
- 無駄な変数・重複関数・未使用インポート
- デバッグ用コード・テスト用print文・console.log の削除確認
- テスト実装（仮データ、モック等）が本番コードに混入していないか

### 4. Dart/Flutter固有
- StatefulWidget と StatelessWidget の適切な使い分け
- dispose() でのリソース解放漏れ
- Provider/Riverpod の適切な使用

## 規模判定

```bash
git diff <diff_range> --stat
git diff <diff_range> --name-status --find-renames
```

| 規模 | 基準 | 戦略 |
|-----|------|-----|
| small | ≤3ファイル、≤100行 | diff |
| medium | 4-10ファイル、100-500行 | arch → diff |
| large | >10ファイル、>500行 | arch → diff並列 → cross-check |

`diff_range` 省略時: HEAD を使用し、作業ツリーの未コミット変更を対象とする。

**large時:**
- 並列: 3-5サブエージェント、各サブは担当ファイルのみ
- 分割: 1呼び出しあたり最大5ファイル/300行、ディレクトリ単位で分割
- 統合はメイン（Claude Code）で実施

## 修正ループ

`ok: false`の場合、`max_iters`回まで反復:
1. `issues`解析 → 修正計画
2. Claude Codeが修正（最小差分のみ、仕様変更は未解決issueに）
3. テスト/リンタ実行（可能なら `flutter analyze`）
4. Codexに再レビュー依頼

停止条件: `ok: true` / `max_iters`到達 / テスト2回連続失敗

## Codex実行

```bash
npx @openai/codex exec --sandbox read-only "<PROMPT>"
```

- PROMPT には（スキーマ含む）最終プロンプトを渡す
- 主要な関連ファイルパスはClaude Codeが明示
- レビュー完了待ち（必須）: codex exec 実行中は次の工程に進まない
- 定期確認: 60秒ごとに最大20回、`poll i/20` と経過時間のみをログし、追加作業はしない
- 20回到達後も未完了なら: 「タイムアウト」扱いでエラー時ルールへ

## Codex出力スキーマ

CodexにJSON1つのみ出力させる。Claude Codeはプロンプト末尾に以下のスキーマを添付。

```json
{
  "ok": true,
  "phase": "arch|diff|cross-check",
  "summary": "レビューの要約",
  "issues": [
    {
      "severity": "blocking",
      "category": "security",
      "file": "lib/auth.dart",
      "lines": "42-45",
      "problem": "問題の説明",
      "recommendation": "修正案"
    }
  ],
  "notes_for_next_review": "メモ"
}
```

フィールド説明:
- `ok`: blockingなissueが0件ならtrue、1件以上ならfalse
- `severity`: 2段階
  - blocking: 修正必須。1件でもあれば`ok: false`
  - advisory: 推奨・警告。`ok: true`でも出力可、レポートに記載のみ
- `category`: correctness / security / perf / maintainability / testing / style / concept-violation（ほめっぷ固有）
- `notes_for_next_review`: Codexが残すメモ。再レビュー時にClaude Codeがプロンプトに含める

## プロンプトテンプレート

### arch
```
以下の変更のアーキテクチャ整合性をレビューせよ。出力はJSON1つのみ。スキーマは末尾参照。
これはレビューゲートとして実行されている。blocking が1件でもあれば ok: false とし、修正→再レビューで収束させる前提で指摘せよ。

プロジェクト: ほめっぷ（Flutter SNSアプリ）
コンセプト: 「頑張る人を褒めて応援するSNS」- 安全な空間、適度な距離感、AIバレ防止

diff_range: {diff_range}
観点: 依存関係、責務分割、破壊的変更、セキュリティ設計、CONCEPT.md準拠
前回メモ: {notes_for_next_review}
```

### diff
```
以下の変更をレビューせよ。出力はJSON1つのみ。スキーマは末尾参照。
これはレビューゲートとして実行されている。blocking が1件でもあれば ok: false とし、修正→再レビューで収束させる前提で指摘せよ。

プロジェクト: ほめっぷ（Flutter SNSアプリ）

diff_range: {diff_range}
対象: {target_files}
観点: {review_focus}

追加観点（ほめっぷ固有）:
- テスト/デバッグコードの残骸
- 旧仕様のコード残骸
- 未使用変数/インポート
- CONCEPT.md/FEATURES.md への準拠

前回メモ: {notes_for_next_review}
```

### cross-check
```
並列レビュー結果を統合し横断レビューせよ。出力はJSON1つのみ。スキーマは末尾参照。
これはレビューゲートとして実行されている。横断的な blocking があれば ok: false とせよ。

全体stat: {stat_output}
各グループ結果: {group_jsons}
観点: interface整合、error handling一貫性、認可、API互換、テスト網羅
```

## エラー時の共通ルール

Codex exec失敗時（タイムアウト・API障害・その他）:
1. 1回リトライ（タイムアウトはファイル数を半分に分割して）
2. 再失敗 → 該当フェーズをスキップし、理由をレポートに記録
3. archスキップ時はdiffのみで続行、diffスキップ時はそのファイル群を「未レビュー」としてレポート

## パラメータ

| 引数 | 既定 | 説明 |
|-----|-----|-----|
| max_iters | 5 | 最大反復（上限5） |
| review_focus | - | 重点観点 |
| diff_range | HEAD | 比較範囲 |
| parallelism | 3 | large時並列度（上限5） |

## 終了レポート例

```
## Codexレビュー結果
- 規模: medium（6ファイル、280行）
- 反復: 2/5 / ステータス: ✅ ok

### 修正履歴
- auth_provider.dart: 未使用インポート削除
- post_service.dart: デバッグprint文削除

### Advisory（参考）
- reaction_service.dart: 関数名がやや冗長、リファクタ推奨

### 未レビュー（エラー時のみ）
- なし

### 未解決（あれば）
- なし
```
