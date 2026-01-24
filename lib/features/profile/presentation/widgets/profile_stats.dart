import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

class ProfileStats extends StatelessWidget {
  final int totalPosts;
  final int totalPraises;
  final int virtue;
  final Color primaryAccent;
  final Color secondaryAccent;

  const ProfileStats({
    super.key,
    required this.totalPosts,
    required this.totalPraises,
    required this.virtue,
    required this.primaryAccent,
    required this.secondaryAccent,
  });

  @override
  Widget build(BuildContext context) {
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
              children: [
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
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStat({required String label, required String value}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
