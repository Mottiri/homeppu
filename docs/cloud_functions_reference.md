# Cloud Functions リファレンス

AI支援開発用のクイックリファレンス。実装修正・追加時にこのドキュメントを参照してください。

---

## 📁 ディレクトリ構成

```
functions/src/
├── index.ts           # エントリーポイント（全エクスポート）
├── config/            # 設定・定数
├── callable/          # ユーザー呼び出し関数
├── scheduled/         # 定期実行関数
├── triggers/          # Firestoreトリガー
├── circle-ai/         # サークルAI専用
├── ai/                # AI関連（プロンプト・プロバイダー）
├── helpers/           # ヘルパー関数
├── http/              # HTTP関数
└── types/             # 型定義
```

---

## 📋 機能別ファイル一覧

### callable/ - ユーザー呼び出し関数

| ファイル | 機能 | 主な関数 |
|---------|------|---------|
| `admin.ts` | 管理者機能 | `cleanUpUserFollows`, `deleteAllAIUsers`, `cleanupOrphanedCircleAIs`, `backfillPublicUsers`, `backfillCircleNameTokens`, `adminDeletePostWithPenalty`, `adminDeleteCommentWithPenalty`, `setAdminRole`, `removeAdminRole`, `banUser`, `permanentBanUser`, `unbanUser` |
| `users.ts` | ユーザー機能 | `followUser`, `unfollowUser`, `getFollowStatus`, `getVirtueHistory`, `getVirtueStatus`, `checkPasswordResetTarget` |
| `virtue_shop.ts` | 徳ポイントショップ | `getVirtueShopConfig`, `purchaseVirtueItem` |
| `posts.ts` | 投稿作成 | `createPostWithRateLimit`, `createPostWithModeration` |
| `comments.ts` | コメント・リアクション | `createCommentWithModeration`, `deleteComment`, `addUserReaction`, `removeUserReaction` |
| `rewarded_reactions.ts` | リワード解放 | `grantRewardedReactionUnlock` |
| `circles.ts` | サークル管理 | `deleteCircle`, `cleanupDeletedCircle`, `startCircleBrowseTrial`, `endCircleBrowseTrial`, `approveJoinRequest`, `rejectJoinRequest`, `sendJoinRequest`, `joinCircle`, `leaveCircle`, `searchCircles` |
| `tasks.ts` | タスク管理 | `createTask`, `getTasks` |
| `reports.ts` | 通報機能 | `reportContent` |
| `names.ts` | 名前管理 | `initializeNameParts`, `getNameParts`, `updateUserName` |
| `inquiries.ts` | 問い合わせ | `createInquiry`, `sendInquiryMessage`, `sendInquiryReply`, `updateInquiryStatus` |
| `ai.ts` | AI管理 | `initializeAIAccounts`, `generateAIPosts` |

### scheduled/ - 定期実行関数

| ファイル | 機能 | スケジュール |
|---------|------|-------------|
| `circles.ts` | サークル管理 | `checkGhostCircles`（毎日21:00。`nextGhostCheckAt` 到来分のみ処理。既存データには `scripts/backfill-circle-scheduling.js` を先に実行）、`evolveCircleAIs`（毎月1日10時）、`triggerEvolveCircleAIs`（手動トリガー用） |
| `cleanup.ts` | クリーンアップ | `cleanupOrphanedMedia`（毎日3時。`pendingMedia` の期限切れ未確定メディアのみを対象に削除/解決）、`cleanupResolvedInquiries`、`cleanupReports`、`cleanupBannedUsers`（永久BAN 180日後に Auth を保持したままアプリデータ削除）、`cleanupUnverifiedUsers` |
| `reminders.ts` | タスク/目標リマインダー通知 | `executeTaskReminder`, `executeGoalReminder`（Cloud Tasks HTTP） |
| `ai-posts.ts` | AI投稿 | `scheduleAIPosts`（現在無効化中） |

### triggers/ - Firestoreトリガー

| ファイル | 機能 | トリガー対象 |
|---------|------|-------------|
| `circles.ts` | サークル | `onCircleCreated`（作成時AI生成）、`onCircleUpdated`（更新時メンバー通知） |
| `posts.ts` | 投稿 | `onPostCreated`（作成時AIコメント・リアクションスケジュール） |
| `users.ts` | ユーザー | `onUserCreated`, `onUserUpdated`, `onUserDeleted`（publicUsers同期） |
| `notifications.ts` | 通知 | `onNotificationCreated`（自動プッシュ送信）、`onCommentCreatedNotify`、`onReactionAddedNotify` |
| `tasks.ts` | タスク | `onTaskUpdated`, `scheduleTaskReminders`, `scheduleTaskRemindersOnCreate` |
| `goals.ts` | 目標 | `scheduleGoalReminders`, `scheduleGoalRemindersOnCreate`, `onGoalUpdatedForVirtue` |
| `reactions.ts` | リアクション | `onReactionCreated` |

補足（2026-01-25）:
- `users/{userId}/notifications/{notificationId}` の作成で `onNotificationCreated` が自動でFCM送信
- `pushPolicy: never` を通知ドキュメントに持たせると「通知は作るがpushは送らない」

### http/ - HTTP関数

| ファイル | 機能 | 主な関数 |
|---------|------|---------|
| `ai-generation.ts` | AI生成HTTP関数 | `generateAICommentV1`, `generateAIReactionV1`, `executeAIPostGeneration` |
| `image-moderation.ts` | 画像モデレーション | `moderateImageCallable` |
| `revenuecat.ts` | RevenueCat連携 | `revenueCatWebhook` |

### circle-ai/ - サークルAI専用

| ファイル | 機能 | 主な関数 |
|---------|------|---------|
| `posts.ts` | サークルAI投稿 | `generateCircleAIPosts`（`nextCircleAIPostAt` 到来分のみ処理。既存データには `scripts/backfill-circle-scheduling.js` を先に実行）, `executeCircleAIPost`（`requestId` ベースで冪等）, `triggerCircleAIPosts` |
| `generator.ts` | サークルAIペルソナ生成 | `generateCircleAIPersona` |

### ai/ - AI関連

| ファイル | 機能 |
|---------|------|
| `provider.ts` | AIプロバイダーファクトリー（Gemini/OpenAI） |
| `personas.ts` | AIペルソナ定義・システムプロンプト・名前パーツ定義 |
| `prompts/comment.ts` | コメント生成プロンプト |
| `prompts/moderation.ts` | モデレーションプロンプト |
| `prompts/post-generation.ts` | 投稿生成プロンプト |
| `prompts/bio-generation.ts` | bio生成プロンプト |
| `prompts/media-analysis.ts` | メディア分析プロンプト |

### config/ - 設定

| ファイル | 内容 |
|---------|------|
| `constants.ts` | `LOCATION`, `PROJECT_ID`, `AI_MODELS` |
| `messages.ts` | エラーメッセージ・通知タイトル・ラベル定数 |
| `secrets.ts` | APIキー取得（`geminiApiKey`, `openaiApiKey`, `revenueCatWebhookSecret`） |
| `collections.ts` | コレクション名定数 |

### helpers/ - ヘルパー

| ファイル | 機能 |
|---------|------|
| `firebase.ts` | Firestore初期化・db取得・FieldValue・Timestamp |
| `admin.ts` | 管理者権限確認 `isAdmin()`, `getAdminUids()` |
| `auth.ts` | 認証関連 `requireAuth()`, `requireAdmin()` |
| `virtue.ts` | 徳ポイント計算 `VIRTUE_CONFIG` |
| `virtue-policy.ts` | 徳ポイント方針取得/加点処理（`settings/virtuePolicy`） |
| `notification.ts` | プッシュ通知送信 `sendPushNotification`, `sendPushOnly` |
| `storage.ts` | Storageファイル削除 `deleteStorageFileFromUrl`, `deleteStorageFileByPath`, `extractStoragePathFromUrl` |
| `pending-media.ts` | pendingMedia管理 `getMediaStoragePath`, `getMediaStoragePaths`, `deletePendingMediaByStoragePaths` |
| `circle-scheduling.ts` | サークル定期処理の due-at 計算 `computeNextGhostCheckAt`, `computeNextCircleAIPostAt` |
| `moderation.ts` | メディアモデレーション `moderateMedia` |
| `media-analysis.ts` | メディア分析 `analyzeMediaForComment` |
| `cloud-tasks.ts` | Cloud Tasks操作 `scheduleHttpTask` |
| `cloud-tasks-auth.ts` | Cloud Tasks認証 `verifyCloudTasksRequest` |
| `public-users.ts` | 公開ユーザー情報 `buildPublicUserData` |
| `spreadsheet.ts` | Googleスプレッドシート連携 |
| `errors.ts` | エラー定義 |
| `search-tokens.ts` | N-gram検索トークン生成 `generateNameTokens` |

---

## 🔄 修正パターン

### 新しいCallable関数を追加する場合

1. `callable/` に適切なファイルを選ぶ（または新規作成）
2. 関数を実装（`onCall` 使用）
3. `index.ts` でエクスポート追加
4. 認証チェック: `requireAuth(request)` または `requireAdmin(request)`
5. エラー: `config/messages.ts` の定数を使用

### 新しい定期実行を追加する場合

1. `scheduled/` に適切なファイルを選ぶ
2. `onSchedule` で実装
3. `index.ts` でエクスポート追加

### 新しいトリガーを追加する場合

1. `triggers/` に適切なファイルを選ぶ
2. `onDocumentCreated/Updated/Deleted` で実装
3. `index.ts` でエクスポート追加

### AIプロンプトを変更する場合

1. `ai/prompts/` の該当ファイルを編集
2. コメント生成: `comment.ts`
3. モデレーション: `moderation.ts`
4. 投稿生成: `post-generation.ts`

### エラーメッセージを追加する場合

1. `config/messages.ts` に定数を追加
2. 適切なカテゴリに配置（`AUTH_ERRORS`, `VALIDATION_ERRORS` など）

---

## 🔍 機能カテゴリ別 対応ファイル

| やりたいこと | 対応ファイル |
|-------------|-------------|
| ユーザー認証・権限 | `callable/admin.ts`, `helpers/admin.ts`, `helpers/auth.ts` |
| フォロー機能 | `callable/users.ts` |
| 投稿作成・モデレーション | `callable/posts.ts`, `helpers/moderation.ts` |
| コメント・リアクション | `callable/comments.ts`, `callable/rewarded_reactions.ts`, `triggers/notifications.ts` |
| サークル管理 | `callable/circles.ts`, `triggers/circles.ts` |
| サークルAI | `circle-ai/*.ts` |
| タスク管理 | `callable/tasks.ts`, `triggers/tasks.ts` |
| 目標リマインダー | `triggers/goals.ts`, `scheduled/reminders.ts` |
| 通報機能 | `callable/reports.ts` |
| 問い合わせ | `callable/inquiries.ts` |
| 通知・プッシュ | `triggers/notifications.ts`, `helpers/notification.ts` |
| AI生成（一般） | `callable/ai.ts`, `ai/provider.ts`, `http/ai-generation.ts` |
| AIプロンプト | `ai/prompts/*.ts` |
| 定期クリーンアップ | `scheduled/cleanup.ts` |
| エラーメッセージ | `config/messages.ts` |
| 徳ポイント | `callable/virtue_shop.ts`, `helpers/virtue.ts` |
| RevenueCat連携 | `http/revenuecat.ts` |

---

## ⚠️ 運用・操作用 関数の扱い方（2026-01-28）

以下は **運用・操作実行専用** の関数です。
現状は維持しますが、**今後も運用で使わないなら削除候補** とします。
- `cleanUpUserFollows`
- `cleanupOrphanedCircleAIs`
- `triggerCircleAIPosts`
- `triggerEvolveCircleAIs`
- `backfillPublicUsers`
- `backfillCircleNameTokens`

**権限付与** は将来の運用で必要になる可能性があるため **現状維持** とします。
- `setAdminRole`
- `removeAdminRole`

**タスク系 Callable**（`createTask`, `getTasks`）は、現状は維持しますが、
クライアント側のFirestore直接操作を維持する方針の場合は **将来削除候補** とします。

---

## 📝 注意事項

1. **リージョン**: 必ず `LOCATION` 定数を使用
2. **エラーメッセージ**: `config/messages.ts` の定数を使用
3. **管理者チェック**: `isAdmin()` または `requireAdmin()` を使用
4. **db取得**: `helpers/firebase.ts` からインポート
5. **新規エクスポート**: 必ず `index.ts` に追加

---

## 🛠️ scripts/

ローカル実行用スクリプト（デプロイ不要）

| ファイル | 用途 |
|---------|------|
| `backfill-email-verified.js` | 既存ユーザーのemailVerifiedを一括更新 |
| `backfill-circle-scheduling.js` | 既存サークルへ `nextGhostCheckAt` / `aiPostingEnabled` / `generatedAICount` / `nextCircleAIPostAt` / `isDeleted` を補完し、過去日時の AI due も将来へ再配置 |
| `backfill-public-users.js` | publicUsersコレクションの一括更新 |
| `check_admin_claims.js` | 管理者カスタムクレームの確認 |
| `migrate-name-parts-rarity.js` | 名前パーツのレアリティ移行 |
| `migrate_last_human_post.js` | lastHumanPostAtフィールドの移行 |
| `set_initial_admin.js` | 初期管理者の設定 |
| `set_initial_admin_cli.js` | 初期管理者の設定（CLI版） |
| `register-stamp-sheets.js` | スタンプシート台紙カタログを差分同期（削除は完全削除） |

## 追記: Stamp Sheet / Comment Thanks (2026-02-09)

### Callable
- `deleteComment`
  - 入力: `{ commentId }`
  - コメント主本人または管理者のみ実行可。コメント本体を削除し、`posts/{postId}.commentCount` を安全に減算。
- `adminDeleteCommentWithPenalty`
  - 入力: `{ commentId, targetUserId, reportIds }`
  - 管理者のみ実行可。通報対応としてコメントを削除し、対象ユーザーへ通知、徳ポイント減算、関連 `reports` を `resolved` 化。
- `likeCommentAsPostOwner`
  - 入力: `{ commentId }`
  - 投稿主のみ実行可。対象コメントに `thanksLikedByPostOwner=true` を設定し、投稿主の `thanksStampCredits` を `+1`。
- `setActiveStampSheet`
  - 入力: `{ sheetId }`
  - ユーザーの `activeStampSheetId` を更新。
- `applyStampToSheetSlot`
  - 入力: `{ sheetId, slotId, stampId }`
  - 空枠の初回押印のみ `thanksStampCredits` を `-1`。既存枠差し替えは消費なし。

## 追記: Post Create Retry Handling (2026-04-04)

### Callable
- `createPostWithModeration`
  - 入力: `{ content, userDisplayName, userAvatarIndex, postMode, circleId?, mediaItems?, clientRequestId? }`
  - `clientRequestId` を付けると、同一リクエストの再送時に二重投稿せず既存 `postId` を返す。
  - サーバー側は `users/{uid}/postRequests/{clientRequestId}` で `processing / succeeded / rejected` を保持し、曖昧失敗後の再送を吸収する。
  - terminal な失敗 (`invalid-argument` など) では、アップロード済みメディアと `pendingMedia` をサーバー側でも後始末する。
  - 画像付き投稿では、クライアント upload・サーバー側の画像モデレーション・Storage metadata 更新を可能な範囲で並列化し、待機時間を短縮している。

## 追記: Async Post Moderation Flow (2026-04-08)

### Callable / HTTP
- `createPostWithModeration`
  - 投稿を即時に `posts/{postId}` へ作成するが、初期状態は `moderationStatus=processing` / `isVisible=false`。
  - 投稿者本人にだけ見える pending 投稿として扱い、バックグラウンドで `executePostModeration` を予約する。
  - 再投稿で同じ `postId` を再利用する場合でも、各審査実行には `moderationAttemptId` を発行し、Cloud Tasks の重複 taskId と stale worker を避ける。
- `executePostModeration`
  - Cloud Tasks から呼ばれる投稿モデレーション worker。
  - テキスト/画像モデレーション結果に応じて、投稿を `approved / rejected / review_needed` へ遷移させる。
  - `rejected / review_needed` への遷移後も side effect 完了までは pending フラグを残し、retry 時に cleanup task / pendingReviews / 通知の欠落を回復する。
- `checkPostModerationTimeout`
  - `processing` のまま一定時間経過した投稿を `review_needed` へ切り替える fallback worker。
  - Cloud Tasks retry を使い切った後でも、owner-only 投稿が `processing` のまま固着しないようにする。
- `cleanupRejectedPost`
  - `rejected` 投稿を 24 時間後に削除する cleanup worker。
- `deleteRejectedPost`
  - 投稿者本人または管理者が、`rejected` 投稿を即時削除する callable。
  - 投稿ドキュメントだけでなく、未参照の Storage メディアも一緒に後始末する。
- `approveReviewedPost`
  - 管理者レビューで `review_needed` 投稿を公開側へ昇格させる。

### 投稿状態
- `processing`
  - 作成直後。投稿者本人にのみ表示。公開 TL には出ない。
- `approved`
  - 公開済み。通常の投稿として扱う。
- `rejected`
  - AI モデレーション NG。投稿者本人にのみ 24 時間表示し、その後 cleanup。
- `review_needed`
  - 自動判定保留。投稿者本人にのみ表示し、管理レビュー待ち。

### rejected / review_needed 時の扱い
- `rejected` / `review_needed` 投稿は `isVisible=false` のまま保持し、owner-only UI から確認する。
- `rejected` では `post_rejected` 通知を送信し、通知タップで該当投稿詳細へ遷移できる。
- 投稿詳細では NG 理由を確認し、そのまま編集・再投稿できる想定。
- `rejected` 投稿からの再投稿は、既存の `postId` を再利用して `processing` へ戻す。`createdAt` は更新され、差し替え前の未使用メディアは削除する。

### 関連データ
- `users/{uid}.thanksStampCredits`
- `users/{uid}.activeStampSheetId`
- `users/{uid}.unlockedStampSheets`
- `users/{uid}/stampSheet/{sheetId}_{slotId}`
- `comments/{commentId}.thanksLikedByPostOwner`
- `comments/{commentId}.thanksLikedAt`
- `comments/{commentId}.thanksLikedBy`

## 追記: AI / Cloud Tasks Logging Hygiene (2026-04-05)

- `http/ai-generation.ts`
  - AIコメント/投稿ワーカーのログは、本文やプロンプト全文ではなく `length + hash` ベースの要約ログを出す。
- `ai/provider.ts`
  - Gemini / OpenAI のレスポンスログは、本文そのものではなく `finishReason`, token usage, `contentSummary` のみを記録する。
- `helpers/cloud-tasks-auth.ts`
  - Cloud Tasks OIDC 検証ログは、JWT payload の `email` や `aud` 実値を出さず、存在有無と audience 一致有無のみを記録する。


