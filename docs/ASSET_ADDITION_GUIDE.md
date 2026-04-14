# アセット追加ガイド

アバターパーツ・リアクションスタンプ・スタンプシート・名前パーツの追加手順をまとめた統合ガイドです。

## 共通前提

- アセットは **PNG / WebP** どちらでも配置可能
- PNGで配置した場合、スクリプト実行時にImageMagickで自動WebP変換され、元のPNGは削除される
- ImageMagickが未インストールでもWebPのみの環境では問題なし（変換が不要なため）
- スクリプトはすべて `functions/` ディレクトリから実行する

### ImageMagickのインストール

PNGで追加する場合のみ必要です。

- https://imagemagick.org/ からインストール
- `magick --version` でPATHが通っていることを確認

---

## 1. アバターパーツ

### 配置先

```
assets/avatars/
├── base/       # ベースアバター
├── eyebrows/   # 眉毛
├── eyes/       # 目
├── hair/       # 髪型
└── mouth/      # 口
```

### 命名規則

```
<パーツ種別>_<番号>_<rarity>.png
```

- `rarity`: `common` / `rare` / `epic`
- commonの場合はrarity省略可
- `<id>` はパーツ種別の接頭辞が必須（例: eyebrowsフォルダなら `eyebrows_...`）
- 価格付きファイル名（`_rare_100` など）は**エラー**（アバターはレア度別価格統一運用）

### 例

```
eyebrows_22_rare.png
hair_16_epic.png
eyes_17.png            ← commonは省略可
mouth_08_common.png
```

### スクリプト実行

```bash
cd functions

# プレビュー（Firestoreに書き込まない）
node scripts/register-avatar-parts.js --dry-run --no-firestore

# 本番実行
node scripts/register-avatar-parts.js

# レア度別価格を同時設定（任意）
node scripts/register-avatar-parts.js --rare-cost 100
```

### 整合チェック

```bash
npm run check:avatar-parts-sync
```

- `lib/core/constants/avatar_assets.dart` と `functions/src/config/avatar-parts.ts` のレア度定義差分を検出する
- 差分がある場合は commit しない

### 自動更新される対象

| 対象 | 内容 |
|------|------|
| `lib/core/constants/avatar_assets.dart` | パーツIDリスト・レア度マップ・アセット名マップ |
| `functions/src/config/avatar-parts.ts` | Functions 共通レア度マップ（購入判定・サブスク解除時フォールバックで共有） |
| Firestore `settings/virtueShop` | レア度別価格（`--no-firestore` で省略可） |

---

## 2. リアクションスタンプ

### 配置先

```
assets/reactions/
```

### 命名規則

```
<id>_<rarity>.png
<id>_<rarity>_<cost>.png
```

- `rarity`: `common` / `rare` / `epic`
- `cost`: rareのときのみ必要（例: 100）

### 例

```
thumbsup_common.png
firework_rare_120.png
crown_epic.png
```

### スクリプト実行

```bash
cd functions

# プレビュー
node scripts/register-reaction-stamps.js --dry-run --no-firestore

# 本番実行
node scripts/register-reaction-stamps.js

# rareのデフォルト価格を指定（cost省略時に使用）
node scripts/register-reaction-stamps.js --default-rare-cost 100
```

### 自動更新される対象

| 対象 | 内容 |
|------|------|
| `lib/core/constants/app_constants.dart` | リアクション定義リスト |
| Firestore `settings/virtueShop` | レア度別価格（`--no-firestore` で省略可） |

---

## 3. スタンプシート

### 配置先

```
assets/stamp_sheets/
├── <sheetId>_<rarity>.png    # 台紙画像
└── layouts/
    └── <sheetId>.json        # レイアウト定義（必須）
```

### 命名規則

- 画像: `<sheetId>_<rarity>.png`
- レイアウト: `layouts/<sheetId>.json`
- `sheetId` は英数字と `_` のみ
- 同じ `sheetId` の画像は1つだけ（同時に複数レア度は不可）
- 対応するレイアウトJSONがない場合はデフォルトレイアウト（5×4グリッド、20スロット）が自動生成される

### 例

```
sakura_common.png
layouts/sakura.json
```

### レイアウトJSONのテンプレート

```json
{
  "sheetId": "sakura",
  "version": 1,
  "aspectRatio": 0.8,
  "slots": [
    { "slotId": "slot_01", "x": 0.15, "y": 0.20, "w": 0.20, "h": 0.20 },
    { "slotId": "slot_02", "x": 0.40, "y": 0.20, "w": 0.20, "h": 0.20 },
    { "slotId": "slot_03", "x": 0.65, "y": 0.20, "w": 0.20, "h": 0.20 },
    { "slotId": "slot_04", "x": 0.15, "y": 0.50, "w": 0.20, "h": 0.20 },
    { "slotId": "slot_05", "x": 0.40, "y": 0.50, "w": 0.20, "h": 0.20 },
    { "slotId": "slot_06", "x": 0.65, "y": 0.50, "w": 0.20, "h": 0.20 }
  ]
}
```

| フィールド | 説明 |
|-----------|------|
| `sheetId` | 台紙ID（ファイル名と一致させる） |
| `version` | レイアウトバージョン（通常1） |
| `aspectRatio` | 台紙のアスペクト比（幅/高さ） |
| `slots[].slotId` | スタンプ配置スロットのID |
| `slots[].x, y` | スロット中心の相対位置（0.0〜1.0） |
| `slots[].w, h` | スロットの相対サイズ（0.0〜1.0） |

### スクリプト実行

```bash
cd functions

# プレビュー
node scripts/register-stamp-sheets.js --dry-run --no-firestore

# 本番実行
node scripts/register-stamp-sheets.js

# レア度別価格を設定（任意）
node scripts/register-stamp-sheets.js --rare-cost 200 --epic-cost 500
```

### 自動更新される対象

| 対象 | 内容 |
|------|------|
| Firestore `settings/stampSheetCatalog` | シート一覧（id, assetPath, rarity, displayOrder, isActive） |
| Firestore `settings/stampSheetLayoutCatalog` | レイアウト一覧（sheetId, layoutAssetPath, version, isActive） |
| Firestore `settings/virtueShop` | レア度別価格（`--no-firestore` で省略可） |

---

## 4. 名前パーツ

名前パーツはテキストベース（画像なし）のため、アセットファイルの配置は不要です。
Firestoreに反映すれば**アプリ再ビルドなしで即反映**されます。

### データ構造

名前パーツは「形容詞（prefix）」+「名詞（suffix）」の組み合わせでユーザー名を構成します。

| 種別 | 例 |
|------|-----|
| prefix（形容詞） | がんばる、もふもふ、伝説の |
| suffix（名詞） | 🐰うさぎ、チャレンジャー、勇者 |

### 追加手順

**1. `functions/src/ai/personas.ts` を編集**

PREFIX_PARTS（形容詞）または SUFFIX_PARTS（名詞）に新しいパーツを追加します。

```typescript
// 形容詞を追加する場合（PREFIX_PARTS 配列に追記）
{ id: "pre_26", text: "ふわふわ", category: "relaxed", rarity: "rare", order: 26 },

// 名詞を追加する場合（SUFFIX_PARTS 配列に追記）
{ id: "suf_31", text: "🦈サメ", category: "animal", rarity: "rare", order: 31 },
```

| フィールド | 説明 | 値 |
|-----------|------|----|
| `id` | 一意のID | prefix: `pre_XX`、suffix: `suf_XX` |
| `text` | 表示テキスト | 絵文字使用可 |
| `category` | カテゴリ | `positive`, `relaxed`, `effort`, `animal`, `funny`, `legendary`, `nature`, `food`, `occupation` |
| `rarity` | レアリティ | `common`（無料）/ `rare`（徳ポイント購入）/ `epic`（サブスク or 購入） |
| `order` | 表示順 | 数値（昇順） |

**2. ビルド**

```bash
cd functions
npm run build
```

**3. スクリプト実行**

```bash
cd functions

# ソースデータの確認のみ（Firestoreアクセスなし）
node scripts/sync-name-parts.js --dry-run --no-firestore

# Firestoreとの差分プレビュー
node scripts/sync-name-parts.js --dry-run

# 追加・更新を実行
node scripts/sync-name-parts.js

# 削除も含めて実行
node scripts/sync-name-parts.js --delete
```

### 既存パーツの変更

`personas.ts` のパーツの `text`, `category`, `rarity`, `order` を変更し、同じ手順でビルド→スクリプト実行します。

### パーツの削除

`personas.ts` から該当パーツを削除し、ビルド→スクリプト実行（`--delete` フラグ必須）します。

```bash
node scripts/sync-name-parts.js --delete
```

**注意**: 削除対象のパーツをユーザーが購入済み or 使用中の場合は警告が表示されます。

### 自動更新される対象

| 対象 | 内容 |
|------|------|
| Firestore `nameParts` コレクション | パーツ定義（id, text, category, rarity, order, type） |

### デプロイ要否

| 変更内容 | 必要な対応 |
|---------|-----------|
| パーツ追加・変更・削除 | **デプロイ不要**（Firestore更新のみで即反映） |
| personas.ts の変更（AI用） | Functionsデプロイ必須（AIが新パーツを使う場合） |

---

## 共通の作業フロー

```
1. アセットファイル（PNG or WebP）を所定のフォルダに配置
     ↓
2. cd functions
     ↓
3. --dry-run --no-firestore でプレビュー確認
     ↓
4. 問題なければ本番実行（PNG→WebP自動変換 + 定数/Firestore更新）
     ↓
5. git add → コミット → プッシュ
     ↓
6. 必要に応じてデプロイ
```

## デプロイ要否の判断

| 変更内容 | 必要な対応 |
|---------|-----------|
| Firestoreのみ更新（価格変更等） | デプロイ不要 |
| `avatar-parts.ts` が更新された | Functionsデプロイ必須 |
| Dart定数ファイルが更新された | アプリ再ビルド |
| アセットのみ追加（定数変更なし） | アプリ再ビルド |
| 名前パーツ追加・変更・削除 | デプロイ不要（Firestore即反映） |

### Functionsデプロイコマンド

```bash
npm --prefix functions run build
firebase deploy --only "functions:default:getVirtueShopConfig,functions:default:purchaseVirtueItem,functions:default:onUserUpdated" --project positive-sns
```

## 反映確認

1. スクリプト実行後、`git diff --name-only` で変更ファイルを確認
2. `npm run check:avatar-parts-sync` が成功することを確認
3. アプリを再起動して新規アセットが表示されることを確認
4. 徳ショップでレア度・価格が正しいことを確認（アバター/リアクション）
5. サブスク解除時に Epic パーツが common fallback に戻ることを確認
6. スタンプシート追加時は、シート切替・スタンプ押印・アーカイブ表示を確認
7. 名前パーツ追加時は、名前編集画面で新パーツが表示されることを確認（アプリ再起動で反映）
