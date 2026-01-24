# Flutter 側リファクタリング計画

## 現状分析

### コードベースサマリー（2026/01/20時点）

| 項目 | 値 |
|------|-----|
| 総行数（Dart） | 33,271行 |
| 総ファイル数 | 99ファイル |
| 最大ファイル | profile_screen.dart（1,730行）|
| 500行超のファイル | 22ファイル |
| テスト | プレースホルダーのみ（実質0）|

### 大きなファイル一覧（分割対象）

| ファイル | 行数 | 優先度 |
|---------|------|--------|
| `profile_screen.dart` | 1,730行 | 高（アバター機能予定）|
| `circle_detail_screen.dart` | 1,370行 | 高 |
| `tasks_screen.dart` | 1,265行 | 高 |
| `circles_screen.dart` | 1,154行 | 中 |
| `settings_screen.dart` | 1,051行 | 中 |
| `task_detail_sheet.dart` | 1,099行 | 中 |
| `task_card.dart` | 1,027行 | 中 |
| `post_card.dart` | 928行 | 中 |
| `goal_detail_screen.dart` | 846行 | 中 |
| `goal_card_with_stats.dart` | 695行 | 低 |
| `create_post_screen.dart` | 673行 | 低 |
| `admin_report_detail_screen.dart` | 664行 | 低 |
| `task_service.dart` | 655行 | 中 |

---

## 重複パターン分析

### 発見された重複パターン

| パターン | 出現箇所 | 共通化優先度 |
|---------|---------|-------------|
| SnackBar表示（`showSnackBar`） | 76箇所（25ファイル） | 高 |
| 確認ダイアログ（`showDialog`） | 28箇所（17ファイル） | 高 |
| ローディング状態管理（`bool _isLoading`） | 21箇所（16ファイル） | 高 |
| CircularProgressIndicator | 多数（39ファイル） | 中 |
| 無限スクロール処理 | 10箇所以上 | 中 |
| debugPrint | 163箇所（27ファイル） | 低（削除対象）|
| **メッセージ文字列（ハードコード）** | 100箇所以上 | 高 |

---

## メッセージ管理の改善

### 現状の問題

`app_constants.dart` に `friendlyMessages` が定義されているが、**ほとんど活用されていない**。

```dart
// 現状: 各所でハードコードされたメッセージ
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('投稿を削除しました')),
);

ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('削除に失敗しました: $e')),
);
```

### 問題点

| 問題 | 影響 |
|------|------|
| メッセージが散在 | 表記揺れが発生（「失敗しました」vs「できませんでした」）|
| 修正が困難 | 同じメッセージを複数箇所で修正が必要 |
| 多言語対応不可 | 将来の国際化対応が困難 |
| トーンの不統一 | フレンドリーな文言とシステム的な文言が混在 |

### 改善案: メッセージファイルの整備

```dart
// lib/core/constants/app_messages.dart（概念例・実際の実装は app_messages.dart 参照）

/// アプリ内メッセージ定義
/// 「ほめっぷ」のフレンドリーなトーンを統一
class AppMessages {
  AppMessages._();

  // ===== 成功メッセージ =====
  static const success = _SuccessMessages();

  // ===== エラーメッセージ =====
  static const error = _ErrorMessages();

  // ===== 確認ダイアログ =====
  static const confirm = _ConfirmMessages();

  // ===== ボタン・ラベル =====
  static const label = _LabelMessages();

  // ===== 空状態 =====
  static const empty = _EmptyMessages();
}

class _SuccessMessages {
  const _SuccessMessages();

  // 投稿関連
  String get postCreated => '投稿できたよ！みんなに届くのを待っててね✨';
  String get postDeleted => '投稿を削除したよ';
  String get commentCreated => 'コメントを送ったよ！';

  // サークル関連
  String get circleCreated => 'サークルを作成したよ！🎉';
  String get circleJoined => 'サークルに参加したよ！';
  String get circleLeft => 'サークルを退会したよ';

  // タスク関連
  String get taskCreated => 'タスクを追加したよ！';
  String get taskCompleted => 'タスク完了！お疲れさま✨';
  String get taskDeleted => 'タスクを削除したよ';

  // ユーザー関連
  String get profileUpdated => 'プロフィールを更新したよ！';
  String get nameChanged => '名前を変更したよ！';
  String get followed => 'フォローしたよ！';
  String get unfollowed => 'フォロー解除したよ';

  // 通報関連
  String get reportSent => '通報を受け付けたよ。確認するね';

  // 問い合わせ関連
  String get inquirySent => '問い合わせを送信したよ！';
  String get replySent => '返信を送ったよ！';
}

class _ErrorMessages {
  const _ErrorMessages();

  // 汎用
  String get general => 'ごめんね、うまくいかなかったみたい😢\nもう一度試してみてね';
  String get network => 'ネットワークの調子が悪いみたい🌐\n接続を確認してね';
  String get unauthorized => 'ログインが必要だよ';
  String get permissionDenied => 'この操作はできないみたい';

  // 投稿関連
  String get postFailed => '投稿できなかったみたい。もう一度試してみてね';
  String get deleteFailed => '削除できなかったみたい';
  String get moderationBlocked => 'この内容は投稿できないみたい😢';

  // バリデーション
  String get emptyContent => '内容を入力してね';
  String get tooLong => '文字数オーバーだよ';

  // 動的エラー（引数付き）
  String withDetail(String detail) => 'エラーが発生しました: $detail';
}

class _ConfirmMessages {
  const _ConfirmMessages();

  // 削除確認
  String deletePost() => 'この投稿を削除する？\nこの操作は取り消せないよ';
  String deleteTask() => 'このタスクを削除する？';
  String deleteCircle(String name) => '「$name」を削除する？\nメンバー全員がアクセスできなくなるよ';
  String deleteComment() => 'このコメントを削除する？';

  // 退会・解除
  String leaveCircle() => '本当にこのサークルを退会する？';
  String unfollow(String name) => '$name さんのフォローを解除する？';

  // ログアウト
  String get logout => '本当にログアウトする？\nまた会えるのを楽しみにしてるね💫';

  // アカウント削除
  String get deleteAccount => '本当にアカウントを削除する？\nすべてのデータが消えちゃうよ😢';
}

class _LabelMessages {
  const _LabelMessages();

  // ボタン
  String get ok => 'OK';
  String get cancel => 'キャンセル';
  String get confirm => '確認';
  String get delete => '削除';
  String get save => '保存';
  String get send => '送信';
  String get close => '閉じる';
  String get retry => '再試行';
  String get yes => 'はい';
  String get no => 'いいえ';

  // 操作
  String get loading => 'ちょっと待っててね...';
  String get sending => '送信中...';
  String get saving => '保存中...';
  String get deleting => '削除中...';
}

class _EmptyMessages {
  const _EmptyMessages();

  String get posts => 'まだ投稿がないよ\n最初の投稿をしてみよう！';
  String get comments => 'まだコメントがないよ';
  String get notifications => '通知はまだないよ';
  String get tasks => 'タスクがないよ\n新しいタスクを追加してみよう！';
  String get circles => 'サークルがないよ\n新しいサークルを探してみよう！';
  String get followers => 'まだフォロワーがいないよ';
  String get following => 'まだ誰もフォローしていないよ';
}
```

### 使用例

```dart
// Before（現状）
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('投稿を削除しました')),
);

// After（改善後）
SnackBarHelper.showSuccess(context, AppMessages.success.postDeleted);

// Before（確認ダイアログ）
showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('確認'),
    content: Text('この投稿を削除しますか？\nこの操作は取り消せません。'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('キャンセル'),
      ),
      // ...
    ],
  ),
);

// After（改善後）
final confirmed = await DialogHelper.showConfirmDialog(
  context: context,
  title: AppMessages.label.confirm,
  message: AppMessages.confirm.deletePost(),
  confirmText: AppMessages.label.delete,
  cancelText: AppMessages.label.cancel,
  isDangerous: true,
);
```

### 既存の friendlyMessages との統合

`app_constants.dart` の `friendlyMessages` は `AppMessages` に統合し、将来的に削除する予定。

> **現状**: `friendlyMessages` は一部の画面でまだ使用中。全置換完了後に削除予定。

```dart
// 統合完了後に app_constants.dart から削除
// static const Map<String, String> friendlyMessages = { ... }; // 将来削除
```

### メリット

| メリット | 説明 |
|---------|------|
| 表記の統一 | 全画面で同じトーンのメッセージ |
| 変更が容易 | 1箇所変更で全体に反映 |
| IDE補完が効く | `AppMessages.success.` で候補表示 |
| 多言語対応の準備 | 将来 `flutter_localizations` への移行が容易 |
| レビューが容易 | メッセージの妥当性を1ファイルで確認 |

---

## 共通化計画

### Phase A: ユーティリティ関数の作成

#### A-1: SnackBar ヘルパー（優先度：高）

**現状**: 各画面で同じようなSnackBar表示コードが散在

```dart
// 現状（82箇所で類似コード）
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('エラーが発生しました')),
);
```

**共通化後**（簡略版・実際の実装は `snackbar_helper.dart` 参照）:

```dart
// lib/core/utils/snackbar_helper.dart（概念例）
class SnackBarHelper {
  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static void showInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// 使用例
SnackBarHelper.showSuccess(context, '保存しました');
SnackBarHelper.showError(context, 'エラーが発生しました');
```

---

#### A-2: 確認ダイアログヘルパー（優先度：高）

**現状**: 削除確認などで毎回AlertDialogを構築

```dart
// 現状（30箇所以上で類似コード）
showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('確認'),
    content: Text('削除しますか？'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('キャンセル'),
      ),
      TextButton(
        onPressed: () {
          Navigator.pop(context);
          _delete();
        },
        child: Text('削除'),
      ),
    ],
  ),
);
```

**共通化後**:

```dart
// lib/core/utils/dialog_helper.dart
class DialogHelper {
  /// 確認ダイアログを表示（戻り値: true=確認, false=キャンセル）
  static Future<bool> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = '確認',
    String cancelText = 'キャンセル',
    bool isDangerous = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: isDangerous
                ? TextButton.styleFrom(foregroundColor: Colors.red)
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 削除確認ダイアログ（よく使うパターン）
  static Future<bool> showDeleteConfirmDialog({
    required BuildContext context,
    required String itemName,
    String? additionalMessage,
  }) {
    return showConfirmDialog(
      context: context,
      title: '削除の確認',
      message: '「$itemName」を削除しますか？${additionalMessage != null ? '\n$additionalMessage' : ''}',
      confirmText: '削除',
      isDangerous: true,
    );
  }
}

// 使用例
final confirmed = await DialogHelper.showDeleteConfirmDialog(
  context: context,
  itemName: 'このタスク',
);
if (confirmed) {
  await _deleteTask();
}
```

---

#### A-3: ローディング状態Mixin（優先度：高）

**現状**: 各画面で `_isLoading` の管理が重複

```dart
// 現状（40箇所以上で類似パターン）
bool _isLoading = true;

Future<void> _loadData() async {
  setState(() => _isLoading = true);
  try {
    // データ取得
  } catch (e) {
    // エラー処理
  } finally {
    setState(() => _isLoading = false);
  }
}
```

**共通化後**:

```dart
// lib/core/mixins/loading_state_mixin.dart（概念例）
mixin LoadingStateMixin<T extends StatefulWidget> on State<T> {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// ローディング状態で処理を実行（二重実行防止付き）
  Future<R?> runWithLoading<R>(Future<R> Function() action) async {
    if (_isLoading) return null;

    setState(() => _isLoading = true);

    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

// 使用例
class _MyScreenState extends State<MyScreen> with LoadingStateMixin {
  Future<void> _loadData() async {
    try {
      await runWithLoading(() async {
        final data = await fetchData();
        // ...
      });
    } catch (e) {
      // エラーはUIに一般化メッセージのみ表示、詳細はログへ
      SnackBarHelper.showError(context, AppMessages.error.general);
      debugPrint('Load failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return CircularProgressIndicator();
    return Content();
  }
}
```

---

#### A-4: 無限スクロールListener（優先度：中）

※ 実装は Phase B（共通Widget作成）で infinite_scroll_listener.dart を追加する。

**方針**: スクロール所有者に `NotificationListener` を置く共通Widget（方式A）で統一  
**対象**: home_screen, circle_detail_screen, profile_screen, circles_screen など
> **補足（運用方針）**
> スクロール所有者は画面構成（CustomScrollView / NestedScrollView / ScrollController等）に合わせて異なることを許容する。  
> 共通化対象は「無限スクロールの発火条件・多重実行ガード」であり、所有者の統一は行わない。

> **運用詳細**
> - profile_screen: child 側で二重実行防止を保持しつつ、親は GlobalKey で `isLoadingMore`/`hasMore` を取得して listener に渡す（運用上の標準）。currentState が null の場合は `hasMore=false` / `isLoadingMore=true` として loadMore を抑制する。
> - circles_screen: ScrollController はスクロールトップ制御のみに使用し、loadMore は InfiniteScrollListener に統一（_onScroll 内の loadMore は廃止）。

```dart
// lib/shared/widgets/infinite_scroll_listener.dart
class InfiniteScrollListener extends StatelessWidget {
  final bool isLoadingMore;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final double threshold;
  final Widget child;

  const InfiniteScrollListener({
    super.key,
    required this.isLoadingMore,
    required this.hasMore,
    required this.onLoadMore,
    this.threshold = 300,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.extentAfter < threshold) {
          if (!isLoadingMore && hasMore) {
            onLoadMore();
          }
        }
        return false;
      },
      child: child,
    );
  }
}
```

---

### Phase B: 共通Widgetの作成

#### 適用優先度（InfiniteScrollListener）

| 優先度 | 画面 | 理由 |
|------|------|------|
| 1 | `profile_screen` | スクロールガード実装済み → ✅ 適用済み（LoadMoreFooter + 再評価） |
| 2 | `circle_detail_screen` | 投稿一覧の無限スクロール使用 → ✅ 適用済み |
| 3 | `home_screen` | TLの無限スクロール使用 → ✅ 適用済み（LoadMoreFooter非表示） |
| 4 | `circles_screen` | サークル一覧の無限スクロール使用 → ✅ 適用済み（検索時LoadMoreFooter非表示） |

#### 全画面統一時の注意点（InfiniteScrollListener / LoadMoreFooter）

- 既存トリガー（NotificationListener / _onScroll / addPostFrameCallback など）は必ず撤去し、無限スクロールの発火経路は一本化する。
- スクロール所有者を必ずラップする（NestedScrollView は内側リスト、CustomScrollView はそのまま）。外側 ScrollController はスクロールトップ制御用途に限定する。
- `LoadMoreFooter` の表示条件は `hasMore && !isLoadingMore && 初回ロード完了 && canLoadMore && !isScrollable` を標準とする。
- `isScrollable` はレイアウト後に再評価し、初回ロード・追加読み込み・削除/フィルタなどリスト長が変わる操作のたびに更新する（post-frameで再計測）。
- **例外**: `home_screen`（`NestedScrollView`）は`isScrollable`判定が不安定なため、`LoadMoreFooter`は`isScrollable: true`固定で手動フォールバックは非表示とする。


#### 既存の共通Widget（実装済み）

以下のWidgetは既に共通化されています：

| Widget | 場所 | 機能 |
|--------|------|------|
| `FullScreenImageViewer` | `lib/shared/widgets/full_screen_image_viewer.dart` | 画像フルスクリーン表示 |

**FullScreenImageViewer の使用例**:

```dart
// 静的メソッドで簡単に呼び出し
FullScreenImageViewer.show(
  context,
  imageUrl,
  heroTag: 'image_$index',  // オプション: Hero アニメーション
);
```

**特徴**:
- ピンチズーム対応（InteractiveViewer: 0.5x〜4.0x）
- Hero アニメーション対応
- ローディング表示（プログレス付き）
- エラー表示（アイコン）
- タップまたは閉じるボタンで終了
- フェードトランジション

---

#### B-1: ローディングオーバーレイ

※ 入力ブロックのため `AbsorbPointer` を標準にする。

```dart
// lib/shared/widgets/loading_overlay.dart
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final String? message;

  const LoadingOverlay({
    required this.isLoading,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AbsorbPointer(
          absorbing: isLoading,
          child: child,
        ),
        if (isLoading)
          Container(
            color: Colors.black26,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  if (message != null) ...[
                    SizedBox(height: 16),
                    Text(message!, style: TextStyle(color: Colors.white)),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
```

#### B-2: エラー表示Widget

**方針**
- メッセージは `AppMessages.error.*` を使用する
- 色/テーマは `AppColors` を使用し、必要なら引数で上書き可能にする


```dart
// lib/shared/widgets/error_view.dart
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorView({
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
          SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
          if (onRetry != null) ...[
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: Text(AppMessages.label.retry),
            ),
          ],
        ],
      ),
    );
  }
}
```

#### B-3: 空状態Widget

**方針**
- メッセージは `AppMessages.empty.*` を使用する
- 色/テーマは `AppColors` を使用し、必要なら引数で上書き可能にする


```dart
// lib/shared/widgets/empty_view.dart
class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  const EmptyView({
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: AppColors.textTertiary),
          SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (description != null) ...[
            SizedBox(height: 8),
            Text(description!, style: TextStyle(color: AppColors.textSecondary)),
          ],
          if (action != null) ...[
            SizedBox(height: 24),
            action!,
          ],
        ],
      ),
    );
  }
}
```

---

### Phase C: 大きなファイルの分割

#### C-1: profile_screen.dart（1,730行）

**現状の構造**:
- ヘッダー表示（カラーパレット、アバター）
- ユーザー情報表示
- 統計情報（投稿数、フォロワー等）
- 投稿一覧（無限スクロール）
- フォロー/フォロー解除
- 設定メニュー
- **管理者メニュー・BAN関連**（重要操作）
- **_UserPostsList / _ProfilePostCard / _FollowingList**（内部Widget）

**分割後**:

```
lib/features/profile/presentation/
├── screens/
│   └── profile_screen.dart        # メインコンテナ（300行程度）
└── widgets/
    ├── profile_header.dart        # ヘッダー部分（配色・アバター表示）
    ├── profile_stats.dart         # 統計情報
    ├── profile_actions.dart       # フォローボタン等
    ├── profile_posts_list.dart    # 投稿一覧（loadMoreは親から通知）
    ├── profile_post_card.dart     # 投稿カード（_ProfilePostCardから移行）
    ├── profile_following_list.dart # フォロー一覧
    ├── profile_menu.dart          # 設定メニュー（現状は軽量、拡張予定がなければprofile_header統合も可）
    └── profile_admin_actions.dart # 管理者メニュー・BAN関連（専用Widget）
```

**設計上の注意点**:

> [!IMPORTANT]
> **無限スクロールの疎結合化**
> 現状: GlobalKey経由で親が `loadMoreCurrentTab()` を呼ぶ構造（強結合）
> 対策: スクロール所有者側（`profile_screen.dart` など）に `InfiniteScrollListener` を配置し、`onLoadMore` で `loadMoreCurrentTab()` を呼ぶ形式に統一
> 補足: isLoadingMore/hasMore は子側で二重実行防止を維持し、親は GlobalKey 経由で両方取得して listener 側の無駄呼び出しを抑制する（運用標準）。

> [!WARNING]
> **ヘッダー配色の責務**
> 現状: 配色生成（`_primaryAccent`, `_secondaryAccent`）が画面Stateで計算・保持
> 対策: 親で計算→子に値渡し（props経由）を徹底し、複数UIでの色ズレ・再計算を防止

> [!CAUTION]
> **管理者メニュー/BAN関連の安全性**
> - 重要操作のため `barrierDismissible: false` 必須
> - `profile_admin_actions.dart` として専用Widget/サービス化
> - レビュー時にセキュリティルール遵守を確認

**アバター機能追加時の拡張**:

```
└── widgets/
    ├── profile_header.dart
    │   └── AvatarDisplay を使用
    └── avatar/                    # 新規追加
        ├── avatar_display.dart    # アバター表示（パーツ重ね合わせ）
        ├── avatar_editor.dart     # パーツ選択UI
        └── avatar_part_picker.dart # 個別パーツ選択
```

---

#### C-2: tasks_screen.dart（1,265行）

**分割後**:

```
lib/features/tasks/presentation/
├── screens/
│   └── tasks_screen.dart          # メインコンテナ（400行程度）
└── widgets/
    ├── task_list_view.dart        # タスク一覧
    ├── task_filter_bar.dart       # フィルター・ソート
    ├── task_calendar_header.dart  # カレンダーヘッダー
    ├── task_edit_mode_bar.dart    # 編集モードバー
    └── task_empty_view.dart       # 空状態
```

---

#### C-3: circle_detail_screen.dart（1,370行）

**状態**: ✅ 分割完了（2026-01-24）

**分割後**:

```
lib/features/circle/presentation/
├── screens/
│   └── circle_detail_screen.dart  # メインコンテナ（350行程度）
└── widgets/
    ├── circle_header.dart         # サークル情報ヘッダー
    ├── circle_members_bar.dart    # メンバー表示バー
    ├── circle_posts_list.dart     # 投稿一覧
    ├── circle_actions.dart        # 参加/退会ボタン等
    └── circle_settings_menu.dart  # 設定メニュー
```

---

## 新規ディレクトリ構造

```
lib/
├── core/
│   ├── constants/
│   ├── router/
│   ├── theme/
│   ├── utils/                     # 【新規】ユーティリティ
│   │   ├── snackbar_helper.dart
│   │   ├── dialog_helper.dart
│   │   └── validators.dart
│   └── mixins/                    # 【新規】Mixin
│       └── loading_state_mixin.dart
├── features/
│   ├── profile/
│   │   └── presentation/
│   │       ├── screens/
│   │       │   └── profile_screen.dart
│   │       └── widgets/           # 【拡充】
│   │           ├── profile_header.dart
│   │           ├── profile_stats.dart
│   │           └── avatar/        # 【将来】アバター機能
│   └── ...
└── shared/
    ├── widgets/
    │   ├── loading_overlay.dart   # 【新規】
    │   ├── error_view.dart        # 【新規】
    │   ├── empty_view.dart        # 【新規】
    │   ├── infinite_scroll_listener.dart # 【新規】
    │   └── ...
    └── ...
```

---

## 実装優先順位

### 優先度：高（今すぐ着手）

| 順位 | 作業 | 効果 | 工数目安 | 状態 |
|-----|------|------|---------|---|
| 1 | `app_messages.dart` 作成 | メッセージ一元管理、表記統一 | 小 | ✅ 完了 |
| 2 | `snackbar_helper.dart` 作成 | 117箇所の統一 | 小 | ✅ 完了 |
| 3 | `dialog_helper.dart` 作成 | 35箇所以上の統一 | 小 | ✅ 完了 |
| 4 | **既存コードへの適用**（下記参照）| 段階的置換 | 中 | ✅ 完了 |
| 5 | `loading_state_mixin.dart` 作成 | 21箇所の統一 | 中 | ✅ 完了 |
| 6 | `profile_screen.dart` 分割（Phase 1: 内部Widget抽出） | 885行削減 | 大 | ✅ 完了 |
| 6a | `profile_screen.dart` 分割（Phase 2: スクロールガード追加） | isLoadingMore/hasMoreチェック | 中 | ✅ 完了 |

---

### Phase B: 共通Widget作成（2026/01/22時点）

| 作業 | 効果 | 状態 |
|------|------|------|
| `infinite_scroll_listener.dart` 作成 | 無限スクロール発火・ガード統一 | ✅ 完了 |
| `load_more_footer.dart` 作成 | ショートリスト用もっと読み込むボタン | ✅ 完了 |
| `loading_overlay.dart` 作成 | AbsorbPointer付きローディング | ✅ 完了 |
| `error_view.dart` 作成 | エラー表示統一 | ✅ 完了 |
| `empty_view.dart` 作成 | 空状態表示統一 | ✅ 完了 |
| `circle_detail_screen.dart` に適用 | InfiniteScrollListener + LoadMoreFooter | ✅ 完了 |
| `home_screen.dart` 共通Widget適用 | 既存方式から移行 | ✅ 完了（LoadMoreFooter非表示） |
| `circles_screen.dart` 共通Widget適用 | 既存方式から移行 | ✅ 完了（検索時LoadMoreFooter/LoadMore抑制） |
| `LoadMoreFooter` 実機テスト | ショートリスト時のボタン表示確認 | ✅ 完了（実機） |

> **注**: `profile_screen` は InfiniteScrollListener + LoadMoreFooter に置換済み（GlobalKeyで`hasMore/isLoadingMore`取得、読み込み完了で`_isScrollable`再評価）。

**レビュー結果（対応済み）**
- `profile_screen`: `_isScrollable` の再評価を読み込み完了/タブ切替後に実施
- `circles_screen`: 検索時は `LoadMoreFooter` を抑制、loadMore発火を停止
- 検証: flutter analyze 通過（既存warning 5件）
- 実機テスト: LoadMoreFooter動作確認済み

---

## 既存コードへのヘルパー適用手順

### 対象ファイル（SnackBar使用箇所が多い順）

| 画面 | SnackBar置換 | Dialog置換 | 状態 |
|------|-------------|-----------|------|
| `tasks_screen.dart` | ✅ | ✅ | ✅ 完了 |
| `circle_detail_screen.dart` | ✅ | ✅ | ✅ 完了 |
| `profile_screen.dart` | ✅ | ✅ | ✅ 完了 |
| `settings_screen.dart` | ✅ | ✅ | ✅ 完了 |
| `create_post_screen.dart` | ✅ | - | ✅ 完了 |

> **注**: カスタムUI（進捗表示・CircularProgressIndicator付き等）の直書きは許容。詳細は `FLUTTER_HELPERS_REVIEW.md` 参照。

### 置き換え手順

#### 1. import追加

```dart
import '../../core/utils/snackbar_helper.dart';
import '../../core/utils/dialog_helper.dart';
import '../../core/constants/app_messages.dart';
```

#### 2. SnackBar置き換え

```dart
// Before
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('タスクを完了しました！')),
);

// After
SnackBarHelper.showSuccess(context, AppMessages.success.taskCompleted);
```

#### 3. Dialog置き換え

```dart
// Before
final confirmed = await showDialog<bool>(...);

// After
final confirmed = await DialogHelper.showDeleteConfirmDialog(
  context: context,
  itemName: 'このタスク',
);
```

### 適用のタイミング

> **推奨**: 新機能開発や既存バグ修正のついでに、触ったファイルから段階的に置き換え

### ⚠️ 適用時の注意: 例外詳細の非表示

既存コードには `$e` を直接表示している箇所が多数あります。適用時は必ず以下のパターンに修正してください：

```dart
// ❌ 避けるべきパターン
catch (e) {
  SnackBarHelper.showError(context, '失敗しました: $e');
}

// ✅ 推奨パターン
catch (e) {
  SnackBarHelper.showError(context, AppMessages.error.general);
  debugPrint('Operation failed: $e');  // ログには残す
}
```

詳細は `FLUTTER_HELPERS_REVIEW.md` を参照。

---

### 優先度：中


| 順位 | 作業 | 効果 |
|-----|------|------|
| 6 | `tasks_screen.dart` 分割（✅ 完了） | 1,265行削減 |
| 7 | `circle_detail_screen.dart` 分割（✅ 完了） | 1,370行削減 |
| 8 | `infinite_scroll_listener.dart` 作成（✅ 完了） | 10箇所の統一 |
| 9 | 共通Widget作成（loading_overlay等）（✅ 完了）| UI統一 |
| 10 | 各画面でAppMessages適用（⏳ 残作業） | メッセージ統一 |

> **注**: 行削減の数値はリファクタリング前との差分の目安。  
> **注**: AppMessages適用は「ハードコードを基本ゼロ」にすることを完了条件とする。

### 優先度：低（長期）

| 作業 | 効果 |
|------|------|
| debugPrint 整理（163箇所） | ログ品質向上 |
| テスト追加 | 品質担保 |
| data/domain層の活用 | アーキテクチャ改善 |

**低優先度TODO（検討）**
- [ ] `lib/features/tasks/presentation/widgets/task_edit_mode_bar.dart:32` `Colors.orange.shade50` の `AppColors` 定数化
- [ ] `lib/features/tasks/presentation/widgets/task_empty_view.dart:32` / `lib/features/tasks/presentation/widgets/task_list_view.dart:70` の `Colors.grey.shade300/600` を `AppColors` へ統一
- [ ] `lib/features/tasks/presentation/widgets/task_empty_view.dart:40` の `SizedBox(height: 100)` を `AppSpacing` 定数化
- [ ] `lib/features/tasks/presentation/widgets/task_list_view.dart:131` の `highlight` スクロール `100.0` を `itemHeight` 定数化

---

## 共通化による削減効果（予測）

| 対象 | 現在の重複行数 | 共通化後 | 削減率 |
|------|--------------|---------|--------|
| SnackBar表示 | 約228行（76箇所×3行）| 76行（1行×76箇所）| 67% |
| 確認ダイアログ | 約420行（28箇所×15行）| 56行（2行×28箇所）| 87% |
| ローディング管理 | 約105行（21箇所×5行）| 21行（1行×21箇所）| 80% |
| **合計** | **約753行** | **約153行** | **80%** |

---

## テスト計画

### 共通化後のテスト

| テスト対象 | テスト内容 |
|-----------|-----------|
| `SnackBarHelper` | 各タイプのSnackBarが正しく表示されるか |
| `DialogHelper` | 確認/キャンセルの戻り値が正しいか |
| `LoadingStateMixin` | ローディング状態が正しく遷移するか |
| 分割後のWidget | 表示が崩れていないか |

### 実機テストチェックリスト

- [ ] プロフィール画面が正常表示
- [ ] フォロー/フォロー解除が動作
- [ ] 投稿一覧の無限スクロールが動作
- [ ] 各種SnackBarが正常表示
- [ ] 削除確認ダイアログが正常動作
- [ ] ローディング表示が正常

---

## 備考

### AI支援開発での注意点

1. **ファイルサイズ**: 300-500行を目安に維持
2. **関数の責務**: 1関数1責務を徹底
3. **共通化の徹底**: 新規コードも必ず共通ヘルパーを使用
4. **テストの追加**: 共通化した部分から順次テスト追加

### タスク画面の補足

- highlightTaskId は日付変更操作（週カレンダー/月間カレンダー/ページ移動）で解除する
- highlightTaskId は自動スクロール後に短時間で解除する
- highlightTaskId では画面再生成しない（forceRefresh のみ）。ハイライト更新は didUpdateWidget で反映する
- ハイライトは highlightRequestId の変更時のみ発火し、戻る遷移で再発火しないようにする
- targetCategoryId のタブ切替は post-frame で実行し、Provider 更新のタイミングを安定化する
- targetDate のプログラムジャンプは onPageChanged を抑制し、Provider 更新のタイミングを安定化する
- ハイライト時に targetCategoryId が null の場合はデフォルトタブへ自動で戻す

### ⚠️ セキュリティ/運用ルール（必須遵守）

以下のルールはレビューで必ずチェックすること。

#### 1. 例外詳細のUI非表示

```dart
// ❌ 禁止: 例外をUIに表示
catch (e) {
  SnackBarHelper.showError(context, 'エラー: $e');
}

// ✅ 必須: 一般化メッセージ + ログ
catch (e) {
  SnackBarHelper.showError(context, AppMessages.error.general);
  debugPrint('Operation failed: $e');
}
```

> **理由**: 例外文字列には内部パス、クエリ、設定情報などが含まれる可能性がある

#### 2. 重要操作のダイアログは `barrierDismissible: false`

```dart
// 削除、BAN、ログアウトなどの重要操作
DialogHelper.showConfirmDialog(
  context: context,
  title: '削除確認',
  message: '本当に削除しますか？',
  barrierDismissible: false,  // ← 必須
  isDangerous: true,
);
```

> **対象**: 削除、BAN/解除、ログアウト、サークル退会など不可逆または重要な操作

#### 3. 重要通知の冗長化

`SnackBarHelper` は `maybeOf` を使用しており、Scaffoldがない場合はサイレント失敗する。
重要な通知（BAN通知など）は以下のいずれかで補強すること：

- 画面内にも状態を表示（バナー、テキスト等）
- 必要に応じてダイアログで確実に伝える

### 将来のアバター機能に向けて

- `profile_header.dart` はアバター表示の主要な場所
- `avatar/` ディレクトリを作成して関連コードを集約
- パーツデータは Firestore または ローカルアセットで管理





