# Stamp Sheet Assets Guide

スタンプシート台紙を追加したときの運用手順です。  
リアクション/アバターと同様に、アセット追加後にスクリプト実行で Firestore 設定を差分同期します。

## 命名規則

- ファイル: `assets/stamp_sheets/<sheetId>_<rarity>.png`
- `rarity`: `common` / `rare` / `epic`
- レイアウトJSON: `assets/stamp_sheets/layouts/<sheetId>.json`

例:

- `assets/stamp_sheets/celebrate_common.png`
- `assets/stamp_sheets/celebrate_rare.png`
- `assets/stamp_sheets/layouts/celebrate.json`

## 重要ルール

- `sheetId` は英数字と `_` のみ
- 同じ `sheetId` の画像は1つだけ（同時に複数レア度は不可）
- 対応する `layouts/<sheetId>.json` がない場合、スクリプトはエラー終了
- 画像が削除された `sheetId` は Firestore から**完全削除**

## 実行コマンド

事前確認（Firestore変更なし）:

```bash
node functions/scripts/register-stamp-sheets.js --dry-run --no-firestore
```

本実行:

```bash
node functions/scripts/register-stamp-sheets.js
```

## オプション

- `--rare-cost <number>`: `settings/virtueShop.stampSheetCostsByRarity.rare` を更新
- `--epic-cost <number>`: `settings/virtueShop.stampSheetCostsByRarity.epic` を更新
- `--dry-run`: 更新内容のプレビューのみ
- `--no-firestore`: Firestore 更新をスキップ
- `--assets <path>`: 台紙フォルダを変更
- `--layouts <path>`: レイアウトフォルダを変更

## スクリプトが更新する Firestore

- `settings/stampSheetCatalog.sheets`
  - `id`, `assetPath`, `rarity`, `displayOrder`, `isActive`
- `settings/stampSheetLayoutCatalog.layouts`
  - `sheetId`, `layoutAssetPath`, `version`, `isActive`
- `settings/virtueShop.stampSheetCostsByRarity`
  - 既存値を保持。`--rare-cost` / `--epic-cost` 指定時のみ更新

## 反映確認

1. スクリプト実行後、`stampSheetCatalog` / `stampSheetLayoutCatalog` の内容を確認
2. アプリを再起動（新規アセット追加時はホットリロードだけでは反映されない場合あり）
3. スタンプ画面で台紙が選べることを確認
4. 枠タップでスタンプ押印できることを確認
