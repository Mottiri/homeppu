---
trigger: always_on
---

---
description: Codexレビューゲートの必須実行ルール
globs: ["**/*.dart", "**/*.ts", "**/*.tsx"]
---

# Review Gate (codex-review)

## 必須タイミング

以下のタイミングで **必ず codex-review SKILL を実行**すること：

1. **仕様書・設計更新後**
   - CONCEPT.md, FEATURES.md, 実装計画の作成・更新直後

2. **Major Step 完了後**
   - 5ファイル以上の変更
   - 新規モジュール・公開APIの追加
   - Firebase Functions・infra・config 変更

3. **コミット・PR・リリース前**
   - git commit 前
   - PR 作成前
   - release 前

## 実行方法

```
codex-review SKILL を実行し、review → fix → re-review のサイクルを ok: true になるまで反復せよ。
```

## レビュー観点（ほめっぷ固有）

- CONCEPT.md への準拠（安全な空間、距離感、AIバレ防止）
- FEATURES.md の仕様準拠
- テスト/デバッグコードの残骸削除
- 旧仕様のコード残骸削除
- 未使用変数・インポートの削除
