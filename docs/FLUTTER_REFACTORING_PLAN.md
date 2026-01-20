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
| SnackBar表示（`showSnackBar`） | 117箇所（29ファイル） | 高 |
| 確認ダイアログ（`showDialog`） | 35箇所（15ファイル） | 高 |
| ローディング状態管理（`bool _isLoading`） | 21箇所（17ファイル） | 高 |
| CircularProgressIndicator | 多数（39ファイル） | 中 |
| 無限スクロール処理 | 10箇所以上 | 中 |
| debugPrint | 150箇所以上 | 低（削除対象）|
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

#### A-4: 無限スクロールMixin（優先度：中）

**現状**: circles_screen, profile_screen などで類似実装

```dart
// lib/core/mixins/infinite_scroll_mixin.dart
mixin InfiniteScrollMixin<T extends StatefulWidget> on State<T> {
  final ScrollController scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isLoadingMore || !_hasMore) return;
    if (scrollController.position.pixels >=
        scrollController.position.maxScrollExtent - 200) {
      loadMore();
    }
  }

  /// サブクラスでオーバーライド
  Future<void> loadMore();

  /// ロード中フラグを設定
  void setLoadingMore(bool value) {
    setState(() => _isLoadingMore = value);
  }

  /// 追加データがあるかフラグを設定
  void setHasMore(bool value) {
    setState(() => _hasMore = value);
  }
}
```

---

### Phase B: 共通Widgetの作成

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
        child,
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
          Icon(Icons.error_outline, size: 48, color: Colors.grey),
          SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: Text('再試行'),
            ),
          ],
        ],
      ),
    );
  }
}
```

#### B-3: 空状態Widget

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
          Icon(icon, size: 64, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (description != null) ...[
            SizedBox(height: 8),
            Text(description!, style: TextStyle(color: Colors.grey)),
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

**分割後**:

```
lib/features/profile/presentation/
├── screens/
│   └── profile_screen.dart        # メインコンテナ（300行程度）
└── widgets/
    ├── profile_header.dart        # ヘッダー部分（アバター表示）
    ├── profile_stats.dart         # 統計情報
    ├── profile_actions.dart       # フォローボタン等
    ├── profile_posts_list.dart    # 投稿一覧（無限スクロール）
    └── profile_menu.dart          # 設定メニュー
```

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
│       ├── loading_state_mixin.dart
│       └── infinite_scroll_mixin.dart
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
| 6 | `profile_screen.dart` 分割 | アバター準備、1,730行削減 | 大 | 未着手 |

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
| 6 | `tasks_screen.dart` 分割 | 1,265行削減 |
| 7 | `circle_detail_screen.dart` 分割 | 1,370行削減 |
| 8 | `infinite_scroll_mixin.dart` 作成 | 10箇所の統一 |
| 9 | 共通Widget作成（loading_overlay等）| UI統一 |
| 10 | 各画面でAppMessages適用 | メッセージ統一 |

### 優先度：低（長期）

| 作業 | 効果 |
|------|------|
| debugPrint 整理（141箇所） | ログ品質向上 |
| テスト追加 | 品質担保 |
| data/domain層の活用 | アーキテクチャ改善 |

---

## 共通化による削減効果（予測）

| 対象 | 現在の重複行数 | 共通化後 | 削減率 |
|------|--------------|---------|--------|
| SnackBar表示 | 約350行（117箇所×3行）| 117行（1行×117箇所）| 67% |
| 確認ダイアログ | 約525行（35箇所×15行）| 70行（2行×35箇所）| 87% |
| ローディング管理 | 約105行（21箇所×5行）| 21行（1行×21箇所）| 80% |
| **合計** | **約980行** | **約208行** | **79%** |

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
