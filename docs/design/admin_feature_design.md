# 管理者機能設計

## 概要
特定の管理者ユーザーに対して、コンテンツモデレーション管理機能を提供。

## 管理者UID
```
hYr5LUH4mhR60oQfVOggrjGYJjG2
```

## 機能一覧

### 1. 要審査投稿レビュー

フラグ付き投稿（モデレーションで曖昧判定されたもの）を管理者がレビュー・判断する画面。

| 項目 | 詳細 |
|------|------|
| 画面 | `AdminReviewScreen` |
| ルート | `/admin/review` |
| トリガー | 🚩アイコンタップ |

#### アクション
- **承認**: `needsReview: false`に更新、`pendingReviews`を`reviewed: true`に
- **削除**: 投稿削除 + Storageメディア削除
- **投稿詳細**: 該当投稿画面へ遷移

### 2. 管理者通知

フラグ付き投稿発生時に管理者へ通知。

| 通知方法 | 詳細 |
|----------|------|
| **アプリ内通知** | `users/{adminId}/notifications`に追加 |
| **FCM通知** | プッシュ通知 |

#### 通知データ
```typescript
{
  type: "review_needed",
  title: "要審査投稿",
  body: "フラグ付き投稿があります: {理由}",
  postId: "{postId}",
  fromUserId: "{投稿者ID}",
  fromUserName: "{投稿者名}",
}
```

### 3. モデレーション三段階方式

| 判定 | confidence | 処理 |
|------|------------|------|
| 明確NG | ≥ 0.7 | 投稿ブロック + メディア削除 |
| 曖昧 | 0.5-0.7 | 投稿許可 + フラグ付け + 管理者通知 |
| OK | < 0.5 | 投稿許可 |

### 4. モデレーションNG時のメディア削除

投稿がモデレーションでNGになった場合、アップロード済みメディアをStorageから自動削除。

```typescript
// createPostWithModeration内
for (const item of mediaItems) {
  const storagePath = extractPathFromUrl(item.url);
  await admin.storage().bucket().file(storagePath).delete();
}
```

## Firestoreコレクション

### pendingReviews
```typescript
{
  postId: string,
  userId: string,
  reason: string,
  createdAt: Timestamp,
  reviewed: boolean,
}
```

## Firestoreインデックス
```json
{
  "collectionGroup": "pendingReviews",
  "fields": [
    { "fieldPath": "reviewed", "order": "ASCENDING" },
    { "fieldPath": "createdAt", "order": "DESCENDING" }
  ]
}
```

## セキュリティルール
```javascript
match /pendingReviews/{docId} {
  allow read, update: if isAdmin();
}
```
