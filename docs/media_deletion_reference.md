# メディア削除処理リファレンス

**作成日**: 2026年1月9日  
**対象**: homeppu プロジェクト

---

## 概要

本ドキュメントは、Firebase Storage上のメディアファイル削除に関する全ての処理をまとめたリファレンスです。

---

## 共通ヘルパー関数

### `deleteStorageFileFromUrl(url: string)`

**ファイル**: `functions/src/index.ts` (199行目)

Firebase Storage のダウンロードURLからファイルを削除する共通関数。

```typescript
async function deleteStorageFileFromUrl(url: string): Promise<boolean>
```

| 項目 | 内容 |
|------|------|
| 入力 | Firebase Storage URL (`https://firebasestorage.googleapis.com/...`) |
| 出力 | `true`（成功） / `false`（失敗） |
| エラー処理 | 例外を投げず、失敗時は `false` を返す |
| ログ | 削除対象パス、成功/失敗をログ出力 |

**処理フロー**:
1. URL形式チェック（Firebase Storageでなければ `false`）
2. URLからStorageパスを抽出（`/o/` で分割、デコード）
3. Admin SDKでファイル削除
4. 成功/失敗を返却

---

## Cloud Functions（サーバー側）

### 1. 投稿メディア削除

#### `onPostDeleted`
**ファイル**: `functions/src/index.ts` (8017行目)

| 項目 | 内容 |
|------|------|
| トリガー | Firestore `posts/{postId}` 削除時 |
| 対象 | 投稿画像、動画、サムネイル |
| 削除方法 | `deleteStorageFileFromUrl` ヘルパー使用 |
| 備考 | `mediaItems` 配列をループして全メディア削除 |

```typescript
// 処理の概要
for (const item of mediaItems) {
  await deleteStorageFileFromUrl(item.url);
  if (item.thumbnailUrl) {
    await deleteStorageFileFromUrl(item.thumbnailUrl);
  }
}
```

---

### 2. サークル画像削除

#### `onCircleUpdated`
**ファイル**: `functions/src/index.ts` (5692行目)

| 項目 | 内容 |
|------|------|
| トリガー | Firestore `circles/{circleId}` 更新時 |
| 対象 | アイコン画像、カバー画像（変更前のもの） |
| 削除方法 | `deleteStorageFileFromUrl` ヘルパー使用 |
| 条件 | URLが変更された場合のみ古い画像を削除 |

```typescript
// 処理の概要
if (beforeData.iconImageUrl && beforeData.iconImageUrl !== afterData.iconImageUrl) {
  await deleteStorageFileFromUrl(beforeData.iconImageUrl);
}
if (beforeData.coverImageUrl && beforeData.coverImageUrl !== afterData.coverImageUrl) {
  await deleteStorageFileFromUrl(beforeData.coverImageUrl);
}
```

#### `cleanupDeletedCircle`
**ファイル**: `functions/src/index.ts` (5065行目)

| 項目 | 内容 |
|------|------|
| トリガー | サークル削除時（Cloud Tasks経由） |
| 対象 | サークルのアイコン、カバー、全投稿メディア |
| 削除方法 | `getFiles({prefix})` でディレクトリ一括取得→削除 |
| 備考 | サークル内投稿のメディアは `deleteStorageFileFromUrl` 使用 |

```typescript
// サークル画像: プレフィックスでまとめて削除
const [files] = await bucket.getFiles({ prefix: `circles/${circleId}/` });
for (const file of files) {
  await file.delete();
}

// サークル投稿メディア: ヘルパー使用
for (const media of postData.mediaItems) {
  await deleteStorageFileFromUrl(media.url);
}
```

---

### 3. 問い合わせ添付画像削除

#### `deleteInquiry` (内部関数)
**ファイル**: `functions/src/index.ts` (7874行目)

| 項目 | 内容 |
|------|------|
| トリガー | `cleanupResolvedInquiries` から呼び出し |
| 対象 | 問い合わせメッセージの添付画像 |
| 削除方法 | **独自正規表現**でパス抽出→削除 |
| 備考 | ヘルパー未使用（統一推奨） |

```typescript
// 現在の実装（独自パターン）
const urlMatch = msg.imageUrl.match(/inquiries%2F([^?]+)/);
if (urlMatch) {
  const filePath = `inquiries/${decodeURIComponent(urlMatch[1])}`;
  await admin.storage().bucket().file(filePath).delete();
}
```

---

### 4. 孤立ファイルの定期クリーンアップ

#### `cleanupOrphanedMedia`
**ファイル**: `functions/src/index.ts` (6580行目付近)

| 項目 | 内容 |
|------|------|
| トリガー | スケジュール実行（週1回） |
| 対象 | 孤立した投稿画像、サークル画像、タスク添付 |
| 削除方法 | `file.delete()` 直接呼び出し |
| 条件 | 24時間以上経過 + 対応するFirestoreドキュメントが存在しない |

**対象パス**:

| プレフィックス | 確認対象 | 備考 |
|---------------|---------|------|
| `posts/` | 投稿ドキュメント | PENDING状態のファイルも削除 |
| `circles/` | サークルドキュメント | サークル削除後のゴミ |
| `task_attachments/` | タスクドキュメント | タスク削除後のゴミ |

```typescript
// 処理パターン（各タイプ共通）
const [files] = await bucket.getFiles({ prefix: "posts/" });
for (const file of files) {
  const docId = /* パスから抽出 */;
  const doc = await db.collection("posts").doc(docId).get();
  if (!doc.exists) {
    await file.delete();
  }
}
```

---

## クライアント側（Flutter）

### プロフィールヘッダー画像削除

**ファイル**: `lib/features/profile/presentation/screens/settings_screen.dart` (200行目, 280行目)

| 項目 | 内容 |
|------|------|
| 対象 | ユーザーヘッダー画像 |
| タイミング | ヘッダーリセット時、デフォルト画像選択時 |
| 削除方法 | Firebase Storage SDK直接呼び出し |
| 認可 | Storage Rules で本人のみ許可 |

```dart
// 実装パターン
final storageRef = FirebaseStorage.instance
    .ref()
    .child('headers')
    .child('${user.uid}.jpg');
await storageRef.delete();
```

---

## Storage パス構造

| パス | 用途 | 削除タイミング | 削除方式 |
|------|------|---------------|---------|
| `headers/{userId}.jpg` | ユーザーヘッダー | クライアントから直接 | クライアントSDK |
| `posts/{userId}/images/{fileName}` | 投稿画像 | 投稿削除時 | `onPostDeleted` |
| `posts/{userId}/videos/{fileName}` | 投稿動画 | 投稿削除時 | `onPostDeleted` |
| `posts/{userId}/thumbnails/{fileName}` | 動画サムネイル | 投稿削除時 | `onPostDeleted` |
| `circles/{circleId}/icon/{fileName}` | サークルアイコン | 画像変更/削除時 | `onCircleUpdated` / `cleanupDeletedCircle` |
| `circles/{circleId}/cover/{fileName}` | サークルカバー | 画像変更/削除時 | `onCircleUpdated` / `cleanupDeletedCircle` |
| `task_attachments/{userId}/{taskId}/{fileName}` | タスク添付 | 孤立時定期削除 | `cleanupOrphanedMedia` |
| `inquiries/{userId}/{fileName}` | 問い合わせ添付 | 問い合わせ削除時 | `deleteInquiry` |

---

## 削除方法の比較

| 方式 | 使用箇所 | メリット | デメリット |
|------|---------|---------|-----------|
| `deleteStorageFileFromUrl` | 投稿削除、サークル画像変更 | コード統一、エラーハンドリング済み | URL形式依存 |
| `file.delete()` 直接 | 孤立ファイル削除 | ファイルオブジェクトそのまま使用可能 | 個別実装が必要 |
| `getFiles({prefix})` + 削除 | サークル削除 | ディレクトリ一括削除可能 | 大量ファイル時は分割必要 |
| クライアントSDK直接 | ヘッダー画像 | シンプル、UIから即時反映 | Storage Rules設定必須 |

---

## 改善推奨事項

1. **`deleteInquiry` のヘルパー統一**
   - 現在独自の正規表現を使用
   - `deleteStorageFileFromUrl` に置き換え可能

2. **タスク添付ファイルの即時削除**
   - 現在は孤立時の定期クリーンアップのみ
   - `onTaskDeleted` トリガー追加で即時削除も可能

---

*本ドキュメントは 2026年1月9日 時点のコードを基に作成されました。*
