# ハードコード技術負債リスト

## 概要

バイブコーディング時の一貫性を保つため、ハードコードを定数に置き換える作業リストです。

## 対応完了

### 1. リージョン設定 ✅ (2026-01-15完了)

**全27箇所を `LOCATION` 定数に置換完了**

| ファイル | 対応状況 |
|---------|----------|
| `index.ts` | ✅ 対応済 |
| `callable/admin.ts` | ✅ 対応済 |
| `callable/users.ts` | ✅ 対応済 |
| `scheduled/cleanup.ts` | ✅ 対応済 |
| `triggers/notifications.ts` | ✅ 対応済 |
| `triggers/posts.ts` | ✅ 対応済（serviceAccountも定数化）|

### 2. AIプロンプト ✅ (2026-01-15完了)

**`ai/prompts/` ディレクトリに分離完了**

| ファイル | 内容 |
|---------|------|
| `prompts/comment.ts` | getSystemPrompt, getCircleSystemPrompt |
| `prompts/moderation.ts` | 画像/動画/テキストモデレーションプロンプト |
| `prompts/media-analysis.ts` | 画像/動画分析プロンプト |
| `prompts/post-generation.ts` | AI投稿生成プロンプト |
| `prompts/bio-generation.ts` | bio生成プロンプト |
| `prompts/index.ts` | 統合エクスポート |

---

## 優先度: 中（将来的に対応推奨）

### 3. エラーメッセージ（50+箇所）

同じエラーメッセージが複数箇所でハードコードされています。

**よく使われるメッセージ**:
- `"ログインが必要です"` - 約25箇所
- `"管理者権限が必要です"` - 約16箇所
- `"ユーザーが見つかりません"` - 約10箇所

**将来の対応**:
```typescript
// helpers/errors.ts を作成
export const ErrorMessages = {
  UNAUTHENTICATED: "ログインが必要です",
  ADMIN_REQUIRED: "管理者権限が必要です",
  USER_NOT_FOUND: "ユーザーが見つかりません",
  // ...
} as const;
```

### 4. コレクション名（116箇所）

Firestoreコレクション名がハードコードされています。

**頻出コレクション**:
- `"users"` - 約50箇所
- `"posts"` - 約30箇所
- `"circles"` - 約20箇所
- `"notifications"` - 約15箇所

**将来の対応**:
```typescript
// config/collections.ts を作成
export const Collections = {
  USERS: "users",
  POSTS: "posts",
  CIRCLES: "circles",
  NOTIFICATIONS: "notifications",
  // サブコレクション
  USER_NOTIFICATIONS: (userId: string) => `users/${userId}/notifications`,
} as const;
```

---

## 優先度: 低（余裕があれば対応）

### 5. 関数タイムアウト設定（21箇所）

```typescript
// 現状: バラバラな設定
timeoutSeconds: 60
timeoutSeconds: 120
timeoutSeconds: 300
timeoutSeconds: 540

// 将来: 標準化
export const Timeouts = {
  DEFAULT: 60,
  MEDIUM: 120,
  HEAVY: 300,
  MAX: 540,
} as const;
```

### 6. メモリ設定（9箇所）

```typescript
// 現状
memory: "256MiB"
memory: "512MiB"
memory: "1GB"

// 将来: 標準化
export const Memory = {
  SMALL: "256MiB",
  MEDIUM: "512MiB",
  LARGE: "1GB",
} as const;
```

---

## 対応ルール

### 新規Cloud Functions作成時

1. `region: LOCATION` を必ず使用
2. `db` は `helpers/firebase.ts` からインポート
3. プロンプトは `ai/prompts/` に追加
4. エラーメッセージは将来的に定数化予定

### 即時対応が必要なケース

以下の場合は、Phase作業に関係なく即時対応してください：

1. **セキュリティに関わる設定**
   - サービスアカウントのメールアドレス → `PROJECT_ID` 定数使用
   - 認証関連のURL

2. **環境依存の設定**
   - プロジェクトID → `PROJECT_ID`
   - リージョン → `LOCATION`

3. **頻繁に変更される可能性がある値**
   - 外部APIのエンドポイント
   - レート制限の閾値
