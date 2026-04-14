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
- 形式: `<id>_<rarity>.webp`（入力は `.png` も可 — スクリプト実行時に自動でWebPへ変換）
- `rarity`: `common` / `rare` / `epic`
- 例:
  - `eyebrows_01_common.webp`
  - `eyebrows_02_rare.webp`
  - `eyebrows_03_epic.webp`

注意:
- アバターはレア度別価格統一運用のため、`_rare_100` のような価格付きファイル名は**エラー**になります。
- 同じ `<id>` が複数ファイルで重複すると**エラー**になります。
- `<id>` はパーツ接頭辞を必須とします（例: eyebrows フォルダなら `eyebrows_...`）。
- PNGで配置した場合、スクリプト実行時にImageMagickでWebPへ自動変換され、元のPNGは削除されます。

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

## 整合チェック

```bash
npm run check:avatar-parts-sync
```

- `lib/core/constants/avatar_assets.dart` と `functions/src/config/avatar-parts.ts` のレア度定義差分を検出する
- 差分がある場合は commit しない

## 自動更新される対象
- `lib/core/constants/avatar_assets.dart`
  - `hairIds` / `eyebrowsIds` / `eyesIds` / `mouthIds`
  - `partRarity`
  - `partAssetNameById`
- `functions/src/config/avatar-parts.ts`
  - `AVATAR_PART_RARITY`
  - `isEpicAvatarPart`
- Firestore: `settings/virtueShop`
  - `avatarPartCostsByRarity`（`--no-firestore` 指定時は更新しない）

## デプロイ要否
- Firestoreのみ更新（価格だけ変更）:
  - デプロイ不要
- `functions/src/config/avatar-parts.ts` が更新された:
  - Functionsデプロイ必須
  - 手順:
  ```bash
  npm --prefix functions run build
  firebase deploy --only "functions:default:getVirtueShopConfig,functions:default:purchaseVirtueItem,functions:default:onUserUpdated" --project positive-sns
  ```
  - PowerShellでは `--only` の値をダブルクォートで囲む
- `lib/core/constants/avatar_assets.dart` が更新された:
  - アプリ再ビルドが必要（実機確認や次回リリースに反映）

変更有無の確認:
```bash
git diff --name-only
```

確認項目:
- `npm run check:avatar-parts-sync` が成功する
- 徳ショップでレア度・価格が正しい
- サブスク解除時に Epic パーツが common fallback に戻る

## 互換コマンド
既存の以下コマンドも新スクリプトへ委譲されます:
```bash
python scripts/update_avatar_assets.py
```
