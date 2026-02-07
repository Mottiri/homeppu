# Avatar Assets Guide

アバターパーツ追加時の運用手順です。  
リアクションスタンプと同じ考え方で、**差分更新 + 既存削除連動**を行います。

## 対象フォルダ
- `assets/avatars/hair/`
- `assets/avatars/eyebrows/`
- `assets/avatars/eyes/`
- `assets/avatars/mouth/`

`assets/avatars` 配下は再帰走査されるため、上記フォルダ配下のサブフォルダに置いても対象になります。

## 命名規則
- 形式: `<id>_<rarity>.png`
- `rarity`: `common` / `rare` / `epic`
- 例:
  - `eyebrows_01_common.png`
  - `eyebrows_02_rare.png`
  - `eyebrows_03_epic.png`

注意:
- アバターはレア度別価格統一運用のため、`_rare_100` のような価格付きファイル名は**エラー**になります。
- 同じ `<id>` が複数ファイルで重複すると**エラー**になります。
- `<id>` はパーツ接頭辞を必須とします（例: eyebrows フォルダなら `eyebrows_...`）。

## 実行コマンド
まず差分確認:
```bash
node functions/scripts/register-avatar-parts.js --dry-run --no-firestore
```

本適用:
```bash
node functions/scripts/register-avatar-parts.js
```

価格を同時設定したい場合（任意）:
```bash
node functions/scripts/register-avatar-parts.js --rare-cost 100
```

## 自動更新される対象
- `lib/core/constants/avatar_assets.dart`
  - `hairIds` / `eyebrowsIds` / `eyesIds` / `mouthIds`
  - `partRarity`
  - `partAssetNameById`
- `functions/src/callable/virtue_shop.ts`
  - `AVATAR_PART_RARITY`
- Firestore: `settings/virtueShop`
  - `avatarPartCostsByRarity`（`--no-firestore` 指定時は更新しない）

## デプロイ要否
- Firestoreのみ更新（価格だけ変更）:
  - デプロイ不要
- `functions/src/callable/virtue_shop.ts` が更新された:
  - Functionsデプロイ必須
  - 例:
  ```bash
  firebase deploy --only functions:getVirtueShopConfig,functions:purchaseVirtueItem
  ```
- `lib/core/constants/avatar_assets.dart` が更新された:
  - アプリ再ビルドが必要（実機確認や次回リリースに反映）

変更有無の確認:
```bash
git diff --name-only
```

## 互換コマンド
既存の以下コマンドも新スクリプトへ委譲されます:
```bash
python scripts/update_avatar_assets.py
```
