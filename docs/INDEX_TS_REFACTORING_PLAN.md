# index.ts 分割リファクタリング計画

## 進捗サマリー

| フェーズ | ステータス | 完了日 |
|---------|-----------|--------|
| Phase 1: 共有ヘルパー抽出 | ✅ 完了・テスト済 | 2026-01-12 |
| Phase 2: AIペルソナ定義分離 | ✅ 完了・テスト済 | 2026-01-12 |
| Phase 3: 独立機能分離 | ✅ 完了・テスト済 | 2026-01-13 |
| Phase 4: サークル関連 | ✅ 完了・テスト済 | 2026-01-13 |
| Phase 5: 投稿・コメント | ✅ 完了・テスト済 | 2026-01-14 |
| Phase 6: 管理者・ユーザー | ✅ 完了・テスト済 | 2026-01-14 |
| Phase 7: スケジュール・HTTP | ✅ 完了・テスト済 | 2026-01-14 |

**2026-01-26 追記**: index.ts に残っていた重い関数を分離し、HTTP/Callable/Triggers/Scheduledへ整理（AI生成、コメント/リアクション、リマインダー、画像モデレーションなど）。

## 現状分析

| 項目 | 初期値 | 現在値 | 削減 |
|------|--------|--------|------|
| 総行数 | 8,628行 | 74行 | -8,554行 (99%) |
| ファイルサイズ | 308KB | ~3KB | -99% |
| export数 | 64関数 | 64関数 | - |


### 作成済みファイル（Phase 1-4）

```
functions/src/
├── ai/
│   └── personas.ts          ✅ 約700行（AIペルソナ定義）
├── config/
│   ├── constants.ts         ✅ プロジェクト定数
│   └── secrets.ts           ✅ シークレット定義
├── helpers/
│   ├── admin.ts             ✅ isAdmin, getAdminUids
│   ├── cloud-tasks-auth.ts  ✅ OIDC認証検証（デバッグログ付き）
│   ├── firebase.ts          ✅ Firebase Admin SDK 共有インスタンス（Phase 3で追加）
│   ├── spreadsheet.ts       ✅ appendInquiryToSpreadsheet（Phase 3で追加）
│   └── storage.ts           ✅ deleteStorageFileFromUrl
├── callable/
│   ├── names.ts             ✅ 約180行（initializeNameParts, getNameParts, updateUserName）
│   ├── reports.ts           ✅ 約130行（reportContent）
│   ├── tasks.ts             ✅ 約210行（createTask, getTasks）
│   ├── inquiries.ts         ✅ 約400行（createInquiry, sendInquiryMessage, sendInquiryReply, updateInquiryStatus）
│   └── circles.ts           ✅ 約580行（Phase 4: deleteCircle, cleanupDeletedCircle, approveJoinRequest, rejectJoinRequest, sendJoinRequest）
├── triggers/
│   └── circles.ts           ✅ 約230行（Phase 4: onCircleCreated, onCircleUpdated）
├── circle-ai/
│   ├── generator.ts         ✅ 約90行（Phase 4: generateCircleAIPersona）
│   └── posts.ts             ✅ 約420行（Phase 4: generateCircleAIPosts, executeCircleAIPost, triggerCircleAIPosts）
├── scheduled/
│   └── circles.ts           ✅ 約290行（Phase 4: checkGhostCircles, evolveCircleAIs, triggerEvolveCircleAIs）
└── types/
    └── index.ts             ✅ モデレーション関連型定義
```

### 問題点
- ファイルが大きすぎてエディタが重い
- マージコンフリクトが発生しやすい
- 単体テストが書きにくい
- どこに何があるか把握しづらい

### 2026-01-12 発覚した問題（教訓）

セキュリティ#15対応（Cloud Tasks OIDC認証）を試行した際に、以下の問題が発生しました。

**試行内容**:
- `helpers/cloud-tasks-auth.ts` を作成（`google-auth-library` を使用）
- `config/constants.ts` を作成
- index.ts でこれらをインポート

**発生した問題**:
```
Container Healthcheck failed - onCircleUpdated, moderateImageCallable
```

**原因**:
- index.ts のトップレベルで `google-auth-library` をインポート
- これにより**すべての関数**で初期化時にライブラリがロードされる
- メモリ256MB制限の関数でメモリ不足が発生

**教訓**:
| 観点 | 詳細 |
|------|------|
| **影響範囲** | index.ts への1つのインポート追加 → 全64関数に影響 |
| **リスク** | 新しいライブラリ追加でメモリ消費増加 → 一部関数が起動不可に |
| **解決策** | **ファイル分割を先に行う**ことで、影響範囲を限定する |

**結論**: セキュリティ修正を安全に適用するには、**リファクタリング（ファイル分割）が必須**

---

## 提案するファイル構成

```
functions/src/
├── index.ts                    # 再エクスポートのみ（約50行）
├── config/
│   ├── constants.ts            # 定数（PROJECT_ID, LOCATION, QUEUE_NAME等）
│   └── secrets.ts              # Secret定義（geminiApiKey, openaiApiKey等）
├── types/
│   └── index.ts                # 型定義（MediaItem, ModerationResult等）
├── helpers/
│   ├── admin.ts                # isAdmin, getAdminUids
│   ├── notification.ts         # sendPushOnly
│   ├── storage.ts              # deleteStorageFileFromUrl
│   ├── sheets.ts               # appendInquiryToSpreadsheet
│   └── virtue.ts               # VIRTUE_CONFIG, penalizeUser
├── ai/
│   ├── provider.ts             # 既存（AIProviderFactory）
│   ├── personas.ts             # AI_PERSONAS, generateAIPersona, 名前パーツ
│   └── moderation.ts           # moderateImage, moderateVideo, moderateMedia
├── triggers/
│   ├── posts.ts                # onPostCreated, onPostDeleted
│   ├── notifications.ts        # onNotificationCreated, onNotificationCreatedPush
│   ├── reactions.ts            # onReactionCreated, onCommentCreatedNotify
│   ├── tasks.ts                # onTaskUpdated, scheduleTaskReminders*
│   └── circles.ts              # onCircleCreated, onCircleUpdated
├── callable/
│   ├── posts.ts                # createPostWithModeration, createPostWithRateLimit
│   ├── comments.ts             # createCommentWithModeration, addUserReaction
│   ├── users.ts                # followUser, unfollowUser, getFollowStatus, getVirtue*
│   ├── tasks.ts                # createTask, getTasks
│   ├── names.ts                # initializeNameParts, getNameParts, updateUserName
│   ├── reports.ts              # reportContent
│   ├── inquiries.ts            # createInquiry, sendInquiryReply, markInquiryViewed等
│   ├── circles.ts              # deleteCircle, approveJoinRequest, sendJoinRequest等
│   ├── admin.ts                # grantAdminRole, removeAdminRole, banUser等
│   └── ai.ts                   # initializeAIAccounts, generateAIPosts, triggerCircleAIPosts
├── scheduled/
│   ├── ai-posts.ts             # scheduleAIPosts
│   ├── reminders.ts            # executeTaskReminder, executeGoalReminder
│   ├── cleanup.ts              # cleanupReports, cleanupOrphanedMedia, cleanupBannedUsers
│   └── circles.ts              # checkGhostCircles, evolveCircleAIs
├── http/
│   ├── ai-generation.ts        # executeAIPostGeneration, generateAICommentV1等
│   ├── circle-cleanup.ts       # cleanupDeletedCircle
│   └── image-moderation.ts     # moderateImageCallable
└── circle-ai/
    ├── generator.ts            # generateCircleAIPersona
    ├── posts.ts                # generateCircleAIPosts, executeCircleAIPost
    └── evolution.ts            # evolveCircleAIs, triggerEvolveCircleAIs
```

---

## 分割優先度（Phase分け）

### Phase 1: 共有ヘルパー抽出（低リスク・高効果）✅ 完了

| ファイル | 抽出対象 | 行数 | ステータス |
|---------|---------|------|----------|
| `helpers/admin.ts` | isAdmin, getAdminUids | 35行 | ✅ 完了 |
| `helpers/storage.ts` | deleteStorageFileFromUrl | 25行 | ✅ 完了 |
| `helpers/cloud-tasks-auth.ts` | verifyCloudTasksRequest | 85行 | ✅ 完了（セキュリティ#15） |
| `config/constants.ts` | PROJECT_ID, LOCATION等 | 18行 | ✅ 完了 |
| `config/secrets.ts` | geminiApiKey等 | 11行 | ✅ 完了 |
| `types/index.ts` | MediaItem, ModerationResult等 | 40行 | ✅ 完了 |
| `helpers/notification.ts` | sendPushOnly | 80行 | ✅ 完了 |

#### ⚠️ 2026-01-25 通知トリガーのズレ（計画と実装の差異）

**発見した差異（コードを正とする）**:
- 本計画では `triggers/notifications.ts` に `onNotificationCreated` を配置する想定（提案構成: notifications.ts に onNotificationCreated）。
- しかし現行ソースには `onNotificationCreated` の実装が存在しない（コメント参照のみ）。
- 多くの箇所が「通知ドキュメント作成で push が自動送信される」前提で実装されている。

**運用リスク**:
- この状態で Cloud Functions を全体 deploy し、未定義関数の削除に同意すると、プッシュ通知が広範囲で停止する可能性がある。

**解決方針（最小で安全な復旧）**:
- `onNotificationCreated` を復活し、「通知ドキュメント作成 → 自動 push」を単一責務として再固定する。
- 柔軟性確保のため、通知ドキュメントに任意フィールドで push 制御を持たせる（例: `pushPolicy: always/never/bySettings`）。
- push 送達状態を通知ドキュメントに記録し、運用観点の追跡性を確保する（`pushStatus` など）。
- ✅ 2026-01-25: `onNotificationCreated` を `triggers/notifications.ts` に復元（pushPolicy/pushStatus対応）

詳細仕様は以下に分離:
- `docs/NOTIFICATION_ON_CREATE_SPEC_2026-01-25.md`

**効果**: 共有コードを1箇所に集約、テスト可能に

**追加対応（セキュリティ#15）**:
- 6つのCloud Tasks関数にOIDC認証を動的インポートで適用
- サービスアカウントを `cloud-tasks-sa@` に統一
- 認証失敗時の詳細ログを追加

---

### Phase 2: AIキャラクター定義分離（中リスク・高効果）✅ 完了

| ファイル | 抽出対象 | 行数 | ステータス |
|---------|---------|------|----------|
| `ai/personas.ts` | OCCUPATIONS, PERSONALITIES, BIO_TEMPLATES, AI_PERSONAS等 | 700行 | ✅ 完了 |

**効果**: 最も行数が多い定数群を分離、index.tsが大幅に軽量化

---

### Phase 3: 独立性の高い機能を分離（低リスク）✅ 完了

| ファイル | 抽出対象 | 行数 | ステータス |
|---------|---------|------|----------|
| `callable/names.ts` | initializeNameParts, getNameParts, updateUserName | 180行 | ✅ 完了 |
| `callable/reports.ts` | reportContent | 130行 | ✅ 完了 |
| `callable/tasks.ts` | createTask, getTasks | 210行 | ✅ 完了 |
| `callable/inquiries.ts` | createInquiry, sendInquiryMessage, sendInquiryReply, updateInquiryStatus | 400行 | ✅ 完了 |
| `helpers/spreadsheet.ts` | appendInquiryToSpreadsheet | 60行 | ✅ 完了（inquiriesから依存） |

**効果**: 約920行をindex.tsから分離、個別機能のテスト・保守が容易に

**注意**: cleanupResolvedInquiries（スケジューラー）とそのヘルパー関数（deleteInquiryWithArchive, sendDeletionWarning）はindex.tsに残置

#### Phase 3 テスト結果（2026-01-13 実施）

| 関数 | テスト結果 | ログ確認 |
|------|-----------|----------|
| `createInquiry` | ✅ 成功 | `Created inquiry: 0n87mbyNbsBeTvb1yMGK` |
| `sendInquiryMessage` | ✅ 成功 | `Added message to inquiry: ...` |
| `sendInquiryReply` | ✅ 成功 | `Sent reply to inquiry: ...` |
| `updateInquiryStatus` | ✅ 成功 | `Updated inquiry status: ... -> in_progress`, `-> resolved` |
| `createTask` | ✅ 成功 | インスタンス起動・正常動作確認 |
| `getTasks` | ✅ 成功 | インスタンス起動・正常動作確認 |
| `getNameParts` | ✅ 成功 | 正常に呼び出し完了 |
| `updateUserName` | ✅ 成功 | `User ... changed name to: まったり🐼パンダ` |
| `reportContent` | ✅ 成功 | `Sent admin notification for report ...` |

**備考**:
- `helpers/firebase.ts` による共有インスタンスパターンが正常に動作
- Firebase初期化タイミングの問題は発生せず
- AppCheckトークン警告は既存の設定（`enforcement is disabled`）によるもので動作に影響なし

---

### Phase 4: サークル関連を分離（中リスク）✅ 完了

| ファイル | 抽出対象 | 行数 | ステータス |
|---------|---------|------|----------|
| `callable/circles.ts` | deleteCircle, cleanupDeletedCircle, approveJoinRequest, rejectJoinRequest, sendJoinRequest | 580行 | ✅ 完了 |
| `triggers/circles.ts` | onCircleCreated, onCircleUpdated | 230行 | ✅ 完了 |
| `circle-ai/generator.ts` | generateCircleAIPersona | 90行 | ✅ 完了 |
| `circle-ai/posts.ts` | generateCircleAIPosts, executeCircleAIPost, triggerCircleAIPosts | 420行 | ✅ 完了 |
| `scheduled/circles.ts` | checkGhostCircles, evolveCircleAIs, triggerEvolveCircleAIs | 290行 | ✅ 完了 |

**効果**: サークル機能を1ディレクトリに集約、約1,610行をindex.tsから分離

#### Phase 4 完了時の修正事項

1. **リージョン指定の追加**: Firestoreトリガー（`onCircleCreated`, `onCircleUpdated`）に `region: LOCATION` を追加
   - 未指定だとFirebaseがus-central1をデフォルトとして認識し、asia-northeast1で動作している既存関数と不一致になる

2. **ハードコードの排除**: `"asia-northeast1"` → `LOCATION` 定数を使用
   - `config/constants.ts` からインポートして一貫性を維持

#### Phase 4 テスト手順

##### T4-1: サークル作成・AI自動生成（onCircleCreated）

| # | テスト項目 | 手順 | 期待結果 | 結果 |
|---|-----------|------|----------|------|
| 1 | サークル作成 | アプリでサークル → 新規作成 → 情報入力 → 作成 | サークルが作成される | |
| 2 | AI3体生成確認 | 作成したサークルのメンバー一覧を確認 | AI3体が自動追加されている | |
| 3 | humanOnlyモード | AIモード「人間のみ」でサークル作成 | AIが生成されない | |

**ログ確認**: Firebase Console → Functions → `onCircleCreated` のログ
```
=== onCircleCreated: [circleId] ===
Generated AI 1: [name] ([id])
Generated AI 2: [name] ([id])
Generated AI 3: [name] ([id])
=== onCircleCreated SUCCESS ===
```

##### T4-2: サークル設定変更通知（onCircleUpdated）

| # | テスト項目 | 手順 | 期待結果 | 結果 |
|---|-----------|------|----------|------|
| 1 | 名前変更 | サークル設定 → 名前を変更 → 保存 | メンバーに通知が届く | |
| 2 | アイコン変更 | サークル設定 → アイコン画像を変更 | 旧画像がStorage削除される | |
| 3 | 内部更新（通知なし） | メンバー追加など内部的な更新 | 通知が送信されない | |

##### T4-3: サークル参加申請（sendJoinRequest, approveJoinRequest, rejectJoinRequest）

| # | テスト項目 | 手順 | 期待結果 | 結果 |
|---|-----------|------|----------|------|
| 1 | 参加申請送信 | 非メンバーでサークル詳細 → 参加申請 | 申請が送信される、オーナーに通知 | |
| 2 | 申請承認 | オーナーで申請一覧 → 承認 | 申請者がメンバーになる、通知が届く | |
| 3 | 申請却下 | オーナーで申請一覧 → 却下 | 申請が削除される、通知が届く | |
| 4 | 重複申請防止 | 同じサークルに再度申請 | エラー「既に申請中です」 | |

##### T4-4: サークル削除（deleteCircle, cleanupDeletedCircle）

| # | テスト項目 | 手順 | 期待結果 | 結果 |
|---|-----------|------|----------|------|
| 1 | サークル削除 | オーナーでサークル設定 → 削除 | サークルが非表示になる | |
| 2 | メンバー通知 | 削除後 | 全メンバーに削除通知が届く | |
| 3 | バックグラウンド処理 | Cloud Tasks確認 | cleanupDeletedCircleがスケジュールされる | |
| 4 | 権限チェック | 非オーナーで削除を試みる | エラー「権限がありません」 | |

##### T4-5: サークルAI投稿（generateCircleAIPosts, executeCircleAIPost）

| # | テスト項目 | 手順 | 期待結果 | 結果 |
|---|-----------|------|----------|------|
| 1 | 手動トリガー | 管理者で `triggerCircleAIPosts` を実行 | Cloud Tasksにタスクがスケジュールされる | |
| 2 | AI投稿生成 | タスク実行後 | サークルAIが投稿を作成 | |

**ログ確認**: `generateCircleAIPosts` → `executeCircleAIPost`

##### T4-6: ゴーストサークル検出（checkGhostCircles）

| # | テスト項目 | 確認方法 | 期待結果 | 結果 |
|---|-----------|----------|----------|------|
| 1 | 定期実行確認 | Cloud Scheduler確認 | 毎日3:30 JSTに実行予定 | |
| 2 | ログ確認 | Functions → checkGhostCircles | 正常にサークルをチェック | |

##### T4-7: サークルAI成長（evolveCircleAIs）

| # | テスト項目 | 手順 | 期待結果 | 結果 |
|---|-----------|------|----------|------|
| 1 | 手動トリガー | 管理者で `triggerEvolveCircleAIs` を実行 | AIのgrowthLevelが+1される | |
| 2 | 上限チェック | growthLevel=5のAIで実行 | レベルが上がらない（上限） | |

**ログ確認**: `evolveCircleAIs` または `triggerEvolveCircleAIs`

#### Phase 4 テスト結果（2026-01-13 実施）

| 関数 | テスト結果 | ログ確認 |
|------|-----------|----------|
| `onCircleCreated` | ✅ 成功 | サークル作成時にAI 3体を自動生成 |
| `onCircleUpdated` | ✅ 成功 | サークル情報更新時にAIプロファイル更新 |
| `sendJoinRequest` | ✅ 成功 | 参加リクエストをFirestoreに記録 |
| `approveJoinRequest` | ✅ 成功 | 参加承認処理が正常完了 |
| `rejectJoinRequest` | - 未実行 | 期間中に拒否操作なし |
| `deleteCircle` | - 未実行 | 期間中に削除操作なし（デプロイは正常） |
| `cleanupDeletedCircle` | - 未実行 | 削除操作なしのため未トリガー |
| `generateCircleAIPosts` | ✅ 成功 | 投稿対象サークル選定・タスク追加完了 |
| `executeCircleAIPost` | ✅ 成功 | Cloud Tasksからトリガー、AI投稿作成成功 |
| `triggerCircleAIPosts` | ✅ 成功 | 手動トリガーでタスクスケジュール確認 |
| `checkGhostCircles` | ✅ 成功 | 定期実行正常（該当なし: 0 ghosts found） |
| `evolveCircleAIs` | ✅ 成功 | 定期実行正常（該当なし: 0 evolved） |
| `triggerEvolveCircleAIs` | ✅ 成功 | 手動トリガー正常動作 |

**備考**: 過去24時間でSeverity: ERROR以上のログは検出されず。

---

### Phase 5: 投稿・コメント・リアクション（中リスク）

| ファイル | 抽出対象 | 行数 |
|---------|---------|------|
| `triggers/posts.ts` | onPostCreated, onPostDeleted | 500行 |
| `callable/posts.ts` | createPostWithModeration等 | 450行 |
| `callable/comments.ts` | createCommentWithModeration, addUserReaction | 180行 |
| `triggers/reactions.ts` | onReactionCreated, onReactionAddedNotify | 120行 |

---

### Phase 6: 管理者・ユーザー管理（低リスク）

| ファイル | 抽出対象 | 行数 |
|---------|---------|------|
| `callable/admin.ts` | grantAdminRole, removeAdminRole, banUser等 | 280行 |
| `callable/users.ts` | followUser, unfollowUser, getVirtue*, cleanUpUserFollows | 350行 |

---

### Phase 7: スケジュール・HTTP関数（低リスク）

| ファイル | 抽出対象 | 行数 |
|---------|---------|------|
| `scheduled/ai-posts.ts` | scheduleAIPosts | 120行 |
| `scheduled/cleanup.ts` | cleanupReports, cleanupOrphanedMedia等 | 380行 |
| `scheduled/reminders.ts` | executeTaskReminder, executeGoalReminder等 | 450行 |
| `http/ai-generation.ts` | executeAIPostGeneration, generateAICommentV1等 | 350行 |

> **運用メモ**: AI自動投稿（scheduleAIPosts）は現在無効化中（`scheduled/ai-posts.ts` 内で早期return）。  
> 需要と負荷を見ながら再有効化を判断する方針。
---

## 分割作業時の注意点

### 1. import/export の整理
```typescript
// 新ファイル（例: helpers/admin.ts）
import * as admin from "firebase-admin";
export async function isAdmin(uid: string): Promise<boolean> { ... }
export async function getAdminUids(): Promise<string[]> { ... }

// index.ts
export { isAdmin, getAdminUids } from "./helpers/admin";
// または
export * from "./helpers/admin";
```

### 2. Secret の扱い
- `defineSecret` は index.ts に残す（関数定義時に必要）
- ヘルパー関数には引数で渡す

### 3. db インスタンス（✅ 実装済み）

**重要**: 分離したモジュールのトップレベルで `admin.firestore()` を直接呼ぶと、`initializeApp()` より先に実行されてエラーになります。

```
FirebaseAppError: The default Firebase app does not exist.
Make sure you call initializeApp() before using any of the Firebase services.
```

**解決策**: `helpers/firebase.ts` で一元管理（推奨・実装済み）

```typescript
// helpers/firebase.ts
import * as admin from "firebase-admin";

// 初期化（複数回呼ばれても安全）
if (admin.apps.length === 0) {
  admin.initializeApp();
}

// 共有インスタンスをエクスポート
export const db = admin.firestore();
export const auth = admin.auth();
export const storage = admin.storage();
export const FieldValue = admin.firestore.FieldValue;
export const Timestamp = admin.firestore.Timestamp;
```

```typescript
// callable/xxx.ts での使用例
import { db, FieldValue, Timestamp } from "../helpers/firebase";

// そのまま使用可能
await db.collection("users").doc(userId).get();
```

**メリット**:
- 初期化タイミングの問題を完全に解消
- コードがシンプル（`getDb()` のような遅延実行パターン不要）
- AI支援コーディングとの相性が良い（標準的なパターン）
- TypeScriptの型推論が効く

### 4. テスト
- 各Phaseの完了後に `npm run build` と動作確認
- デプロイ前に全関数のスモークテスト

---

## 重複パターンの共通化

### 発見された重複パターン

| パターン | 出現回数 | 共通化優先度 |
|---------|---------|-------------|
| 認証チェック（`!request.auth`） | 29箇所 | 高 |
| HttpsError スロー | 60箇所以上 | 高 |
| 管理者権限チェック（`isAdmin`呼び出し） | 16箇所 | 高 |
| 通知作成（`notifications.add`） | 17箇所 | 高 |
| Cloud Tasks 作成 | 16箇所 | 中 |
| console.log/error/warn | 386箇所 | 低（整理対象）|
| Firestore FieldValue操作 | 102箇所 | - |

---

### 共通化計画

#### 1. エラーメッセージ定数化（優先度：高）

**現状**: 同じエラーメッセージがハードコードで散在

```typescript
// 現状（60箇所以上で類似）
throw new HttpsError("unauthenticated", "ログインが必要です");
throw new HttpsError("permission-denied", "管理者権限が必要です");
throw new HttpsError("not-found", "ユーザーが見つかりません");
```

**共通化後**:

```typescript
// helpers/errors.ts
export const ErrorMessages = {
  // 認証
  UNAUTHENTICATED: "ログインが必要です",
  ADMIN_REQUIRED: "管理者権限が必要です",

  // バリデーション
  INVALID_ARGUMENT: "必要な情報が不足しています",
  SELF_ACTION_NOT_ALLOWED: (action: string) => `自分自身を${action}することはできません`,

  // リソース
  USER_NOT_FOUND: "ユーザーが見つかりません",
  POST_NOT_FOUND: "投稿が見つかりません",
  CIRCLE_NOT_FOUND: "サークルが見つかりません",
  TASK_NOT_FOUND: "タスクが見つかりません",

  // 重複
  ALREADY_EXISTS: (item: string) => `既に${item}しています`,
  ALREADY_REPORTED: "既にこの内容を通報しています",
  ALREADY_FOLLOWING: "既にフォローしています",

  // システム
  INTERNAL_ERROR: "システムエラーが発生しました。しばらくしてから再度お試しください。",
} as const;

// 使用例
throw new HttpsError("unauthenticated", ErrorMessages.UNAUTHENTICATED);
throw new HttpsError("not-found", ErrorMessages.USER_NOT_FOUND);
```

---

#### 2. 認証ヘルパー関数（優先度：高）

**現状**: 各関数で同じ認証チェックを繰り返し

```typescript
// 現状（29箇所で同じパターン）
if (!request.auth) {
  throw new HttpsError("unauthenticated", "ログインが必要です");
}
const userId = request.auth.uid;

// 管理者チェック（16箇所）
const userIsAdmin = await isAdmin(request.auth.uid);
if (!userIsAdmin) {
  throw new HttpsError("permission-denied", "管理者権限が必要です");
}
```

**共通化後**:

```typescript
// helpers/auth.ts
import { HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { ErrorMessages } from "./errors";

/**
 * 認証済みユーザーのUIDを取得（未認証ならエラー）
 */
export function requireAuth(request: CallableRequest): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", ErrorMessages.UNAUTHENTICATED);
  }
  return request.auth.uid;
}

/**
 * 管理者権限を要求（未認証または非管理者ならエラー）
 */
export async function requireAdmin(request: CallableRequest): Promise<string> {
  const uid = requireAuth(request);
  const adminStatus = await isAdmin(uid);
  if (!adminStatus) {
    throw new HttpsError("permission-denied", ErrorMessages.ADMIN_REQUIRED);
  }
  return uid;
}

// 使用例（Before: 5行 → After: 1行）
export const followUser = onCall(async (request) => {
  const userId = requireAuth(request);  // これだけ！
  // ...
});

export const deleteAllAIUsers = onCall(async (request) => {
  const adminId = await requireAdmin(request);  // これだけ！
  // ...
});
```

---

#### 3. 通知ヘルパー関数（優先度：高）

**現状**: 通知作成が17箇所で類似パターン

```typescript
// 現状
await db.collection("users").doc(userId).collection("notifications").add({
  type: "task_reminder",
  title: "タスクのお知らせ",
  body: "タスクの期限が近づいています",
  isRead: false,
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
  taskId: taskId,
});
```

**共通化後**:

```typescript
// helpers/notification.ts
interface NotificationOptions {
  userId: string;
  type: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

/**
 * ユーザーに通知を作成
 */
export async function createNotification(options: NotificationOptions): Promise<string> {
  const { userId, type, title, body, data = {} } = options;

  const notificationRef = await db
    .collection("users")
    .doc(userId)
    .collection("notifications")
    .add({
      type,
      title,
      body,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      ...data,
    });

  console.log(`Notification created: ${type} for user ${userId}`);
  return notificationRef.id;
}

/**
 * 複数ユーザーに通知を一括作成
 */
export async function createNotificationsForUsers(
  userIds: string[],
  options: Omit<NotificationOptions, "userId">
): Promise<void> {
  const batch = db.batch();

  for (const userId of userIds) {
    const ref = db.collection("users").doc(userId).collection("notifications").doc();
    batch.set(ref, {
      ...options,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  await batch.commit();
  console.log(`Notifications created for ${userIds.length} users`);
}

// 使用例
await createNotification({
  userId: targetUserId,
  type: "task_reminder",
  title: "タスクのお知らせ",
  body: "タスクの期限が近づいています",
  data: { taskId },
});

// 管理者全員に通知
const adminUids = await getAdminUids();
await createNotificationsForUsers(adminUids, {
  type: "admin_report",
  title: "新規通報を受信",
  body: notifyBody,
  data: { reportId },
});
```

---

#### 4. Cloud Tasks ヘルパー（優先度：中）

**現状**: 16箇所でCloud Tasksを作成

```typescript
// helpers/cloud-tasks.ts
interface TaskOptions {
  queue: string;
  url: string;
  payload: Record<string, unknown>;
  scheduleTime?: Date;
}

export async function scheduleTask(options: TaskOptions): Promise<string> {
  const tasksClient = new CloudTasksClient();
  const project = process.env.GCLOUD_PROJECT || PROJECT_ID;
  const parent = tasksClient.queuePath(project, LOCATION, options.queue);

  const task = {
    httpRequest: {
      httpMethod: "POST" as const,
      url: options.url,
      body: Buffer.from(JSON.stringify(options.payload)).toString("base64"),
      headers: { "Content-Type": "application/json" },
      oidcToken: {
        serviceAccountEmail: `${project}@appspot.gserviceaccount.com`,
      },
    },
    ...(options.scheduleTime && {
      scheduleTime: {
        seconds: Math.floor(options.scheduleTime.getTime() / 1000),
      },
    }),
  };

  const [response] = await tasksClient.createTask({ parent, task });
  console.log(`Task scheduled: ${response.name}`);
  return response.name || "";
}
```

---

### 共通化による効果

| パターン | Before（行数）| After（行数）| 削減率 |
|---------|-------------|------------|--------|
| 認証チェック | 145行（29×5行）| 29行（29×1行）| 80% |
| エラースロー | 60行 | 60行（メッセージ一元管理）| - |
| 通知作成 | 170行（17×10行）| 51行（17×3行）| 70% |
| Cloud Tasks | 160行（16×10行）| 48行（16×3行）| 70% |
| **合計** | **約535行** | **約188行** | **65%** |

---

### 推奨する共通化ファイル

```
functions/src/
├── helpers/
│   ├── admin.ts        # isAdmin, getAdminUids（既存を移動）
│   ├── auth.ts         # requireAuth, requireAdmin【新規】
│   ├── errors.ts       # ErrorMessages【新規】
│   ├── notification.ts # createNotification【新規】
│   ├── storage.ts      # deleteStorageFileFromUrl（既存を移動）
│   ├── cloud-tasks.ts  # scheduleTask【新規】
│   ├── cloud-tasks-auth.ts # verifyCloudTasksRequest【新規・セキュリティ#15】
│   └── index.ts        # 再エクスポート
└── ...
```

### Cloud TasksリクエストのOIDC認証（セキュリティ#15対応）

現在6つの `onRequest` 関数で認証ヘッダーの存在チェックのみ行っていますが、
トークンの正当性を検証する共通ヘルパーを作成します。

**対象関数**:
- `generateAICommentV1`
- `generateAIReactionV1`
- `executeAIPostGeneration`
- `executeTaskReminder`
- `cleanupDeletedCircle`
- `executeCircleAIPost`

**ヘルパー関数設計**:

### 推奨する共通化ファイル

```typescript
// config/constants.ts
import * as dotenv from 'dotenv';
dotenv.config();

export const PROJECT_ID = process.env.GCLOUD_PROJECT || "positive-sns";
export const LOCATION = "asia-northeast1";

export const CLOUD_TASK_FUNCTIONS = {
  generateAICommentV1: "generateAICommentV1",
  generateAIReactionV1: "generateAIReactionV1",
  executeAIPostGeneration: "executeAIPostGeneration",
  executeTaskReminder: "executeTaskReminder",
  cleanupDeletedCircle: "cleanupDeletedCircle",
  executeCircleAIPost: "executeCircleAIPost",
} as const;
```

```typescript
// helpers/cloud-tasks-auth.ts
import { OAuth2Client } from "google-auth-library";
import * as functionsV1 from "firebase-functions/v1";
import { PROJECT_ID, LOCATION } from "../config/constants";

const authClient = new OAuth2Client();

// エミュレータ判定
const IS_EMULATOR = process.env.FUNCTIONS_EMULATOR === "true";

/**
 * Cloud Tasksからのリクエストを検証
 * OIDCトークンを検証し、正当なリクエストかどうかを判定
 *
 * 検証項目:
 * 1. Bearer トークンの存在
 * 2. トークンの署名検証（Google発行であること）
 * 3. audience（呼び出し先関数URL）の一致
 */
export async function verifyCloudTasksRequest(
  request: functionsV1.https.Request,
  functionName: string
): Promise<boolean> {
  // エミュレータでは認証スキップ（開発時のみ）
  if (IS_EMULATOR) {
    console.log(`[DEV] Skipping auth for ${functionName}`);
    return true;
  }

  const authHeader = request.headers.authorization;
  if (!authHeader?.startsWith("Bearer ")) {
    return false;
  }

  try {
    await authClient.verifyIdToken({
      idToken: authHeader.split("Bearer ")[1],
      audience: `https://${LOCATION}-${PROJECT_ID}.cloudfunctions.net/${functionName}`,
    });
    return true;
  } catch (error) {
    console.error(`Token verification failed for ${functionName}:`,
      error instanceof Error ? error.message : "Unknown error"
    );
    return false;
  }
}
```

**使用例**:

```typescript
// 各onRequest関数内
if (!await verifyCloudTasksRequest(request, CLOUD_TASK_FUNCTIONS.generateAICommentV1)) {
  response.status(403).send("Unauthorized");
  return;
}
```

**依存関係**: `google-auth-library`

### リスクと注意点（#15統合時）

#### 1. 依存関係リスク

| リスク | 詳細 | 対策 |
|--------|------|------|
| `google-auth-library` 未導入 | パッケージが未インストールの可能性 | `package.json` を確認し、必要なら追加 |

#### 2. 設定ミスリスク

| リスク | 詳細 | 対策 |
|--------|------|------|
| **PROJECT_ID の参照** | `config/constants.ts` からのインポートが必要 | 分割時にインポートパスを確認 |
| **関数名の不一致** | 呼び出し時に関数名を文字列で渡すため、タイポの可能性 | 関数名を定数化（下記参照） |
| ~~リージョン固定~~ | ~~ハードコード~~ | ✅ `LOCATION` 定数で対応済み |

**関数名の定数化（推奨）**:

```typescript
// config/constants.ts に追加
export const CLOUD_TASK_FUNCTIONS = {
  generateAICommentV1: "generateAICommentV1",
  generateAIReactionV1: "generateAIReactionV1",
  executeAIPostGeneration: "executeAIPostGeneration",
  executeTaskReminder: "executeTaskReminder",
  cleanupDeletedCircle: "cleanupDeletedCircle",
  executeCircleAIPost: "executeCircleAIPost",
} as const;

// 使用例
if (!await verifyCloudTasksRequest(request, CLOUD_TASK_FUNCTIONS.generateAICommentV1)) {
  // ...
}
```

#### 3. 運用リスク

| リスク | 影響 | 発生条件 |
|--------|------|----------|
| **正当なリクエスト拒否** | Cloud Tasksからの処理が全て失敗 | audience URLが不正確な場合 |
| **ロールバック困難** | 認証強化後に問題発覚すると切り戻しが必要 | テスト不足の場合 |
| **ローカル開発不可** | エミュレータではOIDCトークンが発行されない | 開発時のみ認証スキップが必要 |

#### 4. 推奨する導入手順

1. **依存関係確認**: `google-auth-library` がインストール済みか確認
2. **段階的導入**: 1関数ずつ適用（全6関数を一度に変更しない）
3. **本番テスト**: Cloud Tasksからの実リクエストでテスト（エミュレータでは検証不可）
4. **ログ監視**: デプロイ後はCloud Functionsのログを監視

#### 5. テスト計画

| テスト項目 | 方法 | 期待結果 |
|-----------|------|----------|
| 正当なCloud Tasksリクエスト | 本番環境でタスクをトリガー | 正常に処理される |
| 不正なトークン | curlで偽トークンを送信 | 403エラー |
| トークンなし | curlでヘッダーなしリクエスト | 403エラー |
| audience不一致 | 別関数のURLでトークン生成 | 403エラー |

---

## 分割しやすさランキング

| 順位 | ファイル | 理由 |
|-----|---------|------|
| 1 | `callable/inquiries.ts` | 外部依存なし、完全独立 |
| 2 | `callable/names.ts` | 外部依存なし、完全独立 |
| 3 | `callable/reports.ts` | isAdminのみ依存、ほぼ独立 |
| 4 | `helpers/admin.ts` | 依存なし、多くの箇所で使用 |
| 5 | `helpers/storage.ts` | 依存なし |
| 6 | `types/index.ts` | 型定義のみ |
| 7 | `ai/personas.ts` | 行数最大、定数のみ |
| 8 | `callable/tasks.ts` | isAdminのみ依存 |
| 9 | `callable/users.ts` | isAdmin, VIRTUE_CONFIG依存 |
| 10 | `triggers/reactions.ts` | db依存のみ |

---

## 推奨作業順序

1. **helpers/admin.ts** を作成（isAdmin, getAdminUids）
2. **helpers/storage.ts** を作成（deleteStorageFileFromUrl）
3. **types/index.ts** を作成（MediaItem等の型）
4. **callable/inquiries.ts** を作成（問い合わせ全体）
5. **callable/names.ts** を作成（名前パーツ全体）
6. **ai/personas.ts** を作成（AIキャラ定義）
7. 動作確認・デプロイテスト
8. 残りを順次分離

---

## 期待される効果

| 項目 | Before | After（予想）|
|------|--------|-------------|
| index.ts行数 | 8,628行 | 約100行（再エクスポートのみ）|
| 平均ファイル行数 | - | 200-400行 |
| ビルド時間 | - | 変化なし |
| 開発効率 | 低 | 高（検索・ナビゲーション改善）|
| テスト容易性 | 低 | 高（単体テスト可能）|
| マージコンフリクト | 高 | 低（ファイル分散）|

---

## 投稿作成関数の責務分離（推奨）

### 現状の問題

| 関数 | 用途 | 問題点 |
|------|------|--------|
| `createPostWithModeration` | 通常投稿 | レート制限なし |
| `createPostWithRateLimit` | タスク達成自動投稿 | 命名が汎用的、AIServiceに配置 |

### 推奨改善

| 現状 | 改善後 | 理由 |
|------|--------|------|
| `createPostWithRateLimit` | `createSystemPost` | 用途を明確化（システム自動投稿） |
| `AIService` に配置 | `callable/posts.ts` に配置 | AI関連ではないため |
| `createPostWithModeration` にレート制限なし | レート制限を追加 | スパム対策 |

### 詳細

1. **`createPostWithRateLimit` → `createSystemPost` に改名**
   - タスク達成・目標達成などシステム自動投稿専用
   - モデレーション不要（内容が固定）
   - レート制限も不要（発火タイミングが制御されている）

2. **`createPostWithModeration` にレート制限を追加**
   - ユーザーが連打でスパム投稿するのを防止
   - 推奨：1分間に3投稿まで

3. **責務の分離を維持**
   - 1関数に統合せず、用途別に関数を分ける
   - テスト容易性・変更影響範囲の最小化

---

## 実機テスト計画

### テスト前提条件

- テスト用アカウント（一般ユーザー）を用意
- テスト用アカウント（管理者権限付き）を用意
- デバッグビルドのアプリを使用
- Firebase Console でログを確認できる状態にしておく

---

### Phase 1 完了後のテスト（ヘルパー抽出）

#### T1-1: 管理者権限チェック（isAdmin, getAdminUids）

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | 管理者機能へのアクセス | 管理者アカウントでログイン → 管理画面を開く | 管理画面が表示される |
| 2 | 一般ユーザーの制限 | 一般アカウントでログイン → 管理機能のあるボタンをタップ | エラーまたは権限不足メッセージ |
| 3 | 問い合わせ通知 | 一般ユーザーで問い合わせを送信 | 管理者全員に通知が届く |

#### T1-2: Storage削除（deleteStorageFileFromUrl）

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | 投稿削除時の画像削除 | 画像付き投稿を作成 → 投稿を削除 | Storageから画像も削除される（Console確認）|
| 2 | サークルアイコン更新 | サークルアイコンを変更 | 旧アイコンがStorageから削除される |

---

### Phase 2 完了後のテスト（AIキャラ定義分離）

#### T2-1: AIキャラクター動作

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | AIコメント生成 | 投稿を作成（AIモード） | 数秒〜1分後にAIからコメントが付く |
| 2 | AIプロフィール表示 | AIユーザーのプロフィールを開く | 名前・bio・アバターが正常表示 |
| 3 | AIリアクション | 投稿を作成 → しばらく待つ | AIからリアクションが付く |

#### T2-2: サークルAI

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | サークルAI生成 | 新規サークルを作成 | 3体のAIメンバーが自動生成される |
| 2 | サークルAIプロフィール | サークルAIのプロフィールを開く | 正常に表示される |

---

### Phase 3 完了後のテスト（独立機能分離）

#### T3-1: 問い合わせ機能（inquiries）

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | 問い合わせ作成 | 設定 → 問い合わせ → 新規作成 → 送信 | 問い合わせが作成される |
| 2 | 画像付き問い合わせ | 問い合わせ作成時に画像を添付 → 送信 | 画像付きで送信される |
| 3 | 管理者返信 | 管理者で問い合わせに返信 | ユーザーに通知が届く |
| 4 | ユーザー返信 | ユーザーで返信 | 管理者に通知が届く |
| 5 | 問い合わせ解決 | 管理者が「解決」ボタンをタップ | ステータスが「解決済み」に変わる |
| 6 | 問い合わせ削除 | 問い合わせを削除 | 一覧から消える、添付画像もStorage削除 |

#### T3-2: タスク機能（tasks）

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | タスク作成 | タスク画面 → 新規タスク → 保存 | タスクが一覧に表示される |
| 2 | タスク編集 | タスクをタップ → 内容変更 → 保存 | 変更が反映される |
| 3 | タスク完了 | タスクのチェックボックスをタップ | 完了状態になる |
| 4 | リマインダー設定 | タスクにリマインダーを設定 | 設定時刻に通知が届く |

#### T3-3: 名前パーツ機能（names）

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | 名前変更 | プロフィール編集 → 名前変更 | 新しい名前が反映される |
| 2 | 名前パーツ取得 | 名前編集画面を開く | 利用可能なパーツ一覧が表示される |

#### T3-4: 通報機能（reports）

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | 投稿を通報 | 投稿のメニュー → 通報 → 理由選択 → 送信 | 通報完了メッセージ |
| 2 | 重複通報防止 | 同じ投稿を再度通報 | 「既に通報済み」エラー |
| 3 | 通報多数で非表示 | 5アカウントから同じ投稿を通報 | 投稿が非表示になる |

---

### Phase 4 完了後のテスト（サークル関連）

#### T4-1: サークル基本操作

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | サークル作成 | サークル → 新規作成 → 情報入力 → 作成 | サークルが作成される、AI3体生成 |
| 2 | サークル編集 | サークル設定 → 情報編集 → 保存 | 変更が反映される |
| 3 | サークル削除 | サークル設定 → 削除 | サークルが削除される |
| 4 | アイコン/カバー変更 | サークル設定 → 画像変更 | 新画像が反映、旧画像がStorage削除 |

#### T4-2: サークル参加

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | 参加申請 | 非メンバーでサークル詳細 → 参加申請 | 申請が送信される |
| 2 | 申請承認 | オーナーで申請一覧 → 承認 | 申請者がメンバーになる |
| 3 | 申請却下 | オーナーで申請一覧 → 却下 | 申請が削除される |

#### T4-3: サークルAI投稿

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | サークルAIコメント | サークル内で投稿 | サークルAIからコメントが付く |
| 2 | サークルAI投稿（管理者） | 管理画面 → サークルAI投稿トリガー | サークルAIが投稿を作成 |

---

### Phase 5 完了後のテスト（投稿・コメント・リアクション）

#### T5-1: 投稿機能

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | テキスト投稿 | 投稿作成 → テキスト入力 → 投稿 | 投稿がタイムラインに表示 |
| 2 | 画像付き投稿 | 投稿作成 → 画像添付 → 投稿 | 画像付きで投稿される |
| 3 | 動画付き投稿 | 投稿作成 → 動画添付 → 投稿 | 動画付きで投稿される |
| 4 | NGワード検出 | 禁止ワードを含む投稿を試みる | 投稿がブロックされる |
| 5 | 不適切画像検出 | 不適切な画像を添付して投稿 | モデレーションでブロック |
| 6 | 投稿削除 | 自分の投稿 → 削除 | 投稿が削除、画像もStorage削除 |

#### T5-2: コメント機能

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | コメント投稿 | 投稿詳細 → コメント入力 → 送信 | コメントが表示される |
| 2 | コメント通知 | 他ユーザーの投稿にコメント | 投稿者に通知が届く |
| 3 | NGワード検出 | 禁止ワードを含むコメント | ブロックされる |

#### T5-3: リアクション機能

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | リアクション追加 | 投稿のリアクションボタンをタップ | リアクションが追加される |
| 2 | リアクション通知 | 他ユーザーの投稿にリアクション | 投稿者に通知が届く |
| 3 | totalPraises更新 | リアクションを受ける | ユーザーのtotalPraisesが増加 |

---

### Phase 6 完了後のテスト（管理者・ユーザー管理）

#### T6-1: フォロー機能

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | フォロー | ユーザープロフィール → フォロー | フォロー状態になる |
| 2 | フォロー解除 | フォロー中のユーザー → フォロー解除 | フォロー解除される |
| 3 | フォロー状態確認 | プロフィール画面を開く | 正しいフォロー状態が表示 |

#### T6-2: 徳システム

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | 徳ポイント確認 | プロフィール → 徳ステータス | 現在の徳ポイントが表示 |
| 2 | 徳履歴確認 | 徳履歴画面を開く | 履歴一覧が表示される |

#### T6-3: 管理者機能

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | 管理者権限付与 | 管理画面 → ユーザー → 管理者権限付与 | 権限が付与される |
| 2 | 管理者権限削除 | 管理画面 → ユーザー → 管理者権限削除 | 権限が削除される |
| 3 | ユーザーBAN | 管理画面 → ユーザー → BAN | BANされる、通知が届く |
| 4 | BAN解除 | 管理画面 → BANユーザー → 解除 | BAN解除される |

---

### Phase 7 完了後のテスト（スケジュール・HTTP関数）

#### T7-1: リマインダー

| # | テスト項目 | 手順 | 期待結果 |
|---|-----------|------|----------|
| 1 | タスクリマインダー | リマインダー付きタスクを作成 | 設定時刻に通知が届く |
| 2 | 目標リマインダー | リマインダー付き目標を作成 | 設定時刻に通知が届く |

#### T7-2: 定期クリーンアップ（Firebase Console確認）

| # | テスト項目 | 確認方法 | 期待結果 |
|---|-----------|----------|----------|
| 1 | cleanupReports | Consoleでログ確認 | 古いレポートが削除される |
| 2 | cleanupOrphanedMedia | Consoleでログ確認 | 孤立メディアが削除される |
| 3 | checkGhostCircles | Consoleでログ確認 | ゴーストサークル検出・通知 |

---

## 全体テストチェックリスト

分割完了後、以下を順番に確認してください。

### 基本動作確認

- [ ] アプリが起動する
- [ ] ログイン/ログアウトができる
- [ ] タイムラインが表示される
- [ ] プッシュ通知が届く

### 投稿関連

- [ ] テキスト投稿ができる
- [ ] 画像付き投稿ができる
- [ ] 投稿削除ができる
- [ ] AIコメントが付く
- [ ] AIリアクションが付く
- [ ] モデレーションが動作する

### サークル関連

- [ ] サークル作成ができる
- [ ] サークルAIが生成される
- [ ] サークルへの参加申請ができる
- [ ] サークル内投稿にAIコメントが付く
- [ ] サークル削除ができる

### ユーザー関連

- [ ] フォロー/フォロー解除ができる
- [ ] 名前変更ができる
- [ ] プロフィール編集ができる
- [ ] 通報ができる

### タスク・目標関連

- [ ] タスク作成・編集・完了ができる
- [ ] タスクリマインダーが届く
- [ ] 目標リマインダーが届く

### 問い合わせ関連

- [ ] 問い合わせ作成ができる
- [ ] 管理者返信ができる
- [ ] 問い合わせ解決ができる

### 管理者機能（管理者アカウントで確認）

- [ ] 管理画面にアクセスできる
- [ ] ユーザーBAN/解除ができる
- [ ] 管理者権限付与/削除ができる

---

## トラブルシューティング

### デプロイ後に関数が動かない場合

1. Firebase Console → Functions → ログを確認
2. エラーメッセージを確認
3. よくある原因:
   - import パスの誤り
   - export の漏れ
   - Secret が関数に紐付いていない

### 特定の機能だけ動かない場合

1. その機能に関連する関数を特定
2. Firebase Console でその関数のログを確認
3. 分割前のコードと比較してimport/exportを確認

### ロールバック手順

1. `git revert` で分割前の状態に戻す
2. `firebase deploy --only functions` で再デプロイ
3. 動作確認後、問題点を修正して再度分割

---

## 備考

- Firebase Functions では、すべてのexportが `index.ts` から見える必要がある
- 分割後も `index.ts` で再エクスポートすれば既存の呼び出しに影響なし
- Cloud Functions のデプロイ名は export 名で決まるため、リネーム不要
