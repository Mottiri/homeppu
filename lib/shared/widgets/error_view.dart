import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_messages.dart';

/// エラー表示Widget
///
/// 使用方法:
/// ```dart
/// ErrorView(
///   message: AppMessages.error.general,
///   onRetry: _loadData,
/// )
/// ```
class ErrorView extends StatelessWidget {
  /// 表示メッセージ
  final String message;

  /// 再試行コールバック（オプション）
  final VoidCallback? onRetry;

  const ErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onRetry,
                child: Text(AppMessages.label.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
