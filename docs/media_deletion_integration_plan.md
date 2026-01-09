# メディア削除処理の統合計画

**作成日**: 2026年1月9日
**目的**: 現在の削除処理を分析し、統合可能な処理を特定して統合方法を提案

---

## エグゼクティブサマリー

### 統合判定結果

| 処理 | 現在の方式 | 統合判定 | 統合先 |
|------|----------|---------|--------|
| onPostDeleted | deleteStorageFileFromUrl | ✅ 既に統合済み | - |
| onCircleUpdated | deleteStorageFileFromUrl | ✅ 既に統合済み | - |
| cleanupDeletedCircle（投稿） | deleteStorageFileFromUrl | ✅ 既に統合済み | - |
| **cleanupResolvedInquiries** | **独自正規表現** | **🔴 要統合** | **deleteStorageFileFromUrl** |
| cleanupOrphanedMedia | file.delete() 直接 | ❌ 統合不可 | - |
| cleanupDeletedCircle（画像） | getFiles + file.delete() | ❌ 統合不可 | - |

### 統合による効果

- ✅ **1件の重複コード削除**（約10行削減）
- ✅ **保守性向上**（正規表現のバグリスク排除）
- ✅ **コード統一**（URL-based削除が完全に統一）

---

## 1. 現在の削除処理の全体像

### 削除処理の分類基準

**削除対象が事前に判明しているか？** で分類できます。

| 分類 | 削除対象 | 入力データ | 最適な方法 |
|------|---------|----------|----------|
| **判明** | 特定のファイル | Firebase Storage URL | `deleteStorageFileFromUrl(url)` |
| **不明** | 孤立ファイル（要スキャン） | プレフィックス | `file.delete()` 直接 |

---

## 2. 統合可能な処理の特定

### 🔴 統合必須: cleanupResolvedInquiries

**ファイル**: `functions/src/index.ts:7876-7891`

**現在の実装**:
```typescript
for (const msgDoc of messagesSnapshot.docs) {
  const msg = msgDoc.data();
  if (msg.imageUrl) {
    // 独自正規表現でパス抽出
    const urlMatch = msg.imageUrl.match(/inquiries%2F([^?]+)/);
    if (urlMatch) {
      const filePath = `inquiries/${decodeURIComponent(urlMatch[1])}`;
      await admin.storage().bucket().file(filePath).delete();
    }
  }
}
```

**問題点**:
- ❌ `deleteStorageFileFromUrl` と完全に重複
- ❌ 正規表現が複雑（保守性低い）
- ❌ URLがあるのに再度パース処理
- ❌ コードベース全体で一貫性がない

**統合後の実装**:
```typescript
for (const msgDoc of messagesSnapshot.docs) {
  const msg = msgDoc.data();
  if (msg.imageUrl) {
    await deleteStorageFileFromUrl(msg.imageUrl);  // ← 統一ヘルパー使用
  }
}
```

**統合理由**:
- ✅ 削除対象が判明している（メッセージデータにURLあり）
- ✅ `deleteStorageFileFromUrl` の想定ユースケースと完全一致
- ✅ コード重複削減
- ✅ 正規表現のバグリスク排除

**工数**: 5分

---

## 3. 統合できない処理とその理由

### ❌ 統合不可: cleanupOrphanedMedia

**ファイル**: `functions/src/index.ts:6599-6638`

**現在の実装**:
```typescript
// Storage内をスキャン
const [postFiles] = await bucket.getFiles({ prefix: "posts/" });

for (const file of postFiles) {
  // メタデータ確認
  const [metadata] = await file.getMetadata();

  // Firestore照合
  const postDoc = await db.collection("posts").doc(postId).get();

  // 孤立ファイルなら削除
  if (!postDoc.exists) {
    await file.delete();  // ← file.delete() 直接
  }
}
```

**統合できない理由**:
1. ✅ **削除対象が不明**（どのファイルが孤立しているか事前に分からない）
2. ✅ **Storage内のスキャンが必要**（`getFiles()` でファイル一覧取得）
3. ✅ **メタデータアクセスが必要**（作成日時、カスタムメタデータの確認）
4. ✅ **既にFileオブジェクトを持っている**（わざわざURLに変換する意味なし）

**`deleteStorageFileFromUrl` を使うと何が起こるか**:
```typescript
// 非効率な例（やってはいけない）
const [files] = await bucket.getFiles({ prefix: "posts/" });
for (const file of files) {
  // 1. file.name からURLを生成（無駄な処理）
  const url = `https://firebasestorage.googleapis.com/.../posts%2F${encodeURIComponent(file.name)}...`;

  // 2. deleteStorageFileFromUrl 内でURLをパース（二度手間）
  await deleteStorageFileFromUrl(url);
  // → 内部で再度 bucket.file(path).delete() を呼ぶだけ
}
```

**結論**: 統合すると**効率が悪化**するため、現状維持が最適 ✅

---

### ❌ 統合不可: cleanupDeletedCircle（サークル画像削除）

**ファイル**: `functions/src/index.ts:5206-5212`

**現在の実装**:
```typescript
// サークル画像ディレクトリを一括削除
const bucket = admin.storage().bucket();
const [files] = await bucket.getFiles({ prefix: `circles/${circleId}/` });

for (const file of files) {
  await file.delete().catch(e => console.error(...));
}
```

**統合できない理由**:
1. ✅ **ディレクトリ単位の一括削除**（個別URLリストがない）
2. ✅ **プレフィックスマッチで全削除**（icon, cover など全種類を一括処理）
3. ✅ **既にFileオブジェクトを持っている**

**特殊性**:
- サークル削除時はアイコン・カバー画像のURLをFirestoreから取得する必要がある
- しかし削除処理開始時点でサークルドキュメントは既に論理削除済み（`isDeleted: true`）
- URLリストを作るよりプレフィックスで一括削除の方が確実

**結論**: ディレクトリ一括削除という別の目的のため、統合不可 ✅

---

## 4. 既に統合済みの処理

### ✅ onPostDeleted（投稿削除）

**ファイル**: `functions/src/index.ts:8077-8091`

```typescript
for (const item of mediaItems) {
  await deleteStorageFileFromUrl(item.url);
  if (item.thumbnailUrl) {
    await deleteStorageFileFromUrl(item.thumbnailUrl);
  }
}
```

**判定**: 正しく統合済み ✅

---

### ✅ onCircleUpdated（サークル画像変更）

**ファイル**: `functions/src/index.ts:5707-5718`

```typescript
// アイコン画像が変更された場合、古い画像を削除
if (beforeData.iconImageUrl && beforeData.iconImageUrl !== afterData.iconImageUrl) {
  await deleteStorageFileFromUrl(beforeData.iconImageUrl);
}

// カバー画像が変更された場合、古い画像を削除
if (beforeData.coverImageUrl && beforeData.coverImageUrl !== afterData.coverImageUrl) {
  await deleteStorageFileFromUrl(beforeData.coverImageUrl);
}
```

**判定**: 正しく統合済み ✅

---

### ✅ cleanupDeletedCircle（投稿メディア削除）

**ファイル**: `functions/src/index.ts:5129-5142`

```typescript
// メディア削除（ヘルパー関数を使用）
const mediaItems = postData.mediaItems || [];
for (const media of mediaItems) {
  if (media.url) {
    mediaDeletePromises.push(
      deleteStorageFileFromUrl(media.url).then(() => { })
    );
  }
  if (media.thumbnailUrl) {
    mediaDeletePromises.push(
      deleteStorageFileFromUrl(media.thumbnailUrl).then(() => { })
    );
  }
}
```

**判定**: 正しく統合済み ✅

---

## 5. 統合計画の詳細

### 統合対象: cleanupResolvedInquiries（問い合わせ削除）

#### 変更箇所

**ファイル**: `functions/src/index.ts`
**関数**: `deleteInquiryWithArchive`
**行番号**: 7876-7891

#### 変更内容

```diff
// 6. Storage画像を削除（存在する場合）
-// 画像URLからファイルパスを抽出して削除
 for (const msgDoc of messagesSnapshot.docs) {
   const msg = msgDoc.data();
   if (msg.imageUrl) {
     try {
-      // URLからファイルパスを抽出
-      const urlMatch = msg.imageUrl.match(/inquiries%2F([^?]+)/);
-      if (urlMatch) {
-        const filePath = `inquiries/${decodeURIComponent(urlMatch[1])}`;
-        await admin.storage().bucket().file(filePath).delete();
-        console.log(`Deleted storage file: ${filePath}`);
-      }
+      await deleteStorageFileFromUrl(msg.imageUrl);
     } catch (storageError) {
       console.error(`Error deleting storage file for inquiry ${inquiryId}:`, storageError);
     }
   }
 }
```

#### 変更後の全体コード（実装済み: 2026-01-09）

```typescript
// 6. Storage画像を削除（存在する場合）
for (const msgDoc of messagesSnapshot.docs) {
  const msg = msgDoc.data();
  if (msg.imageUrl) {
    await deleteStorageFileFromUrl(msg.imageUrl);
  }
}
```

#### try-catch が不要な理由

`deleteStorageFileFromUrl` ヘルパー関数の設計により、**外側での try-catch は不要**です：

1. **例外を投げない設計**: ヘルパー関数内で全てのエラーをキャッチし、失敗時は `false` を返す
2. **ログ出力済み**: エラー発生時は関数内で `console.warn()` が出力される
3. **処理継続を保証**: 1ファイルの削除失敗が他のファイル削除をブロックしない

```typescript
// deleteStorageFileFromUrl の内部実装（抜粋）
async function deleteStorageFileFromUrl(url: string): Promise<boolean> {
  try {
    // ... 削除処理 ...
    return true;
  } catch (error) {
    console.warn(`Failed to delete storage file (${url}):`, error);
    return false;  // ← 例外を投げずに false を返す
  }
}
```

#### テスト項目

1. 問い合わせ解決から7日後に自動削除が動作すること
2. 添付画像がある問い合わせで、Storage画像が正しく削除されること
3. 添付画像がない問い合わせでエラーが発生しないこと
4. 削除失敗時もエラーで止まらず続行すること

---

## 6. 統合による効果

### コード品質の向上

| 項目 | Before | After | 改善 |
|------|--------|-------|------|
| 削除処理の実装数 | 2種類（ヘルパー + 独自） | 1種類（ヘルパーのみ） | -50% |
| 正規表現の使用箇所 | 1箇所 | 0箇所 | バグリスク排除 |
| コード行数 | 約10行 | 約1行 | -90% |
| URL解析ロジック | 2箇所で重複 | 1箇所に集約 | DRY原則準拠 |

### 保守性の向上

- ✅ **バグ修正が1箇所で済む**（現在は2箇所のメンテナンス必要）
- ✅ **新規実装時の迷いがなくなる**（URLがあれば `deleteStorageFileFromUrl`）
- ✅ **正規表現のバグリスク排除**（複雑な正規表現が不要に）

### パフォーマンスへの影響

- 影響なし（内部処理は同等）

---

## 7. 統合のガイドライン

### URL-based削除の統一ルール

**削除対象が判明している場合（FirestoreにURLがある）**:

```typescript
// ✅ 正しい実装
await deleteStorageFileFromUrl(url);
```

```typescript
// ❌ 避けるべき実装
const urlMatch = url.match(/path%2F([^?]+)/);
const filePath = `path/${decodeURIComponent(urlMatch[1])}`;
await admin.storage().bucket().file(filePath).delete();
```

### Fileオブジェクトがある場合のルール

**削除対象が不明で、Storage内をスキャンする場合**:

```typescript
// ✅ 正しい実装
const [files] = await bucket.getFiles({ prefix: "posts/" });
for (const file of files) {
  await file.delete();
}
```

```typescript
// ❌ 避けるべき実装（非効率）
const [files] = await bucket.getFiles({ prefix: "posts/" });
for (const file of files) {
  const url = constructUrlFromFile(file);  // 無駄な変換
  await deleteStorageFileFromUrl(url);     // 再度パース
}
```

### ディレクトリ一括削除のルール

**プレフィックスで一括削除する場合**:

```typescript
// ✅ 正しい実装
const [files] = await bucket.getFiles({ prefix: `circles/${circleId}/` });
for (const file of files) {
  await file.delete();
}
```

---

## 8. 削除方法の決定フローチャート

```
削除対象が事前に判明している？
│
├─ YES（判明）
│   │
│   ├─ FirestoreにURLがある？
│   │   └─ YES → deleteStorageFileFromUrl(url) ✅
│   │       例: 投稿削除、サークル画像変更、問い合わせ削除
│   │
│   └─ ディレクトリ一括削除？
│       └─ YES → getFiles({prefix}) + file.delete() ✅
│           例: サークル削除時の画像ディレクトリ
│
└─ NO（不明）
    └─ Storage内をスキャンが必要
        → getFiles() + file.delete() 直接 ✅
        例: 孤立ファイルクリーンアップ
```

---

## 9. 実装手順

### Step 1: 修正実施

1. `functions/src/index.ts:7876-7891` を修正
2. 独自正規表現を削除
3. `deleteStorageFileFromUrl` 呼び出しに置き換え

### Step 2: テスト

1. ローカル環境でビルド確認
2. テスト用問い合わせを作成
3. 7日後の削除処理が正常動作することを確認
4. Storage画像が正しく削除されることを確認

### Step 3: デプロイ

1. Cloud Functions にデプロイ
2. ログ監視（次回の定期実行時）
3. 問題なければ完了

---

## 10. まとめ

### 統合結果

| 項目 | 内容 |
|------|------|
| **統合必須** | cleanupResolvedInquiries（独自正規表現 → deleteStorageFileFromUrl） |
| **統合不可** | cleanupOrphanedMedia, cleanupDeletedCircle（サークル画像） |
| **既に統合済み** | onPostDeleted, onCircleUpdated, cleanupDeletedCircle（投稿） |

### 統合の本質

**削除対象が事前に判明しているか** で統合可否が決まる：

- **判明（URLあり）** → `deleteStorageFileFromUrl` に統合 ✅
- **不明（スキャン必要）** → `file.delete()` 直接（統合不可） ❌
- **ディレクトリ一括** → `getFiles + file.delete()`（統合不可） ❌

### 推奨アクション

1. **即座に実施**: cleanupResolvedInquiries の修正（工数: 5分）
2. **維持**: cleanupOrphanedMedia, cleanupDeletedCircle（現状が最適）

---

*本ドキュメントは 2026年1月9日 時点のコードを基に作成されました。*
