# スタンプシート 現行方針・引き継ぎメモ（2026-02-12）

この資料は、スタンプシート機能の現在方針と実装上の重要点を、他AI/他担当へ引き継ぐためにまとめたものです。

## 1. 現在の仕様（確定）

- スタンプ画面は **常に1枚の「現在シート」** のみ表示する。
- コメントへの投稿主限定「いいね！」で `thanksStampCredits` が増える。
- スタンプ押下で `thanksStampCredits` を1消費する。
- 取り消しで `thanksStampCredits` を1回復する。
- スタンプはシート上で左上から空き枠順に押される（ユーザーが枠を個別選択しない）。
- シート満了時:
  - 紙吹雪演出を出す
  - 次シート選択ダイアログを表示
  - 選択後、満了シートをアーカイブして次シートを現在シートにする
- 初回表示時:
  - まだアクティブシート未設定なら、最初のシート選択ダイアログを表示
- シート一覧画面は別画面（`/stamps/catalog`）で「デザイン閲覧 + 購入導線」を提供する。
- アーカイブ一覧は別画面（`/stamps/archives`）で 3x3 グリッド + ページネーション表示を行う。
- 旧ページネーション方式は廃止方針。

## 2. 解放/購入ルール

- Common: 常時利用可
- Rare: 購入済みのみ利用可
- Epic: サブスク中のみ利用可
- シート解放状態とリアクションスタンプ解放状態はそれぞれサーバー情報を参照する。

## 3. 主要データ

- `users/{uid}`
  - `thanksStampCredits`
  - `stampSheetVersion`
  - `activeStampSheetId`
  - `unlockedStampSheets`
  - `unlockedReactionStamps`
  - `isSubscriber`
- `users/{uid}/stampSheet`
  - 現在シートの配置（slotIdごと）
- `users/{uid}/stampSheetArchives`
  - 満了済みシートのスナップショット
- `settings/stampSheetCatalog`
- `settings/stampSheetLayoutCatalog`
- `settings/virtueShop`
- Firestore Rules:
  - `users/{uid}/stampSheetArchives/{archiveId}` はオーナー read のみ許可（write 不可）

## 4. 楽観UI整合の仕組み（重要）

### クライアント側

- メモリ上のランタイム状態を `userId` 単位で保持する（static cache）。
- 押下/取り消しは即時でローカル状態へ反映する（体感速度優先）。
- 同時に `isDirty=true` と `mutationSeq++` を立てる。
- 送信はデバウンス（約600ms）でまとめる。
- 画面離脱やアプリバックグラウンド時にも送信を試行する。

### サーバー側

- 同期は `syncStampSheetSnapshot` で **スナップショット丸ごと** を受け取る。
- `baseVersion`（= `users/{uid}.stampSheetVersion`）でCAS制御し、競合を検出する。
- 受信時に次を再検証する:
  - シート解放状態
  - スタンプ解放状態
  - スロット妥当性
  - クレジット不足の有無
- 検証通過時のみサーバー状態を更新し、`stampSheetVersion` をインクリメントする。

### 満了時

- クライアントはまず現在状態を同期してから `archiveAndStartNextStampSheet` を呼ぶ。
- サーバーで「本当に満了か」を再検証し、満了でなければ拒否する。
- 成功時:
  - `stampSheetArchives` に退避
  - `stampSheet` をクリア
  - `activeStampSheetId` を次シートへ更新

## 5. ダイアログ復元（重要）

- 初回シート未選択の状態は端末にフラグ保存し、次回起動でも再表示する。
- 満了後の次シート選択中にアプリ終了しても、次回起動時に再表示する。
- 保存キーはユーザー単位（ログインユーザー切替時の混線を防止）。

## 6. Functions/デプロイ運用

- 旧Callable `applyStampToSheetSlot` / `undoLatestStamp` は廃止済み方針。
- 現在の主利用Callable:
  - `syncStampSheetSnapshot`
  - `archiveAndStartNextStampSheet`
  - `setActiveStampSheet`
  - `likeCommentAsPostOwner`
  - `getVirtueShopConfig`
  - `purchaseVirtueItem`

### デプロイ時の注意

- `firebase deploy` 前に必ず `functions` で `npm run build` を実行する。
- `build` なしだと、新規エクスポート関数が「存在しない」扱いになることがある。

## 7. 既知の注意点

- 超高速な連打 + 画面遷移連打では、同期タイミングによって一時的な見え方差分が発生しうる。
- 最終正はサーバー状態。再表示・再同期で収束する前提。
- 体感優先のため、押下/取り消し時に都度サーバー往復はしない設計。

## 8. テスト観点（最小）

- 新規ユーザー:
  - 初回シート選択が出る
  - 押下/取り消しでクレジットが即時変化
- 満了:
  - 紙吹雪が出る
  - 次シート選択ダイアログが出る
  - 選択後に新シートで再開できる
- 復元:
  - ダイアログ表示中にアプリ終了して再表示される
- 購入:
  - rare/epic台紙の購入導線が機能する
- 画面導線:
  - スタンプ画面AppBarのデザイン一覧アイコンで `/stamps/catalog` へ遷移できる
  - スタンプ画面AppBarのアーカイブアイコンで `/stamps/archives` へ遷移できる
- アーカイブ:
  - 複数件時にページネーション（ドット）が表示される
  - 各カードで完成日（日付）が表示される

## 9. 次担当へのチェック項目

- `stamp_sheet_screen.dart` で旧ページネーション前提のロジックが再流入していないか
- `stamp_sheet_catalog_screen.dart` / `stamp_sheet_archives_screen.dart` のルーティングが `app_router.dart` と一致しているか
- `functions/src/index.ts` で旧Callable export が復活していないか
- 価格/文言の変更時:
  - Flutter表示文言は `lib/core/constants/app_messages.dart`
  - Functions返却文言は `functions/src/config/messages.ts`
