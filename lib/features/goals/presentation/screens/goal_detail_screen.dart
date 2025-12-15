import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/goal_model.dart';
import '../../../../shared/models/task_model.dart';
import '../../../../shared/services/goal_service.dart';
import '../../../../shared/services/task_service.dart';
import '../../../../shared/providers/goal_provider.dart';

class GoalDetailScreen extends ConsumerStatefulWidget {
  final String goalId;
  const GoalDetailScreen({super.key, required this.goalId});

  @override
  ConsumerState<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends ConsumerState<GoalDetailScreen> {
  final TaskService _taskService = TaskService();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('ログインが必要です')));
    }

    final goalService = ref.read(goalServiceProvider);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: goalService.getGoalStream(widget.goalId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 64,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '目標が見つかりません',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final goal = GoalModel.fromFirestore(snapshot.data!);
        return _buildGoalDetailUI(context, goal, goalService);
      },
    );
  }

  Widget _buildGoalDetailUI(
    BuildContext context,
    GoalModel goal,
    GoalService goalService,
  ) {
    final isCompleted = goal.isCompleted;
    final color = Color(goal.colorValue);
    final daysRemaining = goal.deadline != null
        ? goal.deadline!.difference(DateTime.now()).inDays
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // カスタムAppBar
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: isCompleted
                ? const Color(0xFFFFF8E1)
                : color.withOpacity(0.1),
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_rounded, size: 20),
              ),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: AppColors.error,
                  ),
                ),
                onPressed: () => _confirmDelete(context, goalService),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildHeader(goal, color, isCompleted, daysRemaining),
            ),
          ),

          // コンテンツ
          SliverToBoxAdapter(
            child: Column(
              children: [
                // 達成/再開ボタン
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: isCompleted
                      ? _buildRevertButton(context, goalService, goal)
                      : _buildCompleteButton(context, goalService, goal, color),
                ),

                // タスクセクション
                _buildTaskSection(goal),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    GoalModel goal,
    Color color,
    bool isCompleted,
    int? daysRemaining,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: isCompleted
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF8E1), Color(0xFFFFFBE6)],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
              ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // アイコン
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: isCompleted
                      ? const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFFFC107)],
                        )
                      : LinearGradient(colors: [color, color.withOpacity(0.7)]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isCompleted ? const Color(0xFFFFD700) : color)
                          .withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  isCompleted ? Icons.emoji_events_rounded : Icons.flag_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 16),

              // タイトル
              Text(
                goal.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),

              // 説明
              if (goal.description != null && goal.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  goal.description!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 16),

              // ステータスチップ
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isCompleted && goal.completedAt != null)
                    _buildStatusChip(
                      icon: Icons.check_circle_rounded,
                      label:
                          '${DateFormat('yyyy/MM/dd').format(goal.completedAt!)} 達成',
                      color: AppColors.success,
                    ),
                  if (!isCompleted && daysRemaining != null) ...[
                    _buildDeadlineChip(daysRemaining, color),
                  ],
                  if (goal.deadline != null) ...[
                    const SizedBox(width: 8),
                    _buildStatusChip(
                      icon: Icons.event_rounded,
                      label: DateFormat('yyyy/MM/dd').format(goal.deadline!),
                      color: AppColors.textSecondary,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
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
      chipColor = AppColors.error;
      textColor = Colors.white;
      text = '${-daysRemaining}日超過';
      icon = Icons.warning_amber_rounded;
    } else if (daysRemaining == 0) {
      chipColor = AppColors.warning;
      textColor = Colors.white;
      text = '今日まで！';
      icon = Icons.schedule_rounded;
    } else if (daysRemaining <= 7) {
      chipColor = const Color(0xFFFF6B35);
      textColor = Colors.white;
      text = 'あと$daysRemaining日';
      icon = Icons.timer_outlined;
    } else {
      chipColor = goalColor;
      textColor = Colors.white;
      text = 'あと$daysRemaining日';
      icon = Icons.event_available_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(20),
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
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteButton(
    BuildContext context,
    GoalService service,
    GoalModel goal,
    Color color,
  ) {
    return GestureDetector(
      onTap: () => _toggleComplete(context, service, goal, true),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withBlue((color.blue + 30).clamp(0, 255))],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.emoji_events_rounded, color: Colors.white, size: 24),
            SizedBox(width: 10),
            Text(
              '目標を達成する！',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevertButton(
    BuildContext context,
    GoalService service,
    GoalModel goal,
  ) {
    return OutlinedButton.icon(
      onPressed: () => _toggleComplete(context, service, goal, false),
      icon: const Icon(Icons.undo_rounded),
      label: const Text('未完了に戻す（再開）'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        side: BorderSide(color: AppColors.textHint),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildTaskSection(GoalModel goal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.checklist_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'これまでの積み上げ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),

        StreamBuilder<QuerySnapshot>(
          stream: _taskService.getGoalsTasksStream(goal.id, goal.userId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              );
            }

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return _buildEmptyTasksView();
            }

            final tasks = docs.map((d) => TaskModel.fromFirestore(d)).toList();
            final completedTasks = tasks.where((t) => t.isCompleted).toList();
            final activeTasks = tasks.where((t) => !t.isCompleted).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // アクティブタスク
                if (activeTasks.isNotEmpty) ...[
                  _buildTaskSubHeader(
                    '未完了',
                    activeTasks.length,
                    AppColors.warning,
                  ),
                  ...activeTasks.map((t) => _buildTaskTile(t, false)),
                ],

                // 完了タスク
                if (completedTasks.isNotEmpty) ...[
                  if (activeTasks.isNotEmpty) const SizedBox(height: 8),
                  _buildTaskSubHeader(
                    '完了',
                    completedTasks.length,
                    AppColors.success,
                  ),
                  ...completedTasks.map((t) => _buildTaskTile(t, true)),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmptyTasksView() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.assignment_outlined, size: 48, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(
            'まだタスクがありません',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'タスクを作成して目標に紐づけよう',
            style: TextStyle(fontSize: 12, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskSubHeader(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskTile(TaskModel task, bool isCompleted) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted
              ? AppColors.success.withOpacity(0.2)
              : AppColors.surfaceVariant,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isCompleted
                ? AppColors.success.withOpacity(0.1)
                : AppColors.surfaceVariant,
            shape: BoxShape.circle,
          ),
          child: Icon(
            isCompleted ? Icons.check_rounded : Icons.circle_outlined,
            size: 18,
            color: isCompleted ? AppColors.success : AppColors.textHint,
          ),
        ),
        title: Text(
          task.content,
          style: TextStyle(
            fontSize: 14,
            color: isCompleted
                ? AppColors.textSecondary
                : AppColors.textPrimary,
            decoration: isCompleted ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          DateFormat('MM/dd').format(task.lastCompletedAt ?? task.updatedAt),
          style: TextStyle(fontSize: 11, color: AppColors.textHint),
        ),
        trailing: task.attachmentUrls.isNotEmpty
            ? Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.image_outlined,
                  size: 16,
                  color: AppColors.info,
                ),
              )
            : null,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, GoalService service) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            const SizedBox(width: 8),
            const Text('目標を削除'),
          ],
        ),
        content: const Text('紐づいているすべてのタスクも削除されます。\nこの操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        await service.deleteGoal(widget.goalId, userId);
      }
      // タスク画面を完全に再初期化（削除された関連タスクをUIから反映）
      if (context.mounted) context.go('/tasks', extra: {'forceRefresh': true});
    }
  }

  Future<void> _toggleComplete(
    BuildContext context,
    GoalService service,
    GoalModel goal,
    bool complete,
  ) async {
    if (complete) {
      final shouldDeleteFuture = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFC107)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text('おめでとう！🎉'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('目標を「殿堂入り」にしますか？'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '未来のタスクがあれば削除されます',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.white,
              ),
              child: const Text('殿堂入りへ'),
            ),
          ],
        ),
      );

      if (shouldDeleteFuture == null) return;

      try {
        await service.toggleComplete(
          goal,
          isCompleted: true,
          deleteFutureTasks: shouldDeleteFuture,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: const [
                  Icon(Icons.emoji_events, color: Colors.white),
                  SizedBox(width: 8),
                  Text('おめでとう！目標を達成しました！🎊'),
                ],
              ),
              backgroundColor: const Color(0xFFFFB300),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          // タスク画面を完全に再初期化（削除されたタスクをUIから反映）
          context.go('/tasks', extra: {'forceRefresh': true});
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('目標達成に失敗しました: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      await service.toggleComplete(goal, isCompleted: false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('目標を再開しました'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }
}
