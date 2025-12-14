# 投稿機能設計書 (Post Feature Design)

## 1. 概要 (Overview)

「ほめっぷ」のコア機能である投稿機能の設計仕様です。
本アプリは**「世界一優しいSNS」**をコンセプトとしており、投稿機能においても**徹底したポジティブ維持（ネガティブ排除）**を最優先事項として設計されています。

## 2. コンセプトと方針 (Concept & Policy)

### 2.1 ポジティブ・ファースト
- **基本方針**: ユーザーが安心して利用できるよう、攻撃的・暴力的・過度にネガティブな発言をシステムレベルで排除します。
- **Fail-Closed（安全側への倒し方）**: モデレーションシステムが停止している場合やエラーが発生した場合、**「投稿を許可しない（ブロックする）」**という安全策を取ります。

### 2.2 投稿モード
ユーザーは投稿時に以下のモードを選択できます（現在の実装ではユーザー設定に依存）。
- **AIモード**: AIキャラクターのみが反応するモード。
- **mixモード**: AIと人間両方が反応できるモード。
- **人間モード**: 人間のみが反応できるモード。

---

## 3. アーキテクチャ (Architecture)

### 3.1 投稿フロー
セキュリティとモデレーションを強制するため、**クライアントからFirestoreへの直接書き込みを禁止**しています。

1. **Client**: `createPostWithModeration` (Cloud Functions) を呼び出す。
2. **Cloud Functions**:
    - **Step 0**: 静的NGワードチェック（即時ブロック）
    - **Step 1**: AIテキストモデレーション（Gemini）
    - **Step 2**: メディアモデレーション（画像/動画の解析）
    - **Step 3**: レートリミットチェック（連投防止）
    - **Step 4**: Firestoreへの書き込み (`posts` コレクション)
3. **Firestore**: 投稿データが作成される。
4. **Trigger**: `onPostCreated` が発火し、AIによるリアクション/コメント生成プロセスが開始される。

### 3.2 セキュリティルール (`firestore.rules`)
```javascript
match /posts/{postId} {
  // 作成: クライアントからの直接作成を禁止（Cloud Functions経由のみ）
  allow create: if false;
  
  // 読み取り: 認証済みユーザーのみ
  allow read: if isAuthenticated();
}
```

---

## 4. モデレーション詳細 (Moderation Logic)

### 4.1 静的NGワードチェック (Static Check)
AI判定の前に、絶対禁止ワード（`NG_WORDS`）によるフィルタリングを行います。
- **対象**: 「死ね」「殺す」「自殺」などの暴力・自傷関連用語。
- **動作**: 検出された場合、AIを呼び出さずに**即座にエラー (`invalid-argument`)** を返し、徳ポイントを大幅に減点します。

### 4.2 AIモデレーション (Gemini Analysis)
Google Geminiモデルを使用し、文脈を含めた判定を行います。
- **判定カテゴリ**:
    - `harassment`: 誹謗中傷
    - `hate_speech`: 差別
    - `profanity`: 暴言（汚い言葉）
    - `violence`: 暴力・脅迫
    - `self_harm`: 自傷行為
- **Fail-Closed**: APIキー未設定やAIサーバーエラー時は `internal` エラーをスローし、投稿をブロックします。

### 4.3 徳ポイント (Virtue Points)
不適切な投稿を試みた場合、ユーザーの「徳」が下がります。
- **NGワード使用**: 大幅減点
- **AI判定によるブロック**: 中規模減点

---

## 5. データモデル (Data Model)

### PostModel (`posts` collection)

| Field | Type | Description |
|---|---|---|
| `id` | String | ドキュメントID |
| `userId` | String | 投稿者ID |
| `userDisplayName` | String | 投稿者名（スナップショット） |
| `userAvatarIndex` | int | アイコンID |
| `content` | String | 投稿本文 |
| `mediaItems` | List<Map> | 添付メディア（画像/動画） |
| `postMode` | String | `'ai'` \| `'mix'` \| `'human'` |
| `circleId` | String? | サークル投稿の場合のサークルID |
| `createdAt` | Timestamp | 作成日時 |
| `isVisible` | bool | 表示フラグ（論理削除用） |
| `reactions` | Map | リアクション集計 `{'love': 0, 'praise': 0...}` |
| `commentCount` | int | コメント数 |

### MediaItem Structure
```dart
{
  'url': String,      // Storage URL
  'type': String,     // 'image' | 'video' | 'file'
  'fileName': String?,
  'mimeType': String?,
  'fileSize': int?
}
```

---

## 6. クライアント実装 (Client Implementation)

### 6.1 `CreatePostScreen`
- **入力**: テキスト (`TextField`), メディア選択 (`MediaService`).
- **送信**: `ModerationService.createPostWithModeration` を呼び出し。
- **エラーハンドリング**:
    - `ModerationException` を捕捉し、AIからの「優しいフィードバック（理由）」をダイアログで表示。
    - 徳ポイント減少を即時にUIに反映（`ref.invalidate`）。

### 6.2 表示 (`PostCard`)
- 投稿モードに応じたバッジ表示。
- リアクションボタン押下時のアニメーション。
- メディアのプレビュー表示。

