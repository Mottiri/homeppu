---
description: ハードコード防止ルール - 定数の一元管理
globs: ["functions/src/**/*.ts"]
---

# ハードコード防止ルール

Firebase Cloud Functionsのコードで、以下の値をハードコードしてはいけません。
必ず定義済みの定数を使用してください。

## 必須: config/constants.ts から使用

```typescript
import { PROJECT_ID, LOCATION } from "../config/constants";
```

| ハードコードNG | 定数を使用 |
|---------------|-----------|
| `"asia-northeast1"` | `LOCATION` |
| `"positive-sns"` | `PROJECT_ID` |
| `"generateAICommentV1"` | `CLOUD_TASK_FUNCTIONS.generateAICommentV1` |

## 必須: helpers/firebase.ts から使用

```typescript
import { db, FieldValue, Timestamp, auth, storage } from "../helpers/firebase";
```

| ハードコードNG | 正しい使用法 |
|---------------|-------------|
| `admin.firestore()` | `db` |
| `admin.firestore.FieldValue` | `FieldValue` |
| `admin.firestore.Timestamp` | `Timestamp` |

## 推奨: エラーメッセージの定数化

現在104箇所でエラーメッセージがハードコードされています。
将来的に `helpers/errors.ts` で一元管理を検討してください。

```typescript
// 現状（NG）
throw new HttpsError("unauthenticated", "ログインが必要です");

// 将来（推奨）
throw new HttpsError("unauthenticated", ErrorMessages.UNAUTHENTICATED);
```

## 推奨: コレクション名の定数化

現在116箇所でコレクション名がハードコードされています。
将来的に定数化を検討してください。

```typescript
// 現状（許容）
db.collection("users").doc(userId)

// 将来（推奨）
db.collection(Collections.USERS).doc(userId)
```

## 推奨: 関数設定の標準化

タイムアウトやメモリ設定を標準化することで、一貫性を保てます。

```typescript
// config/function-config.ts（将来作成を検討）
export const FunctionConfig = {
  default: { region: LOCATION, timeoutSeconds: 60, memory: "256MiB" },
  heavy: { region: LOCATION, timeoutSeconds: 300, memory: "1GB" },
  scheduled: { region: LOCATION, timeoutSeconds: 540, memory: "512MiB" },
} as const;
```

## チェックリスト（コードレビュー時）

新しいCloud Functionsを作成する際は、以下を確認してください：

- [ ] `region:` に `LOCATION` 定数を使用しているか
- [ ] `db` は `helpers/firebase.ts` からインポートしているか
- [ ] Cloud Tasks関数名は `CLOUD_TASK_FUNCTIONS` を使用しているか
- [ ] プロジェクトIDは `PROJECT_ID` 定数を使用しているか
