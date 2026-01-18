# Flutter ヘルパー実装レビュー（SnackBar / Dialog）

## 目的

`SnackBarHelper` / `DialogHelper` / `AppMessages` の実装について、開発運用上・セキュリティ上のリスク有無を確認し、改善提案をまとめる。

## 対象

- `lib/core/utils/snackbar_helper.dart`
- `lib/core/utils/dialog_helper.dart`
- `lib/core/constants/app_messages.dart`（エラーメッセージ設計の観点）

## 改善案と対応状況

| # | リスク | 改善案 | 状態 |
|---|--------|--------|------|
| 1 | 例外詳細のユーザー露出 | 一般化メッセージ + ログ | ✅ 完了（tasks/circle） |
| 2 | Scaffold外でのクラッシュ | `maybeOf` 化 | ✅ 完了 |
| 3 | 外側タップで閉じる | `barrierDismissible` 追加 | ✅ 完了 |

---

## ✅ 完了した改善

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

## 🔶 未対応: 例外詳細のユーザー露出防止

### 現状の問題

既存コードの多くの箇所で、エラー時に `$e` を直接表示している：

```dart
// 問題のあるパターン
try {
  await someOperation();
} catch (e) {
  SnackBarHelper.showError(context, '失敗しました: $e');
  //                                               ↑ 内部情報露出
}
```

### 推奨する対応

```dart
// 推奨パターン
try {
  await someOperation();
} catch (e) {
  SnackBarHelper.showError(context, AppMessages.error.general);
  debugPrint('Operation failed: $e');  // ログには残す
}
```

### 対応タイミング

既存コードへのヘルパー適用時（`FLUTTER_REFACTORING_PLAN.md` の「既存コードへのヘルパー適用手順」参照）に、一緒に対応することを推奨。

### 対象箇所（例）

| ファイル | 該当パターン |
|---------|-------------|
| `tasks_screen.dart` | `'失敗しました: $e'` 等 |
| `circle_detail_screen.dart` | `'エラー: $e'` 等 |
| `settings_screen.dart` | `'更新に失敗しました: $e'` 等 |
| その他多数 | `catch` ブロック内の `$e` 表示 |

---

## 対応履歴

| 日付 | 内容 |
|------|------|
| 2026/01/18 | 誤適用差分を取り消し（対応案A採用） |
| 2026/01/18 | `maybeOf` 化、`barrierDismissible` 追加 |
| 2026/01/18 | `tasks_screen.dart` にヘルパー適用（-60行）、例外詳細非表示化 |

---
## 追記（2026/01/18）
`tasks_screen.dart` および `circle_detail_screen.dart` へのヘルパー適用・例外詳細非表示化は完了しました。
直書きコードは解消され、安全な実装に置き換わっています。
