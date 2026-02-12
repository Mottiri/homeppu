# コメントお礼スタンプ + スタンプシート仕様（Phase 1）

最終更新: 2026-02-12
状態: 実装済み（運用中）

## 1. 目的
- タスク導線を段階的に縮小し、交流行動ベースの収集体験に置き換える。
- 投稿主が「良い返信コメント」にお礼を返し、コメント投稿者がスタンプシートで収集を楽しめる状態を作る。
- 徳ポイントとは切り離し、まずは回数ベースの収集体験を安定提供する。

## 2. Phase 1 スコープ
- 投稿主限定で、返信コメントに「お礼いいね」を付与できる。
- いいねされたコメント作成者に「スタンプ回数」を付与する。
- ボトムナビのタスクタブをスタンプシートタブへ差し替える。
- スタンプシート長押しでスタンプバーを開き、選択スタンプを配置する。
- スタンプのロック状態は既存リアクションスタンプと同期する。
- スタンプシート台紙はアセット管理で運用する。
- スタンプシート台紙にも `Common / Rare / Epic` のレア度を持たせる。
- デザイン一覧画面（`/stamps/catalog`）とアーカイブ画面（`/stamps/archives`）を提供する。

## 3. 非スコープ（Phase 1ではやらない）
- タスク関連データ/Functionsの物理削除（非表示のみ）。
- スタンプ回数の種類別管理。
- いいね取り消し機能。
- 徳ポイント連動報酬。

## 4. UX仕様
### 4.0 スタンプシート台紙（アセット + レア度）
- 台紙は画像アセットとして提供する（コード固定ではなくアセット差し替え可能）。
- 台紙は `Common / Rare / Epic` を持つ。
- ユーザーは解放済みの台紙のみ選択/使用できる。
- `Rare / Epic` の解放条件・課金導線は既存「リアクションスタンプ解放」の運用ルールに準拠する。

### 4.1 コメントお礼いいね（付与）
- 対象: 投稿主が、自分の投稿に付いた返信コメントに対して実行。
- 操作: 返信コメント長押しで「いいね候補UI」を表示し、候補タップで確定。
- 制約: 同一コメントへのいいねは1回のみ。
- 取り消し: 不可。

### 4.2 スタンプ回数（獲得）
- いいね確定時、コメント投稿者のスタンプ回数を `+1`。
- 回数は総数のみ管理（種類別カウントなし）。

### 4.3 スタンプシート（消費）
- シート長押しでスタンプバー表示。
- スタンプ選択で空き枠に左上から順に配置し、スタンプ回数 `-1`。
- 取り消し操作で最新の押印を1つ戻し、スタンプ回数 `+1`。

### 4.4 ロック同期
- シートで選べるスタンプは、既存リアクションスタンプの解放状態に完全同期。
- 未解放スタンプはシート上でも選択不可。
- 台紙（シート背景）の解放状態も同様にレア度管理対象とし、未解放台紙は選択不可。

### 4.5 台紙デザインと押下枠の同期方式（確定）
- 台紙画像と押下枠定義は分離し、同じ `sheetId` で紐付ける。
- 台紙画像: `assets/stamp_sheets/<sheetId>_<rarity>.png`
- レイアウト定義: `assets/stamp_sheets/layouts/<sheetId>.json`
- 枠座標は正規化座標（`x,y,w,h` を 0.0-1.0）で定義する。
- 描画時は画像の実表示領域（`BoxFit.contain` の余白を考慮）へ変換し、タップ判定とスタンプ描画に同じ変換を使う。
- 永続化キーは `sheetId + slotId`。同じ台紙で `slotId` は不変運用とする。
- 既存枠の座標修正は許可するが、`slotId` の再利用/付け替えは禁止（既存ユーザー配置保護）。
- 枠削除が必要な場合は、`isActive=false` で無効化し、既存データは維持する。

## 5. データ仕様（Phase 1）
## 5.1 ユーザー側
- `users/{uid}.thanksStampCredits: number`
  - お礼いいねで増える、シート配置で減る。

## 5.2 コメント側（重複防止）
- `comments/{commentId}.thanksLikedByPostOwner: boolean`
- `comments/{commentId}.thanksLikedAt: Timestamp|null`
- `comments/{commentId}.thanksLikedBy: string|null`

## 5.3 スタンプシート側
- `users/{uid}/stampSheet/{slotId}`
  - `slotId: string`
  - `stampId: string|null`
  - `updatedAt: Timestamp`
- `users/{uid}.activeStampSheetId: string|null`
  - 現在使用中の台紙ID。

## 5.4 スタンプシート台紙カタログ側
- `settings/stampSheetCatalog`
  - `sheets: Array<{ id, assetPath, rarity, displayOrder, isActive }>`
- `settings/stampSheetLayoutCatalog`
  - `layouts: Array<{ sheetId, layoutAssetPath, version, isActive }>`
  - 例: `layoutAssetPath = assets/stamp_sheets/layouts/<sheetId>.json`
- `settings/virtueShop.stampSheetCostsByRarity`
  - `Rare` 台紙の徳ポイント価格を管理（必要時）。
- `Epic` 台紙は既存サブスク条件と同期。

注意:
- 既存実装構造に合わせて最終フィールド名は実装時に微調整可。
- ただし「回数は総数のみ」は固定要件。

## 6. サーバー責務
- いいね確定はサーバーでトランザクション実行。
  - 同一コメント1回制限チェック。
  - `thanksStampCredits` 加算。
- シート同期は `syncStampSheetSnapshot` でスナップショット単位で検証。
  - `baseVersion` による競合検出。
  - 回数不足/解放状態/slot妥当性を検証。
- シート満了時の確定処理は `archiveAndStartNextStampSheet` で実行。
- アクティブシート切替は `setActiveStampSheet` で実行。

## 7. 画面/導線変更
- ボトムナビ:
  - タスクタブをスタンプシートタブへ差し替え。
- タスク:
  - Phase 1では非表示のみ。
  - DB/Functionsは残置。

## 8. 不正対策（Phase 1）
- 同一コメント1回制限。
- いいね取り消し不可（再付与防止）。
- 回数の増減はサーバーのみで確定。
- 台紙解放状態はサーバー管理値を正として判定。

## 9. 受け入れ基準
- 投稿主のみが返信コメントへお礼いいねできる。
- 同一コメントへの2回目いいねは不可。
- いいねされたコメント投稿者の回数が増える（現行はテスト運用で `+20`）。
- シート空き枠への配置で回数が1減る。
- 未解放スタンプはシートで選べない。
- タスクタブが表示されず、スタンプシートタブが表示される。

## 10. 実装時の注意
- UI文言は `lib/core/constants/app_messages.dart` に集約。
- クライアント楽観更新を使う場合も、最終確定はサーバー応答で同期。
- 既存徳ポイント/リアクション実装に影響する共有ロジックは回帰確認を行う。

---

## 2026-02-12 実装反映（Phase 1）

### 実装済み
- 投稿主がコメントに対して `いいね！` を 1 回だけ付与できる Callable を実装（`likeCommentAsPostOwner`）。
- `いいね！` 付与時に、コメント投稿者へ `thanksStampCredits` を加算するサーバー処理を実装。
- 注記: 現在値はテスト運用で一時的に `+20`（`functions/src/callable/comments.ts` の `THANKS_STAMP_CREDITS_PER_LIKE`）。
- スタンプシート同期 Callable を実装（`syncStampSheetSnapshot`）。
- アクティブシート切替 Callable を実装（`setActiveStampSheet`）。
- 満了アーカイブ + 次シート開始 Callable を実装（`archiveAndStartNextStampSheet`）。
- ボトムナビのタスク枠をスタンプシート画面に置換（`/stamps`）。
- スタンプシート画面を実装（台紙アセット + レイアウト JSON + シート長押しでスタンプ選択）。
- スタンプロック判定をリアクション解放状態と同期（free / rare(徳解放) / epic(サブスク)）。
- デザイン一覧画面（`/stamps/catalog`）を実装。
- アーカイブ画面（`/stamps/archives`）を実装。

### 追加した主なデータ項目
- `users/{uid}.thanksStampCredits`
- `users/{uid}.activeStampSheetId`
- `users/{uid}.unlockedStampSheets`
- `comments/{commentId}.thanksLikedByPostOwner`
- `comments/{commentId}.thanksLikedAt`
- `comments/{commentId}.thanksLikedBy`
- `users/{uid}/stampSheet/{sheetId}_{slotId}`

### 未完了（次フェーズ候補）
- スタンプシートカタログ運用（Firestore 設定・管理手順）の固定化。
- タスク機能の完全整理（非表示後の段階的廃止方針）。
