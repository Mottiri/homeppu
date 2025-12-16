import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/goal_model.dart';
import '../../../../shared/models/task_model.dart';
import '../../../../shared/services/task_service.dart';

/// 目標カードにタスク一覧を表示するウィジェット
class GoalCardWithStats extends StatefulWidget {
  final GoalModel goal;
  final bool isArchived;
  final bool isReorderMode; // 並び替えモード（タスク非表示）
  final VoidCallback? onDetailTap; // 詳細画面への遷移用

  const GoalCardWithStats({
    super.key,
    required this.goal,
    this.isArchived = false,
    this.isReorderMode = false,
    this.onDetailTap,
  });

  @override
  State<GoalCardWithStats> createState() => _GoalCardWithStatsState();
}

class _GoalCardWithStatsState extends State<GoalCardWithStats> {
  static final TaskService _taskService = TaskService();

  // カード展開状態
  bool _isCardExpanded = true;

  // 展開されているタスクのID
  final Set<String> _expandedTaskIds = {};

  // タスク完了/未完了を切り替え
  Future<void> _toggleTaskCompletion(TaskModel task) async {
    try {
      if (task.isCompleted) {
        await _taskService.uncompleteTask(task.id);
      } else {
        await _taskService.completeTask(task.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    }
  }

  // サブタスク完了/未完了を切り替え
  Future<void> _toggleSubtaskCompletion(
    TaskModel task,
    TaskItem subtask,
  ) async {
    try {
      final updatedSubtasks = task.subtasks.map((s) {
        if (s.id == subtask.id) {
          return s.copyWith(isCompleted: !s.isCompleted);
        }
        return s;
      }).toList();

      final updatedTask = task.copyWith(subtasks: updatedSubtasks);
      await _taskService.updateTask(updatedTask);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    }
  }

  // タスク画面へ遷移（該当日付＋タスクハイライト）
  void _navigateToTask(TaskModel task) {
    context.go(
      '/tasks',
      extra: {
        'highlightTaskId': task.id,
        'targetDate': task.scheduledAt ?? DateTime.now(),
      },
    );
  }

  // 日付をフォーマット
  String _formatTaskDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final taskDate = DateTime(date.year, date.month, date.day);
    final diff = taskDate.difference(today).inDays;

    if (diff == 0) {
      return '今日';
    } else if (diff == 1) {
      return '明日';
    } else if (diff == -1) {
      return '昨日';
    } else if (diff > 0 && diff < 7) {
      return '${diff}日後';
    } else {
      return DateFormat('M/d').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goalColor = Color(widget.goal.colorValue);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: StreamBuilder<QuerySnapshot>(
        key: ValueKey('goal_tasks_${widget.goal.id}'),
        stream: _taskService.getGoalsTasksStream(
          widget.goal.id,
          widget.goal.userId,
        ),
        builder: (context, taskSnapshot) {
          List<TaskModel> tasks = [];
          int completedCount = 0;
          int totalCount = 0;

          if (taskSnapshot.hasData) {
            final allTasks = taskSnapshot.data!.docs
                .map((d) => TaskModel.fromFirestore(d))
                .toList();

            // 繰り返しタスクをフィルタリング：直近の未完了タスクのみ表示
            final Map<String, TaskModel> recurringGroupNearest = {};
            final List<TaskModel> displayTasks = [];

            for (final task in allTasks) {
              if (task.recurrenceGroupId != null) {
                // 繰り返しタスク：グループごとに直近の未完了タスクを選択
                final groupId = task.recurrenceGroupId!;
                final existing = recurringGroupNearest[groupId];

                if (existing == null) {
                  recurringGroupNearest[groupId] = task;
                } else {
                  // 未完了を優先、同じ完了状態なら日付が近い方を優先
                  final existingCompleted = existing.isCompleted;
                  final taskCompleted = task.isCompleted;

                  if (!taskCompleted && existingCompleted) {
                    // 未完了を優先
                    recurringGroupNearest[groupId] = task;
                  } else if (taskCompleted == existingCompleted) {
                    // 同じ完了状態なら日付が近い（scheduledAtが小さい）方
                    final existingDate = existing.scheduledAt ?? DateTime.now();
                    final taskDate = task.scheduledAt ?? DateTime.now();
                    if (taskDate.isBefore(existingDate)) {
                      recurringGroupNearest[groupId] = task;
                    }
                  }
                }
              } else {
                // 非繰り返しタスクはそのまま表示
                displayTasks.add(task);
              }
            }

            // 繰り返しグループの代表タスクを追加
            displayTasks.addAll(recurringGroupNearest.values);

            // ソート：未完了タスクを先に、完了タスクを後に
            displayTasks.sort((a, b) {
              if (a.isCompleted != b.isCompleted) {
                return a.isCompleted ? 1 : -1;
              }
              return b.priority.compareTo(a.priority);
            });

            tasks = displayTasks;
            totalCount = allTasks.length; // 全タスク数（プログレス計算用）
            completedCount = allTasks.where((t) => t.isCompleted).length;
          }

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: widget.isArchived
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFFFFBE6),
                        const Color(0xFFFFF8E1),
                      ],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, goalColor.withOpacity(0.08)],
                    ),
              border: Border.all(
                color: widget.isArchived
                    ? const Color(0xFFFFD700).withOpacity(0.5)
                    : goalColor.withOpacity(0.3),
                width: widget.isArchived ? 2 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.isArchived
                      ? const Color(0xFFFFD700).withOpacity(0.15)
                      : goalColor.withOpacity(0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ヘッダー部分（タップで詳細画面へ）
                _buildHeader(goalColor, completedCount, totalCount),

                // タスク一覧（展開時のみ表示、並び替えモード時は非表示）
                if (!widget.isReorderMode &&
                    _isCardExpanded &&
                    tasks.isNotEmpty &&
                    !widget.isArchived) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(
                      color: goalColor.withOpacity(0.2),
                      height: 1,
                    ),
                  ),
                  _buildTaskList(tasks, goalColor),
                ],

                // タスクがない場合
                if (tasks.isEmpty && !widget.isArchived)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Text(
                      'タスクを追加してください',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textHint,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(Color goalColor, int completedCount, int totalCount) {
    final daysRemaining = widget.goal.deadline != null
        ? widget.goal.deadline!.difference(DateTime.now()).inDays
        : null;
    final progress = totalCount > 0 ? completedCount / totalCount : 0.0;

    return InkWell(
      onTap: () => setState(() => _isCardExpanded = !_isCardExpanded),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // プログレスサークル
            _buildProgressCircle(goalColor, progress),
            const SizedBox(width: 16),

            // コンテンツ
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // タイトル
                  Row(
                    children: [
                      if (widget.isArchived)
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
                          widget.goal.title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: widget.isArchived
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
                  if (widget.goal.description != null &&
                      widget.goal.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.goal.description!,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 8),

                  // チップエリア
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (daysRemaining != null && !widget.isArchived)
                        _buildDeadlineChip(daysRemaining, goalColor),
                      if (totalCount > 0)
                        _buildTaskStatsChip(
                          completedCount,
                          totalCount,
                          goalColor,
                        ),
                      if (widget.goal.reminders.isNotEmpty &&
                          !widget.isArchived)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: goalColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.notifications_active_outlined,
                            size: 14,
                            color: goalColor,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // 展開/折りたたみアイコン + 詳細ボタン
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 詳細画面へ（長押しまたはダブルタップ）
                GestureDetector(
                  onTap: widget.onDetailTap,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: goalColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: goalColor,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 展開/折りたたみ
                Icon(
                  _isCardExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: widget.isArchived
                      ? AppColors.textHint
                      : goalColor.withOpacity(0.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCircle(Color color, double progress) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: widget.isArchived
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFFFFD700), const Color(0xFFFFC107)],
              )
            : null,
        color: widget.isArchived ? null : color.withOpacity(0.1),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!widget.isArchived)
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
            widget.isArchived ? Icons.emoji_events_rounded : Icons.flag_rounded,
            size: 24,
            color: widget.isArchived ? Colors.white : color,
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(List<TaskModel> tasks, Color goalColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: tasks.map((task) => _buildTaskItem(task, goalColor)).toList(),
      ),
    );
  }

  Widget _buildTaskItem(TaskModel task, Color goalColor) {
    final isExpanded = _expandedTaskIds.contains(task.id);
    final hasSubtasks = task.subtasks.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: task.isCompleted ? Colors.grey.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: task.isCompleted
              ? Colors.grey.shade300
              : goalColor.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          // タスクヘッダー（タップでタスク画面へ遷移）
          InkWell(
            onTap: () => _navigateToTask(task),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // 完了状態アイコン（タップで完了切り替え）
                  GestureDetector(
                    onTap: () => _toggleTaskCompletion(task),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: task.isCompleted
                            ? AppColors.success
                            : Colors.transparent,
                        border: Border.all(
                          color: task.isCompleted
                              ? AppColors.success
                              : goalColor.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      child: task.isCompleted
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // タスクタイトル
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            task.content,
                            style: TextStyle(
                              fontSize: 14,
                              color: task.isCompleted
                                  ? AppColors.textHint
                                  : AppColors.textPrimary,
                              decoration: task.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: isExpanded ? null : 1,
                            overflow: isExpanded ? null : TextOverflow.ellipsis,
                          ),
                        ),
                        // 繰り返しアイコン
                        if (task.recurrenceGroupId != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.repeat,
                              size: 14,
                              color: goalColor.withOpacity(0.7),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // 日付表示
                  if (task.scheduledAt != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        _formatTaskDate(task.scheduledAt!),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),

                  // サブタスク展開アイコン（タップで展開）
                  if (hasSubtasks) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() {
                        if (isExpanded) {
                          _expandedTaskIds.remove(task.id);
                        } else {
                          _expandedTaskIds.add(task.id);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: goalColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${task.subtasks.where((s) => s.isCompleted).length}/${task.subtasks.length}',
                              style: TextStyle(
                                fontSize: 11,
                                color: goalColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 16,
                              color: goalColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // サブタスク一覧（展開時）
          if (isExpanded && hasSubtasks) _buildSubtaskList(task, goalColor),
        ],
      ),
    );
  }

  Widget _buildSubtaskList(TaskModel task, Color goalColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(44, 0, 12, 12),
      child: Column(
        children: task.subtasks.map((subtask) {
          return GestureDetector(
            onTap: () => _toggleSubtaskCompletion(task, subtask),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: subtask.isCompleted
                          ? goalColor.withOpacity(0.7)
                          : Colors.transparent,
                      border: Border.all(
                        color: subtask.isCompleted
                            ? goalColor.withOpacity(0.7)
                            : goalColor.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: subtask.isCompleted
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      subtask.title,
                      style: TextStyle(
                        fontSize: 13,
                        color: subtask.isCompleted
                            ? AppColors.textHint
                            : AppColors.textSecondary,
                        decoration: subtask.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDeadlineChip(int daysRemaining, Color goalColor) {
    Color chipColor;
    Color textColor;
    String text;
    IconData icon;

    if (daysRemaining < 0) {
      chipColor = AppColors.error.withOpacity(0.1);
      textColor = AppColors.error;
      text = '${-daysRemaining}日超過';
      icon = Icons.warning_amber_rounded;
    } else if (daysRemaining == 0) {
      chipColor = AppColors.warning.withOpacity(0.2);
      textColor = AppColors.warning;
      text = '今日まで';
      icon = Icons.schedule_rounded;
    } else if (daysRemaining <= 7) {
      chipColor = AppColors.warning.withOpacity(0.1);
      textColor = const Color(0xFFE65100);
      text = 'あと$daysRemaining日';
      icon = Icons.timer_outlined;
    } else {
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

  Widget _buildTaskStatsChip(int completed, int total, Color goalColor) {
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
            '$completed / $total',
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
}
