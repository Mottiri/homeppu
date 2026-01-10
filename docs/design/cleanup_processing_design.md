# 定期クリーンアップ処理設計書

このドキュメントでは、システムで実行されている定期クリーンアップ処理を一覧化し、各処理の目的、実行タイミング、保持期間、ソースコードの場所を記載します。

---

## 概要

| 関数名 | 実行時刻 (JST) | 対象 | 保持期間 | ソースコード |
|--------|--------------|------|---------|-------------|
| `cleanupOrphanedMedia` | 毎日 03:00 | 孤立メディアファイル | 24時間 | [L6579](functions/src/index.ts#L6579) |
| `cleanupResolvedInquiries` | 毎日 03:00 | 解決済み問い合わせ | 7日間 | [L7764](functions/src/index.ts#L7764) |
| `checkGhostCircles` | 毎日 03:30 | ゴースト/放置サークル | 365日/30日 + 7日猶予 | [L8491](functions/src/index.ts#L8491) |
| `cleanupBannedUsers` | 毎日 04:00 | 永久BANユーザー | スケジュール日時到達時 | [L8435](functions/src/index.ts#L8435) |
| `cleanupReports` | 毎日 00:00 | 対処済みレポート | 1ヶ月 | [L7939](functions/src/index.ts#L7939) |

---

## 1. `cleanupOrphanedMedia` - 孤立メディアクリーンアップ

### 処理概要
Firebase Storage上に存在するが、Firestoreのどのドキュメントからも参照されていないファイル（孤立メディア）を検出し、削除します。アップロード失敗、投稿削除、編集時の差し替えなどで発生する不要ファイルを自動的にクリーンアップし、ストレージコストを削減します。

### 実行タイミング
- **スケジュール**: `0 3 * * *` （毎日午前3時 JST）
- **タイムアウト**: 600秒（10分）

### 保持期間
- **24時間**: アップロードから24時間以上経過した孤立メディアが削除対象

### 対象ディレクトリと検出ロジック

この処理では**4種類の対象**があり、それぞれ異なる検出方法を使用しています。

#### 1. 投稿メディア (`posts/`)

**検出方法**: アップロード時にメタデータに埋め込んだ `postId` を使用

| 状態 | 判定 | 説明 |
|------|------|------|
| `postId = "PENDING"` | 孤立 | 投稿前に離脱したケース |
| 投稿ドキュメントが存在しない | 孤立 | 投稿が削除された |

```typescript
// メタデータからpostIdを取得
const customMetadata = metadata.metadata || {};
const postId = customMetadata.postId ? String(customMetadata.postId) : null;

if (postId === "PENDING") {
  // 投稿前に離脱したケース → 孤立
  shouldDelete = true;
} else {
  // 投稿が存在するか確認
  const postDoc = await db.collection("posts").doc(postId).get();
  if (!postDoc.exists) {
    // 投稿が削除された → 孤立
    shouldDelete = true;
  }
}
```

#### 2. サークル画像 (`circles/`)

**検出方法**: ファイルパスから `circleId` を抽出し、存在確認

| パス形式 | 抽出対象 |
|---------|---------|
| `circles/{circleId}/icon/{fileName}` | `circleId` = pathParts[1] |

```typescript
// パスからcircleIdを抽出: circles/{circleId}/icon/{fileName}
const pathParts = file.name.split("/");
const circleId = pathParts[1];

// サークルが存在するか確認
const circleDoc = await db.collection("circles").doc(circleId).get();
if (!circleDoc.exists) {
  // サークルが削除された → 孤立
  shouldDelete = true;
}
```

#### 3. タスク添付ファイル (`task_attachments/`)

**検出方法**: ファイルパスから `taskId` を抽出し、存在確認

| パス形式 | 抽出対象 |
|---------|---------|
| `task_attachments/{userId}/{taskId}/{fileName}` | `taskId` = pathParts[2] |

```typescript
// パスからtaskIdを抽出: task_attachments/{userId}/{taskId}/{fileName}
const pathParts = file.name.split("/");
const taskId = pathParts[2];

const taskDoc = await db.collection("tasks").doc(taskId).get();
if (!taskDoc.exists) {
  // タスクが削除された → 孤立
  shouldDelete = true;
}
```

#### 4. 孤立サークル投稿（Firestoreデータ）

**検出方法**: 投稿の `circleId` が指すサークルが存在するか確認

> **注意**: この処理は Storage ではなく Firestore のデータを対象としています

```typescript
// サークル投稿を取得
const circlePostsSnapshot = await db.collection("posts")
  .where("circleId", "!=", null)
  .limit(500)
  .get();

// サークルの存在を確認するためのキャッシュ
const circleExistsCache: Map<string, boolean> = new Map();

for (const postDoc of circlePostsSnapshot.docs) {
  const circleId = postDoc.data().circleId;
  
  // キャッシュを確認（同じサークルへの複数クエリを防止）
  let circleExists = circleExistsCache.get(circleId);
  if (circleExists === undefined) {
    const circleDoc = await db.collection("circles").doc(circleId).get();
    circleExists = circleDoc.exists;
    circleExistsCache.set(circleId, circleExists);
  }

  if (!circleExists) {
    // サークルが削除された → 投稿も削除
    // コメント、リアクション、メディアも一緒に削除
  }
}
```

### 検出ロジックまとめ

| 対象 | 検出方法 | 孤立条件 |
|------|---------|---------|
| 投稿メディア | メタデータの `postId` | `PENDING` or 投稿が存在しない |
| サークル画像 | パスから `circleId` 抽出 | サークルが存在しない |
| タスク添付 | パスから `taskId` 抽出 | タスクが存在しない |
| サークル投稿 | Firestoreの `circleId` | サークルが存在しない |

### ソースコード

**ファイル**: `functions/src/index.ts`  
**行番号**: L6575-L6780


---

## 2. `cleanupResolvedInquiries` - 解決済み問い合わせクリーンアップ

### 処理概要
解決済み（resolved）になった問い合わせを7日後に自動削除します。削除前日（6日目）にユーザーへ削除予告通知を送信し、7日経過後に問い合わせ本体・メッセージ・添付画像を削除します。削除されたデータは `archivedInquiries` コレクションにアーカイブとして保存されます。

### 実行タイミング
- **スケジュール**: `0 3 * * *` （毎日午前3時 JST）

### 保持期間
| 経過日数 | アクション |
|---------|-----------|
| 6日以上 | ユーザーに削除予告通知を送信 |
| 7日以上 | 問い合わせを削除、アーカイブに保存 |

### アーカイブ保存内容
- 問い合わせID、ユーザー情報、件名、カテゴリ
- 全メッセージ（content, senderType, createdAt）
- 作成日時、解決日時、削除日時

### ソースコード

**ファイル**: `functions/src/index.ts`  
**行番号**: L7760-L7930

```typescript
export const cleanupResolvedInquiries = onSchedule(
  {
    schedule: "0 3 * * *",
    timeZone: "Asia/Tokyo",
    region: "asia-northeast1",
  },
  async () => {
    console.log("=== cleanupResolvedInquiries started ===");

    const now = new Date();
    const sixDaysAgo = new Date(now.getTime() - 6 * 24 * 60 * 60 * 1000);
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    // 解決済みの問い合わせを取得
    const inquiriesSnapshot = await db.collection("inquiries")
      .where("status", "==", "resolved")
      .get();

    for (const doc of inquiriesSnapshot.docs) {
      const inquiry = doc.data();
      const resolvedAt = inquiry.resolvedAt?.toDate?.();

      if (resolvedAt < sevenDaysAgo) {
        // 7日以上経過 → 削除 + アーカイブ
        await deleteInquiryWithArchive(doc.id, inquiry);
      } else if (resolvedAt < sixDaysAgo && !inquiry.deletionNotified) {
        // 6日以上経過 → 削除予告通知
        await sendDeletionNotification(doc.id, inquiry);
      }
    }
  }
);

// 問い合わせ削除＆アーカイブ処理
async function deleteInquiryWithArchive(inquiryId: string, inquiry: any) {
  // 1. アーカイブデータを作成
  const archiveData = { ...inquiry, archivedAt: Timestamp.now() };
  
  // 2. メッセージを取得してアーカイブに含める
  const messagesSnapshot = await db.collection("inquiries")
    .doc(inquiryId).collection("messages").get();
  archiveData.messages = messagesSnapshot.docs.map(d => d.data());
  
  // 3. アーカイブに保存
  await db.collection("archivedInquiries").doc(inquiryId).set(archiveData);
  
  // 4. 添付画像をStorageから削除
  for (const msg of archiveData.messages) {
    if (msg.imageUrl) {
      await deleteStorageFile(msg.imageUrl);
    }
  }
  
  // 5. 問い合わせを削除
  await db.collection("inquiries").doc(inquiryId).delete();
}
```

---

## 3. `checkGhostCircles` - ゴースト/放置サークル検出・削除

### 処理概要
長期間活動のないサークルを検出し、オーナーに警告通知を送信後、自動削除します。「ゴーストサークル」は最後の人間投稿から365日以上経過、「放置サークル」は人間投稿が1件もなく作成から30日以上経過したサークルを指します。

### 実行タイミング
- **スケジュール**: `30 3 * * *` （毎日午前3時30分 JST）
- **タイムアウト**: 540秒（9分）
- **メモリ**: 512MiB

### 保持期間・判定基準

| サークル種別 | 条件 | 削除までの期間 |
|------------|------|--------------|
| **ゴーストサークル** | 最後の人間投稿から365日以上経過 | 警告通知 + 7日猶予 |
| **放置サークル** | 人間投稿なし かつ 作成から30日以上経過 | 警告通知 + 7日猶予 |

### 関連定数
```typescript
const GHOST_THRESHOLD_DAYS = 365; // ゴースト判定日数
const EMPTY_THRESHOLD_DAYS = 30;  // 放置判定日数
const DELETE_GRACE_DAYS = 7;      // 猶予期間
```

### ソースコード

**ファイル**: `functions/src/index.ts`  
**行番号**: L8480-L8629

```typescript
export const checkGhostCircles = onSchedule(
  {
    schedule: "30 3 * * *",
    timeZone: "Asia/Tokyo",
    region: "asia-northeast1",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    console.log("=== checkGhostCircles START ===");
    const now = Date.now();
    const ghostThreshold = new Date(now - GHOST_THRESHOLD_DAYS * 24 * 60 * 60 * 1000);
    const emptyThreshold = new Date(now - EMPTY_THRESHOLD_DAYS * 24 * 60 * 60 * 1000);
    const deleteThreshold = new Date(now - DELETE_GRACE_DAYS * 24 * 60 * 60 * 1000);

    const circlesSnapshot = await db.collection("circles")
      .where("isDeleted", "!=", true)
      .get();

    for (const circleDoc of circlesSnapshot.docs) {
      const circleData = circleDoc.data();
      const lastHumanPostAt = circleData.lastHumanPostAt?.toDate?.();
      const createdAt = circleData.createdAt?.toDate?.();
      const ghostWarningNotifiedAt = circleData.ghostWarningNotifiedAt?.toDate?.();

      // ゴースト判定: 最後の人間投稿が365日以上前
      let isGhost = lastHumanPostAt && lastHumanPostAt < ghostThreshold;
      // 放置判定: 人間投稿なし + 作成から30日以上
      let isEmpty = !lastHumanPostAt && createdAt < emptyThreshold;

      if (!isGhost && !isEmpty) continue;

      if (!ghostWarningNotifiedAt) {
        // 未通知 → オーナーに警告通知
        await sendGhostWarningNotification(circleDoc.id, circleData);
        await circleDoc.ref.update({ ghostWarningNotifiedAt: Timestamp.now() });
      } else if (ghostWarningNotifiedAt < deleteThreshold) {
        // 通知から7日経過 → 削除
        await deleteCircle(circleDoc.id);
      }
    }
  }
);
```

---

## 4. `cleanupBannedUsers` - 永久BANユーザー削除

### 処理概要
永久BANされたユーザーを、事前に設定されたスケジュール日時に完全削除します。Firebase Authenticationからのユーザー削除とFirestoreのユーザードキュメント削除を行います。

### 実行タイミング
- **スケジュール**: `0 4 * * *` （毎日午前4時 JST）
- **タイムアウト**: 540秒（9分）

### 保持期間
- **可変**: `permanentBanScheduledDeletionAt` フィールドに設定された日時
- 通常、永久BAN時点から一定期間（例: 30日）後に設定される

### 対象クエリ条件
```typescript
db.collection("users")
  .where("banStatus", "==", "permanent")
  .where("permanentBanScheduledDeletionAt", "<=", now)
  .limit(20)
```

### 必要なインデックス
| コレクション | フィールド1 | フィールド2 |
|-------------|-----------|-----------|
| `users` | `banStatus` (Ascending) | `permanentBanScheduledDeletionAt` (Ascending) |

### ソースコード

**ファイル**: `functions/src/index.ts`  
**行番号**: L8432-L8478

```typescript
export const cleanupBannedUsers = onSchedule(
  {
    schedule: "0 4 * * *",
    timeZone: "Asia/Tokyo",
    region: "asia-northeast1",
    timeoutSeconds: 540,
  },
  async () => {
    console.log("=== cleanupBannedUsers START ===");
    const now = admin.firestore.Timestamp.now();

    const snapshot = await db.collection("users")
      .where("banStatus", "==", "permanent")
      .where("permanentBanScheduledDeletionAt", "<=", now)
      .limit(20)
      .get();

    if (snapshot.empty) {
      console.log("No users to delete");
      return;
    }

    console.log(`Found ${snapshot.size} users to scheduled delete`);

    for (const doc of snapshot.docs) {
      try {
        const uid = doc.id;
        console.log(`Deleting banned user: ${uid}`);

        // Firebase Authからユーザー削除
        await admin.auth().deleteUser(uid).catch(e => {
          console.warn(`Auth delete failed for ${uid}:`, e);
        });

        // Firestoreからユーザードキュメント削除
        await db.collection("users").doc(uid).delete();

      } catch (error) {
        console.error(`Error deleting user ${doc.id}:`, error);
      }
    }

    console.log("=== cleanupBannedUsers COMPLETE ===");
  }
);
```

---

## 5. `cleanupReports` - レポートクリーンアップ

### 処理概要
対処済みの通報（レポート）を作成から1ヶ月後に自動削除します。`reviewed`（対処済み）または `dismissed`（却下済み）ステータスのレポートが対象です。

### 実行タイミング
- **スケジュール**: `every day 00:00` （毎日午前0時 JST）
- **タイムアウト**: 300秒（5分）

### 保持期間
- **1ヶ月**: 対処済み（reviewed/dismissed）かつ作成から1ヶ月以上経過

### 対象ステータス
| ステータス | 説明 |
|-----------|------|
| `reviewed` | 対処済み |
| `dismissed` | 却下済み |

### ソースコード

**ファイル**: `functions/src/index.ts`  
**行番号**: L7935-L8000

```typescript
export const cleanupReports = onSchedule(
  {
    schedule: "every day 00:00",
    timeZone: "Asia/Tokyo",
    timeoutSeconds: 300,
  },
  async (event) => {
    console.log("Starting cleanupReports function...");

    try {
      // 1ヶ月前の日時を計算
      const cutoffDate = new Date();
      cutoffDate.setMonth(cutoffDate.getMonth() - 1);
      const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoffDate);

      // 対処済みレポートを取得
      const reviewedSnapshot = await db
        .collection("reports")
        .where("status", "==", "reviewed")
        .where("createdAt", "<", cutoffTimestamp)
        .get();

      // 却下済みレポートを取得
      const dismissedSnapshot = await db
        .collection("reports")
        .where("status", "==", "dismissed")
        .where("createdAt", "<", cutoffTimestamp)
        .get();

      console.log(
        `Found ${reviewedSnapshot.size} reviewed and ` +
        `${dismissedSnapshot.size} dismissed reports to delete`
      );

      // 削除実行
      const batch = db.batch();
      reviewedSnapshot.docs.forEach(doc => batch.delete(doc.ref));
      dismissedSnapshot.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();

    } catch (error) {
      console.error("Error in cleanupReports:", error);
    }
  }
);
```

---

## 実行スケジュール一覧（時系列）

```
00:00 JST ─── cleanupReports         ── 対処済みレポート削除
  │
03:00 JST ─┬─ cleanupOrphanedMedia   ── 孤立メディア削除
           └─ cleanupResolvedInquiries ── 解決済み問い合わせ削除
  │
03:30 JST ─── checkGhostCircles      ── ゴースト/放置サークル検出・削除
  │
04:00 JST ─── cleanupBannedUsers     ── 永久BANユーザー削除
```

---

## 保持期間まとめ

| 対象 | 保持期間 | 備考 |
|------|---------|------|
| 孤立メディア | 24時間 | アップロード後、参照なし |
| 解決済み問い合わせ | 7日間 | 解決後から起算 |
| ゴーストサークル | 365日 + 7日猶予 | 最後の人間投稿から起算 |
| 放置サークル | 30日 + 7日猶予 | サークル作成から起算 |
| 永久BANユーザー | スケジュール日時 | BAN時に設定された日時 |
| 対処済みレポート | 1ヶ月 | レポート作成から起算 |

---

## ソースコード参照

| 関数名 | ファイル | 行番号 |
|--------|---------|--------|
| `cleanupOrphanedMedia` | `functions/src/index.ts` | L6575-L6760 |
| `cleanupResolvedInquiries` | `functions/src/index.ts` | L7760-L7930 |
| `cleanupReports` | `functions/src/index.ts` | L7935-L8000 |
| `cleanupBannedUsers` | `functions/src/index.ts` | L8432-L8478 |
| `checkGhostCircles` | `functions/src/index.ts` | L8480-L8629 |

---

## 更新履歴

| 日付 | 内容 |
|------|------|
| 2026-01-10 | 初版作成 |
| 2026-01-10 | 処理概要とソースコード抜粋を追加 |
