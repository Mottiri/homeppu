import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// SnackBar 表示ヘルパー
///
/// アプリ全体で統一されたスタイルの SnackBar を表示するためのユーティリティ。
///
/// 使用例:
/// ```dart
/// SnackBarHelper.showSuccess(context, 'タスクを完了しました！');
/// SnackBarHelper.showError(context, 'エラーが発生しました');
/// SnackBarHelper.showInfo(context, 'お知らせです');
/// ```
class SnackBarHelper {
  SnackBarHelper._();

  /// 成功メッセージを表示（緑色）
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      context,
      message: message,
      backgroundColor: AppColors.success,
      icon: Icons.check_circle_outline,
      duration: duration,
    );
  }

  /// エラーメッセージを表示（赤色）
  static void showError(BuildContext context, String message) {
    _show(
      context,
      message: message,
      backgroundColor: AppColors.error,
      icon: Icons.error_outline,
    );
  }

  /// 情報メッセージを表示（デフォルト色）
  static void showInfo(BuildContext context, String message) {
    _show(
      context,
      message: message,
      backgroundColor: AppColors.textPrimary,
      icon: Icons.info_outline,
    );
  }

  /// 警告メッセージを表示（オレンジ色）
  static void showWarning(BuildContext context, String message) {
    _show(
      context,
      message: message,
      backgroundColor: AppColors.warning,
      icon: Icons.warning_amber_outlined,
    );
  }

  /// カスタム SnackBar を表示
  static void _show(
    BuildContext context, {
    required String message,
    required Color backgroundColor,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    // Scaffold外で呼ばれた場合は何もしない（クラッシュ防止）
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: duration,
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}
