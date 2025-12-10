# AIコメント機能 設計仕様書

## 1. 機能概要
「ほめっぷ」のAIコメント機能は、ユーザーの投稿に対してAIキャラクター（ペルソナ）たちが自動で「褒める」コメントを返信する機能です。
ユーザー体験の向上（お化け通知の解消）のため、**Cloud Tasksを用いた遅延実行モデル** を採用しています。

### アーキテクチャ図
```mermaid
sequenceDiagram
    participant App as アプリ (Flutter)
    participant DB as Firestore (DB)
    participant Trigger as onPostCreated (Cloud Functions)
    participant Queue as Cloud Tasks (キュー)
    participant Worker as generateAICommentV1 (Cloud Functions)

    App->>DB: 1. 投稿を作成 (posts/{postId})
    DB->>Trigger: 2. トリガー起動
    Note over Trigger: 画像分析 & AIキャラ選定
    Trigger->>Queue: 3. タスクを予約 (○分後に実行)
    Note over Queue: 〜 指定時間まで待機 〜
    Queue->>Worker: 4. 実行リクエスト (HTTP)
    Note over Worker: Geminiでコメント生成
    Worker->>DB: 5. コメント保存 (comments/{commentId})
    DB->>App: 6. ユーザーに通知 & 表示
```

---

## 2. 詳細仕様

### A. トリガー関数 (`onPostCreated`)
- **トリガー**: Firestore `posts/{postId}` の作成時
- **ランタイム**: Cloud Functions v2
- **実行権限**: `cloud-tasks-sa` サービスアカウントを使用
- **処理内容**:
  1. `postMode` が "human" の場合はスキップ。
  2. 投稿内のメディア（画像・動画）がある場合、Geminiで内容をテキスト化（キャプション生成）。
  3. ランダムにAIペルソナを選出（3〜10人）。
  4. 各ペルソナについて、**Cloud Tasks** にタスクを追加（Enqueue）。
     - 実行時刻(`scheduleTime`)を現在時刻から **1分〜10分後**（ランダム/テスト設定）に設定。

### B. コメント生成関数 (`generateAICommentV1`)
- **トリガー**: Cloud Tasks からのHTTPリクエスト
- **ランタイム**: Cloud Functions v1 (URL固定化のため)
- **URL形式**: `https://asia-northeast1-<projectId>.cloudfunctions.net/generateAICommentV1`
- **処理内容**:
  1. リクエストボディから `postId`, `mediaDescriptions`, `persona` 等を受け取る。
  2. Gemini APIを使用し、ペルソナの口調に合わせたコメントを生成。
  3. 生成されたテキストを `posts/{postId}/comments` コレクションに保存。
  4. 保存トリガーにより、別途プッシュ通知が送信される。

---

## 3. インフラ設定要件

本機能を動作させるためには、Google Cloud プロジェクト側で以下のリソース設定が必要です。

### プロジェクト情報
- **Project ID**: `positive-sns`
- **Region**: `asia-northeast1` (Tokyo)

### Cloud Tasks
- **キュー名**: `generateAIComment`
- **設定**:
  - Max dispatches per second: 500 (Default)
  - Max concurrent dispatches: 1000 (Default)

### IAM (Service Account)
- **Service Account**: `cloud-tasks-sa@positive-sns.iam.gserviceaccount.com`
- **必要なロール**:
  - **Cloud Tasks Enqueuer** (Cloud Tasks タスク追加ユーザー)
  - **Cloud Functions Invoker** (Cloud Functions 起動元)
  - **Service Account User** (サービス アカウント ユーザー)
  - **Editor** (編集者) ※Firestore読み書き用
- **特記事項**: `ActAs` 権限のため、デプロイ実行ユーザー（開発者）にもこのSAに対する「サービス アカウント ユーザー」権限が必要。

---

## 4. 運用・保守
- **ログ確認**: Cloud Functions のログだけでなく、Cloud Tasks コンソールでタスクの実行履歴（成功/失敗/リトライ）を確認可能。
- **リトライポリシー**: Cloud Tasks のデフォルト設定により、関数がエラー（500系）を返した場合は自動リトライが行われる。
