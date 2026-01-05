# 投稿機能設計書 (Post Feature Design)

## 1. 概要 (Overview)

「ほめっぷ」のコア機能である投稿機能の設計仕様書です。
本アプリは**「世界一優しいSNS」**をコンセプトとしており、投稿機能においても**徹底したポジティブ維持（ネガティブ排除）**と**AIによる即時フィードバック**を最優先事項として設計されています。

## 2. コンセプトと方針 (Concept & Policy)

### 2.1 ポジティブ・ファースト
- **基本方針**: ユーザーが安心して利用できるよう、攻撃的・暴力的・過度にネガティブな発言をシステムレベルで排除します。
- **Fail-Open（テキスト）**: AIモデレーションでエラーが発生した場合、テキスト投稿は**「許可」**します（UX優先）。
- **Fail-Closed（メディア）**: 画像/動画のモデレーションでエラーが発生した場合、メディアのアップロードは**「拒否」**します（安全性優先）。

### 2.2 投稿モード
ユーザーは投稿時に以下のモードを選択します。
- **AIモード**: AIキャラクターのみが反応するモード。
- **mixモード**: AIと人間両方が反応できるモード。
- **人間モード**: 人間のみが反応できるモード。

---

## 3. アーキテクチャ (Architecture)

### 3.1 投稿作成フロー
セキュリティとモデレーションを強制するため、クライアントからFirestoreへの直接書き込みを禁止し、**Cloud Functions (`onCall`) 経由でのみ**作成可能です。

1. **Client**: `ModerationService` が `createPostWithModeration` を呼び出す。
2. **Cloud Functions (`createPostWithModeration`)**:
    - **Step 1: 認証 & BANチェック**: 未ログインまたはBAN中ユーザーは拒否。
    - **Step 2: 静的NGワードチェック**: `NG_WORDS` に一致した場合、即時エラー（`invalid-argument`）& 徳ポイント減少。
    - **Step 3: AIテキストモデレーション**: Gemini 2.0 Flash で `isNegative` 判定。
        - `isNegative: true` (confidence >= 0.7) → エラー返却 & 徳ポイント減少。
        - `0.5 <= confidence < 0.7` → `needsReview` フラグを立てて投稿許可（管理者へ通知）。
    - **Step 4: メディアモデレーション** (ある場合): Geminiで画像/動画を分析。
        - 不適切判定 → Storageからファイルを削除しエラー返却 & 徳ポイント減少。
    - **Step 5: レートリミット**: 1分間に5投稿まで。
    - **Step 6: Firestore書き込み**: `posts` コレクションに作成。
    - **Step 7: メタデータ更新**: Storage上のメディアファイルのmetadataに `postId` を紐付け。

3. **Firestore Trigger (`onPostCreated`)**: `posts/{postId}` 作成を検知。
    - **AIコメント生成**:
        - 人間モード以外の場合、AIキャラクターを選定。
        - サークル投稿の場合はサークル設定（`generatedAIs`）に従う。
        - Cloud Tasks に生成タスクを積む（`generateAICommentV1` / `generateAIReactionV1`）。

### 3.2 投稿削除フロー
クライアントまたは管理者による削除操作は、Firestoreドキュメントの削除によって行われます。関連データはサーバーサイドでカスケード削除されます。

1. **Client**: `PostService.deletePost` (または管理者画面) から `posts/{postId}` を削除。
2. **Firestore Trigger (`onPostDeleted`)**:
    - **コメント削除**: `comments` コレクションから該当 `postId` を一括削除。
    - **リアクション削除**: `reactions` コレクションから該当 `postId` を一括削除。
    - **通知削除**: **投稿者本人**の `notifications` コレクションから該当 `postId` の通知を一括削除。
        - *Note: 第三者への通知削除は未実装（現状仕様では通知送付先が投稿者のみのため問題なし）。*
    - **Storage削除**: 投稿に含まれる画像/動画（サムネイル含む）をStorageから削除。
    - **カウント更新**: ユーザー (`totalPosts`) およびサークル (`postCount`) の投稿数を減算。

---

## 4. モデレーション詳細 (Moderation Logic)

### 4.1 静的NGワードチェック
- **対象**: `kill`, `die`, `violence` などの直球な暴言。
- **動作**: 検出時即ブロック。AI呼び出しコストを節約。

### 4.2 AIモデレーション (Gemini)
- **判定カテゴリ**:
    - `harassment` (嫌がらせ), `hate_speech` (ヘイト), `profanity` (暴言), `violence` (暴力), `self_harm` (自傷), `spam` (スパム)。
- **判定基準**:
    - **Reject**: `isNegative: true` AND `confidence >= 0.7`
    - **Flag (要審査)**: `isNegative: true` AND `0.5 <= confidence < 0.7`
        - 投稿は表示されるが、管理者に「要審査」通知が飛ぶ。
    - **Accept**: 上記以外。

### 4.3 徳ポイント (Virtue Points)
- **NGワード**: -30 pt
- **AIブロック**: -15 pt
- **通報による非表示**: -20 pt (※要管理者確認)

---

## 5. 通知機能連携 (Notifications)

投稿に関連するアクションは以下の通り通知されます。

### 5.1 コメント通知 (`onCommentCreatedNotify`)
- **トリガー**: `comments/{commentId}` 作成。
- **通知先**: **投稿者の** (`post.userId`)。
    - 自分自身のコメントは通知しない。
    - 第三者（コメント参加者）への通知機能は現在ありません。
- **FCM**: プッシュ通知を送信。

### 5.2 リアクション通知 (`onReactionAddedNotify`)
- **トリガー**: `reactions/{reactionId}` 作成。
- **通知先**: **投稿者の** (`post.userId`)。
    - 自分自身のリアクションは通知しない。
- **FCM**: プッシュ通知を送信。

---

## 6. データモデル (Data Model: Reference)

### PostModel (`posts`)
```typescript
interface Post {
  id: string;
  userId: string;
  userDisplayName: string;
  userAvatarIndex: number; // 0-20
  content: string;
  mediaItems: MediaItem[]; // { url, type, thumbnailUrl, ... }
  postMode: 'ai' | 'mix' | 'human';
  circleId?: string; // サークル投稿の場合
  createdAt: Timestamp;
  isVisible: boolean; // falseの場合論理削除/非表示
  commentCount: number;
  reactions: {
    love: number;
    praise: number;
    cheer: number;
    empathy: number;
    [key: string]: number;
  };
  // モデレーション用
  needsReview?: boolean;
  needsReviewReason?: string;
  hiddenAt?: Timestamp; // 通報等による非表示日時
}
```

### CommentModel (`comments`)
```typescript
interface Comment {
  id: string;
  postId: string;
  userId: string; // AIの場合はAI ID
  userDisplayName: string;
  content: string;
  isAI: boolean;
  createdAt: Timestamp;
  // ...
}
```
