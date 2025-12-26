# 孤立メディアクリーンアップ機能設計

## 概要
投稿前に離脱したユーザーや、削除後に残ったメディアファイル・Firestoreデータを定期的にクリーンアップする機能。

## 対象Storageパス

| パス | 用途 | 孤立リスク | 判定方法 |
|------|------|-----------|----------|
| `posts/{userId}/images/` | 投稿画像 | **高** | `postId === 'PENDING'` or 投稿不存在 |
| `posts/{userId}/videos/` | 投稿動画 | **高** | 同上 |
| `posts/{userId}/files/` | 投稿ファイル | **高** | 同上 |
| `circles/{circleId}/icon/` | サークルアイコン | 低 | サークル不存在 |
| `circles/{circleId}/cover/` | サークルヘッダー | 低 | 同上 |
| `task_attachments/{userId}/{taskId}/` | タスク添付 | 中 | タスク不存在 |

## 対象Firestoreコレクション（2025-12-22追加）

| コレクション | 用途 | 孤立リスク | 判定方法 |
|-------------|------|-----------|----------|
| `posts` | サークル投稿 | 中 | circleId指定だがサークル不存在 |
| `comments` | コメント | 中 | postId指定だが投稿不存在 |
| `reactions` | リアクション | 中 | postId指定だが投稿不存在 |

## メタデータ方式

### 投稿メディア（postId付与）
```typescript
{
  postId: 'PENDING' | 'actual-post-id',
  uploadedAt: 'timestamp',
  userId: 'user-id'
}
```

### サークル・タスク添付
既存のパス構造（`circleId`, `taskId`含む）で判定可能。

## 孤立判定ロジック

```typescript
// 1. 投稿メディア（Storage）
if (postId === 'PENDING' && 24時間以上経過) → 削除
if (postId !== 'PENDING' && 投稿不存在) → 削除

// 2. サークル画像（Storage）
if (サークル不存在 && 24時間以上経過) → 削除

// 3. タスク添付（Storage）
if (タスク不存在 && 24時間以上経過) → 削除

// 4. 孤立サークル投稿（Firestore）
if (circleId != null && サークル不存在) → 投稿 + コメント + リアクション + メディア削除

// 5. 孤立コメント（Firestore）
if (postId指定 && 投稿不存在) → 削除

// 6. 孤立リアクション（Firestore）
if (postId指定 && 投稿不存在) → 削除
```

## 変更ファイル

### [MODIFY] MediaService（Flutter）
- 投稿アップロード時に`postId=PENDING`, `uploadedAt`メタデータ付与

### [MODIFY] createPostWithModeration（Cloud Functions）
- 投稿成功後にメディアの`postId`メタデータを更新

### [MODIFY] cleanupOrphanedMedia（Cloud Functions）
- Cloud Schedulerで毎日午前3時実行
- 全対象パス（Storage）を走査、孤立メディアを削除
- **[2025-12-22追加]** 孤立サークル投稿（Firestore）を削除
- **[2025-12-22追加]** 孤立コメント（Firestore）を削除
- **[2025-12-22追加]** 孤立リアクション（Firestore）を削除

## Cloud Scheduler設定
```yaml
schedule: "0 3 * * *"  # 毎日午前3時
timezone: "Asia/Tokyo"
target: cleanupOrphanedMedia
timeoutSeconds: 600    # 10分タイムアウト（2025-12-26追加）
```

## 処理制限
- Storage: 全ファイル走査
- Firestore: 各コレクション最大500〜1000件/実行（バッチサイズ制限）
- 投稿存在キャッシュを使用して重複クエリを削減

## 検証計画
1. 投稿メディアのメタデータ付与確認
2. 投稿成功後のメタデータ更新確認
3. クリーンアップジョブの動作確認（各パス）
4. **[2025-12-22]** 孤立サークル投稿削除確認（28件削除成功）
5. **[2025-12-22]** 孤立コメント削除確認（6件削除成功）
6. **[2025-12-22]** 孤立リアクション削除確認（0件 = 孤立なし）

## 未対応項目（TODO）
- ユーザー削除時のデータクリーンアップ（退会機能）

