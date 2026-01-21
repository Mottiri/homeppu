import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// 空状態表示Widget
///
/// 使用方法:
/// ```dart
/// EmptyView(
///   title: '投稿がありません',
///   description: '最初の投稿を作成しましょう',
///   icon: Icons.inbox_outlined,
///   action: ElevatedButton(...),
/// )
/// ```
class EmptyView extends StatelessWidget {
  /// アイコン
  final IconData icon;

  /// タイトル
  final String title;

  /// 説明文（オプション）
  final String? description;

  /// アクションWidget（オプション）
  final Widget? action;

  const EmptyView({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                style: TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}
