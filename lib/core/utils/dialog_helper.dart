import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

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
    String confirmText = '確認',
    String cancelText = 'キャンセル',
    bool isDangerous = false,
    bool barrierDismissible = true,
  }) async {
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
              cancelText,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: isDangerous
                ? TextButton.styleFrom(foregroundColor: AppColors.error)
                : null,
            child: Text(confirmText),
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
    final message = additionalMessage != null
        ? '「$itemName」を削除しますか？\n$additionalMessage'
        : '「$itemName」を削除しますか？';

    return showConfirmDialog(
      context: context,
      title: '削除の確認',
      message: message,
      confirmText: '削除',
      isDangerous: true,
      barrierDismissible: false,
    );
  }

  /// ログアウト確認ダイアログを表示
  static Future<bool> showLogoutConfirmDialog(BuildContext context) {
    return showConfirmDialog(
      context: context,
      title: 'ログアウト',
      message: '本当にログアウトしますか？\nまた会えるのを楽しみにしてるね💫',
      confirmText: 'ログアウト',
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
    String confirmText = '保存',
    String cancelText = 'キャンセル',
    int? maxLength,
    int maxLines = 1,
  }) async {
    final controller = TextEditingController(text: initialValue);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hintText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          maxLength: maxLength,
          maxLines: maxLines,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              cancelText,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(confirmText),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }
}
