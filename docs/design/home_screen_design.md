# ホーム画面設計書

## 1. 概要
ユーザーがタイムラインを閲覧するメイン画面。「おすすめ」タブと「フォロー中」タブで投稿を表示。

## 2. 画面構成 (UI Layout)

### 2.1 ヘッダー
*   **ロゴ**: 中央に72px表示、シマー効果アニメーション付き
*   **通知アイコン**: 右端に配置、未読数バッジ付き

### 2.2 タブバー
*   **おすすめ**: サークル投稿を除外した全体のタイムライン
*   **フォロー中**: フォロー中ユーザーの投稿のみ
*   `pinned: false` - スクロールで非表示

### 2.3 投稿リスト
*   プル更新対応
*   無限スクロール対応（30件ずつ読み込み）
*   `PostCard`ウィジェットで表示

## 3. 機能仕様 (Functionality)

### 3.1 背景グラデーション (2026-01-06 追加)
*   ユーザーの`headerPrimaryColor`と`headerSecondaryColor`から動的にグラデーション生成
*   パステルカラー（透明度25%と15%）で上から下へ
*   下部は`warmGradient`の上部色（#FDF8F3）へフェード

### 3.2 スクロールトップ機能 (2026-01-06 追加)
*   ボトムナビのホームボタンタップ時、既にホーム画面の場合はスクロールトップ
*   `homeScrollToTopProvider`でトリガー
*   スムーズアニメーション（300ms, easeOut）

### 3.3 タイムラインリフレッシュ
*   投稿作成後は`timelineRefreshProvider`をインクリメントしてリロード

## 4. 関連ファイル
*   `lib/features/home/presentation/screens/home_screen.dart`
*   `lib/features/home/presentation/screens/main_shell.dart`
*   `lib/features/home/presentation/widgets/post_card.dart`
