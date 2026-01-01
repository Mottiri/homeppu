# Cloud Functions リファレンス

**最終更新**: 2026-01-01  
**総関数数**: 48個

---

## 1. 投稿・コンテンツ管理

| 関数名 | タイプ | 説明 |
|--------|--------|------|
| `onPostCreated` | Firestore Trigger | 投稿作成時にAIコメント生成をトリガー |
| `createPostWithModeration` | Callable | テキスト・メディアのモデレーション付き投稿作成 |
| `createPostWithRateLimit` | Callable | レート制限付き投稿作成 |
| `moderateImageCallable` | Callable | クライアントから画像モデレーションを呼び出し |
| `reportContent` | Callable | 投稿・コメント・ユーザーの通報処理 |

---

## 2. AIアカウント管理

| 関数名 | タイプ | 説明 |
|--------|--------|------|
| `initializeAIAccounts` | Callable | AIアカウントの初期セットアップ（管理用） |
| `generateAIPosts` | Callable | AIによる自動投稿生成（手動トリガー） |
| `scheduleAIPosts` | Scheduled | 毎日10時に5人のAIを選択して自動投稿スケジュール |
| `deleteAllAIUsers` | Callable | 全AIユーザーを削除（管理用・危険） |

---

## 3. AIコメント・リアクション

| 関数名 | タイプ | 説明 |
|--------|--------|------|
| `generateAICommentV1` | HTTP | Cloud Tasksから呼び出されるAIコメント生成 |
| `createCommentWithModeration` | Callable | モデレーション付きコメント作成 |
| `onCommentCreatedNotify` | Firestore Trigger | コメント作成時にプッシュ通知送信 |
| `addUserReaction` | Callable | ユーザーリアクションの追加・更新 |
| `generateAIReactionV1` | HTTP | Cloud Tasksから呼び出されるAIリアクション生成 |
| `onReactionAddedNotify` | Firestore Trigger | リアクション追加時にプッシュ通知送信 |
| `onReactionCreated` | Firestore Trigger | リアクション作成時の集計・処理 |

---

## 4. サークル管理

| 関数名 | タイプ | 説明 |
|--------|--------|------|
| `onCircleCreated` | Firestore Trigger | サークル作成時にAIメンバーを自動追加 |
| `onCircleUpdated` | Firestore Trigger | サークル更新時の関連処理 |
| `deleteCircle` | Callable | サークルのソフトデリート |
| `cleanupDeletedCircle` | HTTP | 削除済みサークルのデータクリーンアップ（バックグラウンド） |
| `approveJoinRequest` | Callable | サークル参加申請の承認 |
| `rejectJoinRequest` | Callable | サークル参加申請の拒否 |
| `sendJoinRequest` | Callable | サークル参加申請の送信 |

---

## 5. サークルAI投稿

| 関数名 | タイプ | 説明 |
|--------|--------|------|
| `generateCircleAIPosts` | Scheduled | 毎日サークルAI投稿をスケジュール |
| `executeCircleAIPost` | HTTP | Cloud Tasksから呼び出されるAI投稿実行 |
| `triggerCircleAIPosts` | Callable | サークルAI投稿の手動トリガー（テスト用） |
| `evolveCircleAIs` | Scheduled | サークルAIのレベルアップ処理（毎月1日） |
| `triggerEvolveCircleAIs` | Callable | サークルAI進化の手動トリガー |
| `cleanupOrphanedCircleAIs` | Callable | 孤立したサークルAIのクリーンアップ |

---

## 6. ユーザー・フォロー

| 関数名 | タイプ | 説明 |
|--------|--------|------|
| `followUser` | Callable | ユーザーをフォロー |
| `unfollowUser` | Callable | フォロー解除 |
| `getFollowStatus` | Callable | フォロー状態を取得 |
| `cleanUpUserFollows` | Firestore Trigger | ユーザー削除時のフォロー関連クリーンアップ |

---

## 7. 徳（Virtue）システム

| 関数名 | タイプ | 説明 |
|--------|--------|------|
| `getVirtueHistory` | Callable | 徳ポイントの履歴取得 |
| `getVirtueStatus` | Callable | 現在の徳ポイント状態取得 |

---

## 8. タスク・リマインダー

| 関数名 | タイプ | 説明 |
|--------|--------|------|
| `createTask` | Callable | タスク作成 |
| `getTasks` | Callable | タスク一覧取得 |
| `onTaskUpdated` | Firestore Trigger | タスク更新時の処理 |
| `scheduleTaskReminders` | Firestore Trigger | タスク更新時にリマインダーを再スケジュール |
| `scheduleTaskRemindersOnCreate` | Firestore Trigger | タスク作成時にリマインダーをスケジュール |
| `executeTaskReminder` | HTTP | Cloud Tasksから呼び出されるリマインダー通知実行 |

---

## 9. 名前パーツ（アバター名生成）

| 関数名 | タイプ | 説明 |
|--------|--------|------|
| `initializeNameParts` | Callable | 名前パーツの初期データ投入（管理用） |
| `getNameParts` | Callable | 利用可能な名前パーツを取得 |
| `updateUserName` | Callable | ユーザー名を更新 |

---

## 10. AI投稿実行（汎用）

| 関数名 | タイプ | 説明 |
|--------|--------|------|
| `executeAIPostGeneration` | HTTP | Cloud Tasksから呼び出されるAI投稿生成 |

---

## 11. メンテナンス・クリーンアップ

| 関数名 | タイプ | 説明 |
|--------|--------|------|
| `cleanupOrphanedMedia` | Scheduled | 毎日3時に孤立メディア・データをクリーンアップ |
| `cleanupReports` | Scheduled | 毎日0時に1ヶ月以上前の解決済み通報を自動削除 |
| `onPostDeleted` | Firestore Trigger | 投稿削除時にコメント・リアクション・通知・メディアをカスケード削除 |

---

## 12. プッシュ通知自動化

| 関数名 | タイプ | 説明 |
|--------|--------|------|
| `onNotificationCreated` | Firestore Trigger | 通知ドキュメント作成時に自動でFCMプッシュ通知を送信 |

---

## トリガータイプ一覧

| タイプ | 説明 | 関数数 |
|--------|------|--------|
| **Callable** | クライアントから直接呼び出し | 21 |
| **Firestore Trigger** | Firestoreドキュメント変更時に発火 | 12 |
| **HTTP** | HTTPリクエストで呼び出し（Cloud Tasks用） | 9 |
| **Scheduled** | Cloud Schedulerで定期実行 | 5 |

---

## 使用キュー（Cloud Tasks）

| キュー名 | 用途 |
|---------|------|
| `generateAIComment` | AIコメント・リアクション生成 |
| `task-reminders` | タスクリマインダー通知 |
| `circleAIPost` | サークルAI投稿生成 |
