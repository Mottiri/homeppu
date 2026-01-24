import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

class ProfileAdminReportBadge extends StatelessWidget {
  final bool isAdmin;
  final int reportCount;

  const ProfileAdminReportBadge({
    super.key,
    required this.isAdmin,
    required this.reportCount,
  });

  @override
  Widget build(BuildContext context) {
    if (!isAdmin || reportCount == 0) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final isHigh = reportCount >= 3;
    final badgeColor = isHigh ? AppColors.error : Colors.orange;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.flag, size: 14, color: badgeColor),
                const SizedBox(width: 4),
                Text(
                  '累計被通報: $reportCount回',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileBanWarning extends StatelessWidget {
  final bool showWarning;
  final bool showContactButton;
  final VoidCallback? onContact;

  const ProfileBanWarning({
    super.key,
    required this.showWarning,
    required this.showContactButton,
    this.onContact,
  });

  @override
  Widget build(BuildContext context) {
    if (!showWarning) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.error.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.error,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'アカウントが制限されています。投稿やコメントができません。',
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (showContactButton && onContact != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onContact,
                      icon: const Icon(Icons.support_agent, size: 20),
                      label: const Text('運営へ問い合わせる'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
