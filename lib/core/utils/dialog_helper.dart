import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_messages.dart';

/// ダイアログ表示ヘルパー
///
/// アプリ全体で統一されたスタイルのダイアログを表示するためのユーティリティ。
///
/// 使用例:
/// ```dart
/// final confirmed = await DialogHelper.showConfirmDialog(
///   context: context,
///   title: '確認',
///   message: '本当に削除しますか？',
///   isDangerous: true,
/// );
/// if (confirmed) {
///   await deleteItem();
/// }
/// ```
class DialogHelper {
  DialogHelper._();

  /// 確認ダイアログを表示
  ///
  /// 戻り値: true = 確認ボタン押下, false = キャンセルまたは外側タップ
  ///
  /// [barrierDismissible] を false にすると、外側タップでダイアログが閉じなくなる（危険操作向け）
  static Future<bool> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String message,
    String? confirmText,
    String? cancelText,
    bool isDangerous = false,
    bool barrierDismissible = true,
  }) async {
    final resolvedConfirmText = confirmText ?? AppMessages.label.confirm;
    final resolvedCancelText = cancelText ?? AppMessages.label.cancel;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              resolvedCancelText,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: isDangerous
                ? TextButton.styleFrom(foregroundColor: AppColors.error)
                : null,
            child: Text(resolvedConfirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 削除確認ダイアログを表示（よく使うパターン）
  ///
  /// 使用例:
  /// ```dart
  /// final confirmed = await DialogHelper.showDeleteConfirmDialog(
  ///   context: context,
  ///   itemName: 'このタスク',
  /// );
  /// ```
  static Future<bool> showDeleteConfirmDialog({
    required BuildContext context,
    required String itemName,
    String? additionalMessage,
  }) {
    final message = AppMessages.confirm.deleteItem(
      itemName,
      additionalMessage: additionalMessage,
    );

    return showConfirmDialog(
      context: context,
      title: AppMessages.confirm.deleteTitle,
      message: message,
      confirmText: AppMessages.label.delete,
      isDangerous: true,
      barrierDismissible: false,
    );
  }

  /// ログアウト確認ダイアログを表示
  static Future<bool> showLogoutConfirmDialog(BuildContext context) {
    return showConfirmDialog(
      context: context,
      title: AppMessages.label.logout,
      message: AppMessages.confirm.logout,
      confirmText: AppMessages.label.logout,
      isDangerous: true,
      barrierDismissible: false,
    );
  }

  /// 入力ダイアログを表示
  ///
  /// 戻り値: 入力されたテキスト、キャンセル時は null
  static Future<String?> showInputDialog({
    required BuildContext context,
    required String title,
    String? initialValue,
    String? hintText,
    String? confirmText,
    String? cancelText,
    int? maxLength,
    int maxLines = 1,
  }) async {
    String? result;
    final resolvedConfirmText = confirmText ?? AppMessages.label.save;
    final resolvedCancelText = cancelText ?? AppMessages.label.cancel;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController(text: initialValue);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hintText,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            maxLength: maxLength,
            maxLines: maxLines,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                resolvedCancelText,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                result = controller.text;
                Navigator.pop(dialogContext);
              },
              child: Text(resolvedConfirmText),
            ),
          ],
        );
      },
    );

    return result;
  }
}
