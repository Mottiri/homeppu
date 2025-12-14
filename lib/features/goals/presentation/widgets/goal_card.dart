import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/goal_model.dart';

/// 美しくリデザインされた目標カードウィジェット
class GoalCard extends StatelessWidget {
  final GoalModel goal;
  final bool isArchived;
  final VoidCallback? onTap;
  final int completedTaskCount;
  final int totalTaskCount;

  const GoalCard({
    super.key,
    required this.goal,
    this.isArchived = false,
    this.onTap,
    this.completedTaskCount = 0,
    this.totalTaskCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final goalColor = Color(goal.colorValue);
    final daysRemaining = goal.deadline != null
        ? goal.deadline!.difference(DateTime.now()).inDays
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: isArchived
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFFFFBE6), // 淡いゴールド
                        const Color(0xFFFFF8E1),
                      ],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, goalColor.withOpacity(0.05)],
                    ),
              border: Border.all(
                color: isArchived
                    ? const Color(0xFFFFD700).withOpacity(0.5)
                    : goalColor.withOpacity(0.2),
                width: isArchived ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isArchived
                      ? const Color(0xFFFFD700).withOpacity(0.15)
                      : goalColor.withOpacity(0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // 左側: プログレスサークル
                  _buildProgressCircle(goalColor),

                  const SizedBox(width: 16),

                  // 中央: コンテンツ
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // タイトル行
                        Row(
                          children: [
                            if (isArchived)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.emoji_events_rounded,
                                  size: 18,
                                  color: const Color(0xFFFFB300),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                goal.title,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isArchived
                                      ? AppColors.textSecondary
                                      : AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        // 説明
                        if (goal.description != null &&
                            goal.description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            goal.description!,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],

                        const SizedBox(height: 8),

                        // 期限チップとタスク統計
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (daysRemaining != null && !isArchived)
                              _buildDeadlineChip(daysRemaining, goalColor),
                            if (totalTaskCount > 0 && !isArchived)
                              _buildTaskStatsChip(goalColor),
                          ],
                        ),

                        // 達成日（アーカイブ済み）
                        if (isArchived && goal.completedAt != null)
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 14,
                                color: AppColors.success,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${DateFormat('yyyy/MM/dd').format(goal.completedAt!)} 達成',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  // 右側: 矢印
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isArchived
                        ? AppColors.textHint
                        : goalColor.withOpacity(0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressCircle(Color color) {
    // タスク完了率を計算
    final progress = totalTaskCount > 0
        ? completedTaskCount / totalTaskCount
        : 0.0;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isArchived
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFFFFD700), const Color(0xFFFFC107)],
              )
            : null,
        color: isArchived ? null : color.withOpacity(0.1),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!isArchived)
            SizedBox(
              width: 52,
              height: 52,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 4,
                backgroundColor: color.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          Icon(
            isArchived ? Icons.emoji_events_rounded : Icons.flag_rounded,
            size: 24,
            color: isArchived ? Colors.white : color,
          ),
        ],
      ),
    );
  }

  Widget _buildTaskStatsChip(Color goalColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: goalColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checklist_rounded, size: 14, color: goalColor),
          const SizedBox(width: 4),
          Text(
            '$completedTaskCount / $totalTaskCount',
            style: TextStyle(
              fontSize: 12,
              color: goalColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeadlineChip(int daysRemaining, Color goalColor) {
    Color chipColor;
    Color textColor;
    String text;
    IconData icon;

    if (daysRemaining < 0) {
      // 期限切れ
      chipColor = AppColors.error.withOpacity(0.1);
      textColor = AppColors.error;
      text = '${-daysRemaining}日超過';
      icon = Icons.warning_amber_rounded;
    } else if (daysRemaining == 0) {
      // 今日
      chipColor = AppColors.warning.withOpacity(0.2);
      textColor = AppColors.warning;
      text = '今日まで';
      icon = Icons.schedule_rounded;
    } else if (daysRemaining <= 7) {
      // 1週間以内
      chipColor = AppColors.warning.withOpacity(0.1);
      textColor = const Color(0xFFE65100);
      text = 'あと$daysRemaining日';
      icon = Icons.timer_outlined;
    } else {
      // 余裕あり
      chipColor = goalColor.withOpacity(0.1);
      textColor = goalColor;
      text = 'あと$daysRemaining日';
      icon = Icons.event_available_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
