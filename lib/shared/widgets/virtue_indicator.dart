import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../providers/moderation_provider.dart';
import '../services/moderation_service.dart';

/// 徳ポイント表示ウィジェット
class VirtueIndicator extends ConsumerWidget {
  final bool showLabel;
  final double size;

  const VirtueIndicator({super.key, this.showLabel = true, this.size = 40});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final virtueAsync = ref.watch(virtueStatusProvider);

    return virtueAsync.when(
      data: (status) =>
          _VirtueDisplay(status: status, showLabel: showLabel, size: size),
      loading: () => SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.virtue,
        ),
      ),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}

class _VirtueDisplay extends StatelessWidget {
  final VirtueStatus status;
  final bool showLabel;
  final double size;

  const _VirtueDisplay({
    required this.status,
    required this.showLabel,
    required this.size,
  });

  Color get _color {
    if (status.virtue <= 0) return AppColors.error;
    if (status.needsWarning) return AppColors.warning;
    if (status.virtue >= 80) return AppColors.success;
    return AppColors.virtue;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showVirtueDialog(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // 背景の円
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 3,
                  backgroundColor: AppColors.surfaceVariant,
                  valueColor: AlwaysStoppedAnimation(
                    _color.withValues(alpha: 0.3),
                  ),
                ),
              ),
              // 進捗の円
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: status.virtueRatio.clamp(0.0, 1.0),
                  strokeWidth: 3,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(_color),
                ),
              ),
              // 徳アイコン
              Text(
                '徳',
                style: TextStyle(
                  fontSize: size * 0.35,
                  fontWeight: FontWeight.bold,
                  color: _color,
                ),
              ),
            ],
          ),
          if (showLabel) ...[
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${status.virtue}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _color,
                  ),
                ),
                if (status.needsWarning)
                  Text(
                    '⚠️ 注意',
                    style: TextStyle(fontSize: 10, color: AppColors.warning),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showVirtueDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => VirtueDetailDialog(status: status),
    );
  }
}

/// 徳ポイント詳細ダイアログ
class VirtueDetailDialog extends ConsumerWidget {
  final VirtueStatus status;

  const VirtueDetailDialog({super.key, required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(virtueHistoryProvider);

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.virtue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('✨', style: TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 12),
          const Text('徳ポイント'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 現在の徳ポイント
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.virtue.withValues(alpha: 0.1),
                    AppColors.virtue.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${status.virtue}',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: AppColors.virtue,
                    ),
                  ),
                  Text(
                    ' / ${status.maxVirtue}',
                    style: TextStyle(
                      fontSize: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 説明
            Text(
              '徳ポイントは、ほめっぷでの行いを表す指標だよ☺️',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '• ポジティブな投稿で徳が上がるよ\n• ネガティブな発言をすると下がるよ\n• 0になると投稿できなくなるよ',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),

            if (status.needsWarning) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Text('⚠️', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '徳ポイントが少なくなっているよ。ポジティブな投稿を心がけてね！',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // 履歴
            Text('履歴', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),

            historyAsync.when(
              data: (history) {
                if (history.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'まだ履歴がないよ',
                        style: TextStyle(color: AppColors.textHint),
                      ),
                    ),
                  );
                }

                return SizedBox(
                  height: 150,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: history.take(5).length,
                    itemBuilder: (context, index) {
                      final item = history[index];
                      final isPositive = item.change > 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isPositive
                                    ? AppColors.success.withValues(alpha: 0.1)
                                    : AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isPositive
                                    ? '+${item.change}'
                                    : '${item.change}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isPositive
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.reason,
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.virtue),
              ),
              error: (e, _) => const Text('履歴を読み込めませんでした'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

/// コンパクトな徳ポイントバッジ
class VirtueBadge extends ConsumerWidget {
  const VirtueBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final virtueAsync = ref.watch(virtueStatusProvider);

    return virtueAsync.when(
      data: (status) {
        Color color = AppColors.virtue;
        if (status.virtue <= 0) {
          color = AppColors.error;
        } else if (status.needsWarning) {
          color = AppColors.warning;
        } else if (status.virtue >= 80) {
          color = AppColors.success;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '徳',
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${status.virtue}',
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}
