import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';

class ProfileStats extends StatelessWidget {
  final int totalPosts;
  final int totalPraises;
  final int virtue;
  final int? followingCount;
  final List<String>? followingIds;
  final Color primaryAccent;
  final Color secondaryAccent;
  final bool isVirtueLoading;
  final VoidCallback? onVirtueTap;
  final Key? virtueStatKey;

  const ProfileStats({
    super.key,
    required this.totalPosts,
    required this.totalPraises,
    required this.virtue,
    this.followingCount,
    this.followingIds,
    required this.primaryAccent,
    required this.secondaryAccent,
    this.isVirtueLoading = false,
    this.onVirtueTap,
    this.virtueStatKey,
  });

  @override
  Widget build(BuildContext context) {
    final stats = <Widget>[
      Expanded(
        child: _buildStat(
          label: '投稿',
          value: '$totalPosts',
        ),
      ),
      Container(width: 1, color: Colors.grey.shade300),
      Expanded(
        child: _buildStat(
          label: '称賛',
          value: '$totalPraises',
        ),
      ),
      Container(width: 1, color: Colors.grey.shade300),
      Expanded(
        child: _buildStat(
          label: '徳',
          value: '$virtue',
          isLoading: isVirtueLoading,
          onTap: onVirtueTap,
          wrapperKey: virtueStatKey,
        ),
      ),
    ];

    if (followingCount != null) {
      stats.addAll([
        Container(width: 1, color: Colors.grey.shade300),
        Expanded(
          child: _buildStat(
            label: AppMessages.home.tabFollowing,
            value: '$followingCount',
            onTap: followingIds != null && followingIds!.isNotEmpty
                ? () => context.push('/following', extra: followingIds)
                : null,
          ),
        ),
      ]);
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 8,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                primaryAccent.withValues(alpha: 0.15),
                secondaryAccent.withValues(alpha: 0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: IntrinsicHeight(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: stats,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStat({
    required String label,
    required String value,
    bool isLoading = false,
    VoidCallback? onTap,
    Key? wrapperKey,
  }) {
    final content = SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            if (isLoading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppColors.textSecondary,
                ),
              )
            else
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );

    if (onTap == null) return content;

    return GestureDetector(
      key: wrapperKey,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}
