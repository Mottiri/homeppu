# Cloud Functions リファレンス

AI支援開発用のクイックリファレンス。機能改修・追加時にこのドキュメントを参照してください。

---

## 📁 ディレクトリ構成

```
functions/src/
├── index.ts           # エントリーポイント（再エクスポート）
├── config/            # 設定・定数
├── callable/          # ユーザー呼び出し関数
├── scheduled/         # 定期実行関数
├── triggers/          # Firestoreトリガー
├── circle-ai/         # サークルAI専用
├── ai/                # AI関連（プロンプト・プロバイダー）
├── helpers/           # ヘルパー関数
└── types/             # 型定義
```

---

## 🎯 機能別ファイル一覧

### callable/ - ユーザー呼び出し関数

| ファイル | 機能 | 主な関数 |
|---------|------|---------|
| `admin.ts` | 管理者機能 | `setAdminRole`, `removeAdminRole`, `banUser`, `permanentBanUser`, `unbanUser`, `deleteAllAIUsers`, `cleanupOrphanedCircleAIs` |
| `users.ts` | ユーザー機能 | `followUser`, `unfollowUser`, `getFollowStatus`, `getVirtueHistory`, `getVirtueStatus` |
| `posts.ts` | 投稿作成 | `createPostWithRateLimit`, `createPostWithModeration` |
| `circles.ts` | サークル管理 | `deleteCircle`, `approveJoinRequest`, `rejectJoinRequest`, `sendJoinRequest` |
| `tasks.ts` | タスク管理 | `createTask`, `getTasks` |
| `reports.ts` | 通報機能 | `reportContent` |
| `names.ts` | 名前管理 | `initializeNameParts`, `getNameParts`, `updateUserName` |
| `inquiries.ts` | 問い合わせ | `createInquiry`, `sendInquiryMessage`, `sendInquiryReply`, `updateInquiryStatus` |
| `ai.ts` | AI管理 | `initializeAIAccounts`, `generateAIPosts` |

### scheduled/ - 定期実行関数

| ファイル | 機能 | スケジュール |
|---------|------|-------------|
| `circles.ts` | サークル管理 | ゴースト検出（毎日3:30）、AI成長（毎月1日） |
| `cleanup.ts` | クリーンアップ | 孤立メディア・問い合わせ・レポート削除（毎日深夜） |
| `ai-posts.ts` | AI投稿 | AI自動投稿スケジュール |

### triggers/ - Firestoreトリガー

| ファイル | 機能 | トリガー対象 |
|---------|------|-------------|
| `circles.ts` | サークル | 作成時AI生成、更新時メンバー通知 |
| `posts.ts` | 投稿 | 作成時AIコメントスケジュール |
| `notifications.ts` | 通知 | 通知ドキュメント作成時の自動プッシュ送信 + コメント/リアクション通知作成 |
| `tasks.ts` | タスク | 更新時リマインダースケジュール |

補足（2026-01-25）:
- `users/{userId}/notifications/{notificationId}` の作成で `onNotificationCreated` が自動でFCM送信
- `pushPolicy: never` を通知ドキュメントに持たせると「通知は作るがpushは送らない」

### circle-ai/ - サークルAI専用

| ファイル | 機能 |
|---------|------|
| `posts.ts` | サークルAI投稿生成・実行 |
| `generator.ts` | サークルAIペルソナ生成 |

### ai/ - AI関連

| ファイル | 機能 |
|---------|------|
| `provider.ts` | AIプロバイダーファクトリー（Gemini/OpenAI） |
| `personas.ts` | AIペルソナ定義・システムプロンプト |
| `prompts/comment.ts` | コメント生成プロンプト |
| `prompts/moderation.ts` | モデレーションプロンプト |
| `prompts/post-generation.ts` | 投稿生成プロンプト |
| `prompts/bio-generation.ts` | bio生成プロンプト |

### config/ - 設定

| ファイル | 内容 |
|---------|------|
| `constants.ts` | `LOCATION`, `PROJECT_ID`, `AI_MODELS` |
| `messages.ts` | エラーメッセージ・通知タイトル・ラベル定数 |
| `secrets.ts` | APIキー参照 |

### helpers/ - ヘルパー

| ファイル | 機能 |
|---------|------|
| `firebase.ts` | Firestore初期化・db参照 |
| `admin.ts` | 管理者判定 `isAdmin()` |
| `virtue.ts` | 徳ポイント計算 |
| `notification.ts` | プッシュ通知送信 |
| `storage.ts` | Storageファイル削除 |
| `moderation.ts` | メディアモデレーション |
| `cloud-tasks-auth.ts` | Cloud Tasks認証 |

---

## 🔧 改修パターン

### 新しいCallable関数を追加する場合

1. `callable/` に適切なファイルを選ぶ（または新規作成）
2. 関数を実装（`onCall` 使用）
3. `index.ts` でエクスポート追加
4. 認証チェック: `AUTH_ERRORS.UNAUTHENTICATED`
5. 権限チェック: `AUTH_ERRORS.ADMIN_REQUIRED`

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

## 📋 機能カテゴリ別 対応ファイル

| やりたいこと | 対応ファイル |
|-------------|-------------|
| ユーザー認証・権限 | `callable/admin.ts`, `helpers/admin.ts` |
| フォロー機能 | `callable/users.ts` |
| 投稿作成・モデレーション | `callable/posts.ts`, `helpers/moderation.ts` |
| サークル管理 | `callable/circles.ts`, `triggers/circles.ts` |
| サークルAI | `circle-ai/*.ts` |
| タスク管理 | `callable/tasks.ts`, `triggers/tasks.ts` |
| 通報機能 | `callable/reports.ts` |
| 問い合わせ | `callable/inquiries.ts` |
| 通知・プッシュ | `triggers/notifications.ts`, `helpers/notification.ts` |
| AI生成（全般） | `callable/ai.ts`, `ai/provider.ts` |
| AIプロンプト | `ai/prompts/*.ts` |
| 定期クリーンアップ | `scheduled/cleanup.ts` |
| エラーメッセージ | `config/messages.ts` |

---

## ⚠️ 注意事項

1. **リージョン**: 必ず `LOCATION` 定数を使用
2. **エラーメッセージ**: `config/messages.ts` の定数を使用
3. **管理者チェック**: `isAdmin()` を使用
4. **db参照**: `helpers/firebase.ts` からインポート
5. **新規エクスポート**: 必ず `index.ts` に追加
