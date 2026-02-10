# 文字コードとメッセージ管理ルール

最終更新: 2026-02-08

## 1. 文字コードルール（必須）
- ソースコードとドキュメントは `UTF-8 (BOMなし)` で保存する
- 改行コードは `LF` を基本とする
- PowerShellで `>` リダイレクトを使ってファイル生成/上書きしない
  - `>` は環境により意図しないエンコーディングになるため
- ファイル編集は `apply_patch` またはエディタ保存を使う
- PowerShellで内容を書き込む場合は `Set-Content -Encoding utf8` を使う

## 2. 文字化けチェック（コミット前）
- 実行コマンド: `npm run check:mojibake`
- 対象: `lib`, `functions/src`, `functions/package.json`, `docs`, `scripts`, `firebase`, `AGENTS.md`, `package.json`
- 文字化け疑い（半角カナ・代表的な崩れトークン・置換文字 `U+FFFD`）を検出して失敗させる
- Git hook: `.githooks/pre-commit` で自動実行
- 初回設定: `npm run setup:hooks`（`core.hooksPath=.githooks`）

## 3. メッセージ管理ルール（必須）
- Flutter UIで表示する文言:
  - `lib/core/constants/app_messages.dart` に集約する
  - Widget内にハードコードしない
- Cloud Functions側で使う文言:
  - `functions/src/config/messages.ts` に集約する
  - サーバー内部ログ/エラー文言は Functions 側定数を使う
- クライアントに見せるエラー:
  - 可能な限り `code`（または識別可能なキー）で受け取り、Flutter側で `AppMessages` にマッピングする
  - 直接サーバー文言をそのまま表示する実装は最小限にする

## 4. 実務チェックリスト
- `npm run check:mojibake`
- `flutter analyze`
- `functions` 変更時は `npm.cmd run build`（`functions/` 配下）
