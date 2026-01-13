# ハードコード技術負債リスト

## 概要

バイブコーディング時の一貫性を保つため、ハードコードを定数に置き換える作業リストです。

## 優先度: 高（リファクタリング時に必須対応）

### 1. リージョン設定 `"asia-northeast1"`

| ファイル | 箇所数 | ステータス |
|---------|--------|-----------|
| `index.ts` | 38 | Phase 5-7で対応 |
| `callable/names.ts` | 0 | ✅ 対応済 |
| `callable/reports.ts` | 0 | ✅ 対応済 |
| `callable/tasks.ts` | 0 | ✅ 対応済 |
| `callable/inquiries.ts` | 0 | ✅ 対応済 |
| `callable/circles.ts` | 0 | ✅ Phase 4で対応済 |
| `triggers/circles.ts` | 0 | ✅ Phase 4で対応済 |
| `circle-ai/posts.ts` | 0 | ✅ Phase 4で対応済 |
| `scheduled/circles.ts` | 0 | ✅ Phase 4で対応済 |

**対応方法**:
```typescript
import { LOCATION } from "../config/constants";
// region: "asia-northeast1" → region: LOCATION
```

---

## 優先度: 中（将来的に対応推奨）

### 2. エラーメッセージ（104箇所）

同じエラーメッセージが複数箇所でハードコードされています。

**よく使われるメッセージ**:
- `"ログインが必要です"` - 約30箇所
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

### 3. コレクション名（116箇所）

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

### 4. 関数タイムアウト設定（21箇所）

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

### 5. メモリ設定（9箇所）

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

### リファクタリング各Phase完了時

1. 新規作成ファイルでは `LOCATION` 定数を必ず使用
2. 既存コードからの移植時にハードコードを発見したら定数に置換
3. Phase完了後、このドキュメントのステータスを更新

### 新規Cloud Functions作成時

1. `.claude/rules/no_hardcode.md` のルールに従う
2. `region: LOCATION` を必ず使用
3. `db` は `helpers/firebase.ts` からインポート

---

## 即時対応が必要なケース

以下の場合は、Phase作業に関係なく即時対応してください：

1. **セキュリティに関わる設定**
   - サービスアカウントのメールアドレス
   - 認証関連のURL

2. **環境依存の設定**
   - プロジェクトID
   - リージョン（`LOCATION`）

3. **頻繁に変更される可能性がある値**
   - 外部APIのエンドポイント
   - レート制限の閾値
