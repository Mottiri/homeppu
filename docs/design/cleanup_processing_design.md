# 定期クリーンアップ処理設計書

> [!WARNING]
> 2026-02-12時点でタスク/目標機能は本体から廃止済みです。  
> この文書内の task/goal 関連記述は履歴資料として扱ってください。


このドキュメントでは、システムで実行されている定期クリーンアップ処理を一覧化し、各処理の目的、実行タイミング、保持期間、検出・削除ロジックを記載します。

---

## 概要

| 関数名 | 実行時刻 (JST) | 対象 | 保持期間 | ソースコード |
|--------|--------------|------|---------|-------------|
| `cleanupOrphanedMedia` | 毎日 03:00 | `pendingMedia` に残った未確定メディア | 24時間 | [L6579](functions/src/index.ts#L6579) |
| `cleanupResolvedInquiries` | 毎日 03:00 | 解決済み問い合わせ | 7日間 | [L7764](functions/src/index.ts#L7764) |
| `checkGhostCircles` | 毎日 03:30 | ゴースト/放置サークル | 365日/30日 + 7日猶予 | [L8491](functions/src/index.ts#L8491) |
| `cleanupBannedUsers` | 毎日 04:00 | 永久BANユーザー | スケジュール日時到達時 | [L8435](functions/src/index.ts#L8435) |
| `cleanupReports` | 毎日 00:00 | 対処済みレポート | 1ヶ月 | [L7939](functions/src/index.ts#L7939) |

---

## 1. `cleanupOrphanedMedia` - 未確定メディアクリーンアップ

### 処理概要
`cleanupOrphanedMedia` は Firebase Storage 全体を走査せず、Firestore の `pendingMedia` コレクションに残っている未確定メディアだけを対象にクリーンアップします。

- 投稿画像アップロード時に `type: post_image`
- サークルアイコンアップロード時に `type: circle_icon`
- サークルヘッダーアップロード時に `type: circle_cover`

の pending レコードを作成し、投稿/サークルへの紐付け完了時に pending を削除します。
クライアント離脱や途中失敗で pending が残った場合のみ、定期ジョブが後始末を行います。

### 実行タイミング
- **スケジュール**: `0 3 * * *` （毎日午前3時 JST）
- **タイムアウト**: 600秒（10分）

### 保持期間
- **24時間**: `createdAt` から 24 時間以上経過した pending が削除対象

### 対象と判定ロジック

対象は `pendingMedia` のみです。各ドキュメントは少なくとも以下を持ちます。

- `type`
- `ownerId`
- `storagePath`
- `circleId`（サークル画像のみ）
- `createdAt`

ジョブは `createdAt <= now - 24h` の pending を取得し、`type` に応じて「すでに本体へ紐付いたか」を確認します。

#### 1-1. 投稿画像 (`post_image`)

- `posts` コレクションの `mediaStoragePaths` に `storagePath` が含まれていれば **添付済み**
- 添付済みなら pending ドキュメントだけ削除
- 添付されていなければ Storage ファイルと pending ドキュメントを削除

#### 1-2. サークルアイコン (`circle_icon`)

- `circles.iconImageStoragePath == storagePath` なら **添付済み**
- 添付済みなら pending ドキュメントだけ削除
- 添付されていなければ Storage ファイルと pending ドキュメントを削除

#### 1-3. サークルヘッダー (`circle_cover`)

- `circles.coverImageStoragePath == storagePath` なら **添付済み**
- 添付済みなら pending ドキュメントだけ削除
- 添付されていなければ Storage ファイルと pending ドキュメントを削除

### 旧方式からの変更点

2026-04-02 時点で、以下の旧ロジックは廃止されています。

- `posts/` や `circles/` の Storage 全件列挙
- 投稿メタデータ `postId: PENDING` を見た孤立判定
- `comments` / `reactions` / サークル投稿の全走査 cleanup

理由は、データ量増加に対して Storage list / Firestore read コストが線形に膨らみやすく、保守ジョブとしてスケールしにくかったためです。

### 現在の設計上の役割

- **主系統**: アップロード失敗時ロールバックと、投稿/サークル保存成功時の pending 解消
- **保険**: それでも残った pending のみを 1 日 1 回掃除

> [!NOTE]
> 旧 full-scan cleanup の詳細記述は履歴資料として扱ってください。現行コードの truth は `functions/src/scheduled/cleanup.ts` です。

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

### 検出方法

Firestoreの `inquiries` コレクションから `status == "resolved"` の問い合わせを全件取得します。各問い合わせの `resolvedAt`（解決日時）フィールドから経過日数を計算し、6日以上または7日以上経過しているかを判定します。

```typescript
const inquiriesSnapshot = await db.collection("inquiries")
  .where("status", "==", "resolved")
  .get();

for (const doc of inquiriesSnapshot.docs) {
  const resolvedAt = doc.data().resolvedAt?.toDate();
  // resolvedAtから経過日数を計算して判定
}
```

### 削除方法

7日以上経過した問い合わせは、以下の手順で削除とアーカイブを行います：

1. **アーカイブデータ作成**: 問い合わせの全フィールドをコピー
2. **メッセージ取得**: サブコレクション `messages` から全メッセージを取得し、アーカイブデータに含める
3. **アーカイブ保存**: `archivedInquiries` コレクションに保存（同じIDを使用）
4. **添付画像削除**: メッセージ内の `imageUrl` からStorageのパスを抽出し、ファイルを削除
5. **メッセージ削除**: サブコレクションの全ドキュメントを削除
6. **問い合わせ削除**: 問い合わせドキュメント本体を削除

```typescript
// 1-3. アーカイブ保存
const archiveData = { ...inquiry, archivedAt: Timestamp.now() };
archiveData.messages = messagesSnapshot.docs.map(d => d.data());
await db.collection("archivedInquiries").doc(inquiryId).set(archiveData);

// 4. 添付画像削除
for (const msg of archiveData.messages) {
  if (msg.imageUrl) await deleteStorageFile(msg.imageUrl);
}

// 5-6. Firestoreから削除
for (const msgDoc of messagesSnapshot.docs) {
  await msgDoc.ref.delete();
}
await db.collection("inquiries").doc(inquiryId).delete();
```

### アーカイブ保存内容

| フィールド | 説明 |
|-----------|------|
| 問い合わせ全フィールド | userId, subject, category, status など |
| messages | 全メッセージの配列（content, senderType, createdAt） |
| archivedAt | アーカイブ日時（削除実行時） |

### ソースコード

**ファイル**: `functions/src/index.ts`  
**行番号**: L7760-L7930

---

## 3. `checkGhostCircles` - ゴースト/放置サークル検出・削除

### 処理概要
長期間活動のないサークルを検出し、オーナーに警告通知を送信後、自動削除します。「ゴーストサークル」は最後の人間投稿から365日以上経過、「放置サークル」は人間投稿が1件もなく作成から30日以上経過したサークルを指します。

### 実行タイミング
- **スケジュール**: `30 3 * * *` （毎日午前3時30分 JST）
- **タイムアウト**: 540秒（9分）
- **メモリ**: 512MiB

### 保持期間・判定基準

| サークル種別 | 条件 | 削除までの流れ |
|------------|------|--------------|
| **ゴーストサークル** | 最後の人間投稿から365日以上経過 | 警告通知 → 7日猶予 → 削除 |
| **放置サークル** | 人間投稿なし かつ 作成から30日以上経過 | 警告通知 → 7日猶予 → 削除 |

### 関連定数

```typescript
const GHOST_THRESHOLD_DAYS = 365; // ゴースト判定日数
const EMPTY_THRESHOLD_DAYS = 30;  // 放置判定日数
const DELETE_GRACE_DAYS = 7;      // 猶予期間
```

### 検出方法

Firestoreの `circles` コレクションから `isDeleted != true` のサークルを全件取得します。各サークルについて、以下のフィールドを確認して判定します：

1. **`lastHumanPostAt`**: 最後の人間による投稿日時（AIの投稿は含まない）
2. **`createdAt`**: サークル作成日時
3. **`ghostWarningNotifiedAt`**: 警告通知を送信した日時

**ゴーストサークル判定**:
```typescript
// 人間投稿があり、かつ365日以上前
const isGhost = lastHumanPostAt && lastHumanPostAt < ghostThreshold;
```

**放置サークル判定**:
```typescript
// 人間投稿が一度もなく、作成から30日以上経過
const isEmpty = !lastHumanPostAt && createdAt < emptyThreshold;
```

### 削除方法

ゴースト/放置と判定されたサークルは、2段階で処理されます：

#### ステップ1: 警告通知（未通知の場合）

オーナーに「サークルが7日後に削除される」旨の通知を送信し、`ghostWarningNotifiedAt` に現在日時を記録します。

```typescript
if (!ghostWarningNotifiedAt) {
  await sendGhostWarningNotification(circleId, circleData);
  await circleDoc.ref.update({ ghostWarningNotifiedAt: Timestamp.now() });
}
```

#### ステップ2: 削除（通知から7日経過後）

警告通知から7日以上経過した場合、サークルを完全削除します。削除処理では以下を実行：

1. **サークル投稿を削除**: `posts` コレクションから `circleId` が一致する投稿を全て削除
2. **各投稿のコメント・リアクション削除**: 投稿に紐づく関連データを削除
3. **メディアファイル削除**: 投稿に含まれるメディアをStorageから削除
4. **サークルドキュメント削除**: `circles` コレクションからサークル本体を削除
5. **サークル画像削除**: サークルアイコンをStorageから削除

```typescript
if (ghostWarningNotifiedAt < deleteThreshold) {
  await deleteCircle(circleId);  // 上記の全削除処理を実行
}
```

### ソースコード

**ファイル**: `functions/src/index.ts`  
**行番号**: L8480-L8629

---

## 4. `cleanupBannedUsers` - 永久BANユーザー削除

### 処理概要
永久BANされたユーザーを、事前に設定されたスケジュール日時にアプリデータ削除します。Firebase Authenticationのレコードは残しつつ `disabled: true` に更新し、Firestore / Storage / 関連データを削除します。

### 実行タイミング
- **スケジュール**: `0 4 * * *` （毎日午前4時 JST）
- **タイムアウト**: 540秒（9分）

### 保持期間
- **可変**: `permanentBanScheduledDeletionAt` フィールドに設定された日時
- 現在は永久BAN執行時点から **180日後**

### 検出方法

Firestoreの `users` コレクションに対して、以下の複合クエリを実行します：

1. **`banStatus == "permanent"`**: 永久BANステータスのユーザー
2. **`permanentBanScheduledDeletionAt <= 現在日時`**: 削除予定日時が到達したユーザー

一度の実行で最大20件を処理し、大量のユーザーがいる場合は複数日に分けて削除します。

```typescript
const snapshot = await db.collection("users")
  .where("banStatus", "==", "permanent")
  .where("permanentBanScheduledDeletionAt", "<=", now)
  .limit(20)
  .get();
```

### 削除方法

各ユーザーについて、以下の順序で削除を実行します：

1. **Firebase Authentication無効化**: `admin.auth().updateUser(uid, { disabled: true })`
2. **Storage削除**: `users/{uid}/profile/`, `headers/{uid}.*`, `posts/{uid}/`, `inquiries/{uid}/`
3. **所有サークル削除**: 所有サークル配下の投稿・コメント・リアクション・参加申請・画像・生成AIを削除
4. **本人データ削除**: 本人投稿、問い合わせ、`inquiry_archives`、参加申請、banAppeals、virtueHistory
5. **参照整合**: follow / follower、circle memberIds / subOwnerId を除去
6. **ユーザー配下サブコレクション削除**: notifications, categories, stampSheet, stampSheetArchives, purchases, virtueDaily
7. **Firestore本体削除**: `users/{uid}` を削除（`publicUsers/{uid}` は trigger で削除）

> **注意**: Firebase Authentication レコードは残すため、同一メールアドレスでの再登録は防止されます。一方で 180日経過後はアプリデータを復旧しません。過去に他ユーザー投稿へ残したコメント・リアクションは履歴として保持します。

### 必要なインデックス

| コレクション | フィールド1 | フィールド2 |
|-------------|-----------|-----------| 
| `users` | `banStatus` (Ascending) | `permanentBanScheduledDeletionAt` (Ascending) |

### ソースコード

**ファイル**: `functions/src/index.ts`  
**行番号**: L8432-L8478

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
| `reviewed` | 管理者が対処済みとしたレポート |
| `dismissed` | 管理者が却下（問題なし）としたレポート |

> **注意**: `pending`（未対処）のレポートは削除対象外です。

### 検出方法

Firestoreの `reports` コレクションに対して、2つのクエリを実行します：

1. **`status == "reviewed"` かつ `createdAt < 1ヶ月前`**
2. **`status == "dismissed"` かつ `createdAt < 1ヶ月前`**

```typescript
const cutoffDate = new Date();
cutoffDate.setMonth(cutoffDate.getMonth() - 1);
const cutoffTimestamp = Timestamp.fromDate(cutoffDate);

const reviewedSnapshot = await db.collection("reports")
  .where("status", "==", "reviewed")
  .where("createdAt", "<", cutoffTimestamp)
  .get();

const dismissedSnapshot = await db.collection("reports")
  .where("status", "==", "dismissed")
  .where("createdAt", "<", cutoffTimestamp)
  .get();
```

### 削除方法

取得した全てのレポートをバッチ処理で一括削除します。レポートには関連データ（添付ファイル等）がないため、ドキュメントの削除のみで完了します。

```typescript
const batch = db.batch();
reviewedSnapshot.docs.forEach(doc => batch.delete(doc.ref));
dismissedSnapshot.docs.forEach(doc => batch.delete(doc.ref));
await batch.commit();
```

### ソースコード

**ファイル**: `functions/src/index.ts`  
**行番号**: L7935-L8000

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

| 対象 | 保持期間 | 起算点 | 削除対象 |
|------|---------|-------|---------|
| 孤立メディア | 24時間 | アップロード日時 | Storage + 関連Firestore |
| 解決済み問い合わせ | 7日間 | 解決日時 | Firestore + Storage（アーカイブ保存） |
| ゴーストサークル | 365日 + 7日猶予 | 最後の人間投稿日時 | サークル全体 + 投稿 + メディア |
| 放置サークル | 30日 + 7日猶予 | サークル作成日時 | サークル全体 + 投稿 + メディア |
| 永久BANユーザー | スケジュール日時 | BAN時に設定 | Auth + ユーザードキュメント |
| 対処済みレポート | 1ヶ月 | レポート作成日時 | レポートドキュメントのみ |

---

## ソースコード参照

| 関数名 | ファイル | 行番号 |
|--------|---------|--------|
| `cleanupOrphanedMedia` | `functions/src/index.ts` | L6575-L6780 |
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
| 2026-01-10 | 検出・削除ロジックの詳細説明を追加 |

