# リアクションスタンプ追加手順

## 概要
- `assets/reactions` にアセットを追加し、スクリプトで登録します。
- ファイル名から **レア度** と **価格** を自動判定します。
- 既存スタンプは **スキップ** されますが、ファイル名変更（レア度変更）時は更新されます。
- 実行ログで `Added/Updated/Skipped` が確認できます。

## ファイル命名ルール
```
<id>_<rarity>.webp
<id>_<rarity>_<cost>.webp
```

- `rarity`: `common` / `rare` / `epic`
- `cost`: rare のときのみ必要（例: 100）
- 入力は `.png` も可 — スクリプト実行時にImageMagickでWebPへ自動変換され、元のPNGは削除されます

例:
```
clap_common.webp
sparkle_epic.webp
cracker_rare_120.webp
```

## スクリプト実行
```
node functions/scripts/register-reaction-stamps.js
```

### オプション
- `--default-rare-cost 100`
  - rare で cost を省略した場合に使うデフォルト価格
- `--dry-run`
  - 変更内容のプレビューのみ
- `--no-firestore`
  - Firestore の `settings/virtueShop` 更新をスキップ
- `--assets <path>`
  - 走査するアセットディレクトリを指定

## 実行ログの例
```
=== Summary ===
Added: 1
- cracker
Updated: 0
Skipped (no rarity suffix): 2
- clap
- heart
Done.
```

## 既存スタンプの扱い
- `assets/reactions` に存在するものだけを登録対象にします。
- 既存スタンプは **スキップ** されます。
- ただし、同じ `id` で **ファイル名が変わった場合**は更新対象になります。
  - 例: `clap_common.webp` → `clap_rare_100.webp` に変更した場合、`clap` が rare として更新されます。
