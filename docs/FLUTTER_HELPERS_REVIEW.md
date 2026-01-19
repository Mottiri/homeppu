# Flutter ヘルパー実装レビュー（SnackBar / Dialog）

## 目的

`SnackBarHelper` / `DialogHelper` / `AppMessages` の実装について、開発運用上・セキュリティ上のリスク有無を確認し、改善提案をまとめる。

## 対象

- `lib/core/utils/snackbar_helper.dart`
- `lib/core/utils/dialog_helper.dart`
- `lib/core/constants/app_messages.dart`（エラーメッセージ設計の観点）

## 完了基準の定義

| 項目 | 基準 |
|------|------|
| 例外詳細の非表示 | UIに `$e` を表示しない（`debugPrint` は許容） |
| ヘルパー適用 | 汎用的なSnackBar/DialogはHelper使用、**カスタムUI（Checkbox付き、入力フォーム付き等）は直書き許容** |
| 安全性 | `maybeOf` 使用、重要操作は `barrierDismissible: false` |

## 改善案と対応状況

| # | リスク | 改善案 | 状態 |
|---|--------|--------|------|
| 1 | 例外詳細のユーザー露出 | 一般化メッセージ + ログ | ✅ 完了（UI非表示化） |
| 2 | Scaffold外でのクラッシュ | `maybeOf` 化 | ✅ 完了 |
| 3 | 外側タップで閉じる | `barrierDismissible` 追加 | ✅ 完了 |

---

## ✅ 完了した改善

### 改善案1: 例外詳細のUI非表示化（2026/01/19）

```dart
// Before（問題のあるパターン）
catch (e) {
  SnackBarHelper.showError(context, '失敗しました: $e');
}

// After（推奨パターン）
catch (e) {
  SnackBarHelper.showError(context, AppMessages.error.general);
  debugPrint('Operation failed: $e');  // ログには残す（リリースビルドでは無効）
}
```

**対応済みファイル**: `tasks_screen.dart`, `circle_detail_screen.dart`

### 改善案2: `maybeOf` 化（2026/01/18）

```dart
// Before
ScaffoldMessenger.of(context).showSnackBar(...);

// After
final messenger = ScaffoldMessenger.maybeOf(context);
if (messenger == null) return;
messenger.showSnackBar(...);
```

### 改善案3: `barrierDismissible` 追加（2026/01/18）

- `showConfirmDialog` に `barrierDismissible` パラメータ追加
- `showDeleteConfirmDialog` と `showLogoutConfirmDialog` はデフォルトで `false`（外側タップ無効）

---

## 📋 許容される直書き

以下のケースは `DialogHelper` では対応できないため、直書きを許容します：

| ファイル | 箇所 | 理由 |
|----------|------|------|
| `tasks_screen.dart` | `_confirmDelete` | Checkbox付きダイアログ（StatefulBuilder使用） |
| `circle_detail_screen.dart` | `_showDeleteDialog` | 削除理由入力フォーム付き |
| `circle_detail_screen.dart` | `_handleDeleteCircle` | 進捗表示付きSnackBar（Row＋CircularProgressIndicator） |
| `circle_detail_screen.dart` | `_showRulesConsentDialog` | ルール表示付きカスタムUI |
| `circle_detail_screen.dart` | `_showRulesDialog` | ルール表示付きカスタムUI |
| `circle_detail_screen.dart` | `_showPinnedPostsList` | リスト表示ボトムシート |

これらの直書きでは以下を遵守しています：
- **重要操作**（削除、参加確認）は `barrierDismissible: false`
- **閲覧用**（ルール確認）はデフォルト（`true`）で許容
- エラー時は `$e` をUIに表示しない

---

## 対応履歴

| 日付 | 内容 |
|------|------|
| 2026/01/18 | 誤適用差分を取り消し（対応案A採用） |
| 2026/01/18 | `maybeOf` 化、`barrierDismissible` 追加 |
| 2026/01/18 | `tasks_screen.dart` にヘルパー適用（-60行） |
| 2026/01/19 | `circle_detail_screen.dart` にヘルパー適用 |
| 2026/01/19 | 例外詳細のUI非表示化完了、完了基準を明確化 |
