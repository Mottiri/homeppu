import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:homeppu/core/constants/app_colors.dart';
import '../../../../shared/models/task_model.dart';

class TaskCard extends StatefulWidget {
  final TaskModel task;
  final VoidCallback onComplete;
  final VoidCallback onUncomplete;
  final VoidCallback onDelete;
  final VoidCallback onTap; // 詳細を開く

  // Edit Mode Props
  final bool isEditMode;
  final bool isSelected;
  final VoidCallback onToggleSelection;
  final VoidCallback onLongPress;
  final Animation<double>? shakeAnimation;
  final Future<bool> Function()? onConfirmDismiss;

  const TaskCard({
    super.key,
    required this.task,
    required this.onComplete,
    required this.onUncomplete,
    required this.onDelete,
    required this.onTap,
    this.isEditMode = false,
    this.isSelected = false,
    required this.onToggleSelection,
    required this.onLongPress,
    this.shakeAnimation,
    this.onConfirmDismiss,
  });

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _completeController;
  late Animation<double> _scaleAnimation;
  bool _isProcessing = false;

  // Random shake parameters
  late final double _randomAmplitude;
  late final int _randomDirection;

  @override
  void initState() {
    super.initState();
    _completeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _completeController, curve: Curves.easeInOut),
    );

    // Randomize shake
    final random = Random();
    _randomDirection = random.nextBool() ? 1 : -1;
    // 0.5 ~ 1.5倍の振れ幅
    _randomAmplitude = 0.5 + random.nextDouble();
  }

  @override
  void didUpdateWidget(TaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.isCompleted != oldWidget.task.isCompleted ||
        widget.task.isCompletedToday != oldWidget.task.isCompletedToday) {
      // 状態が変わったらローディング解除
      if (_isProcessing) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  void dispose() {
    _completeController.dispose();
    super.dispose();
  }

  Future<void> _handleComplete() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    await _completeController.forward();
    await _completeController.reverse();

    widget.onComplete();
  }

  Future<void> _handleUncomplete() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    widget.onUncomplete();
  }

  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 2:
        return Colors.red.shade100;
      case 1:
        return Colors.orange.shade100;
      default:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompletedToday =
        widget.task.isCompletedToday ||
        (widget.task.isGoal && widget.task.isCompleted) ||
        (widget.task.isTodo && widget.task.isCompleted);

    // 期限表示用
    String dateLabel = '';
    if (widget.task.scheduledAt != null) {
      final now = DateTime.now();
      final diff = widget.task.scheduledAt!.difference(now).inDays;
      if (diff == 0) {
        dateLabel = '今日 ${DateFormat('H:mm').format(widget.task.scheduledAt!)}';
      } else if (diff == 1) {
        dateLabel = '明日 ${DateFormat('H:mm').format(widget.task.scheduledAt!)}';
      } else {
        dateLabel = DateFormat('M/d H:mm').format(widget.task.scheduledAt!);
      }
    }

    // 編集モード中の背景色
    Color getBackgroundColor() {
      if (widget.isEditMode && widget.isSelected) {
        return Colors.red.shade50;
      }
      return isCompletedToday ? Colors.green.shade50 : Colors.white;
    }

    Widget contentCallback() {
      return GestureDetector(
        onLongPress: widget.onLongPress, // 編集モード開始
        onTap: widget.isEditMode ? widget.onToggleSelection : widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: getBackgroundColor(),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(13),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
            // 選択中のボーダー
            border: widget.isEditMode && widget.isSelected
                ? Border.all(color: Colors.red.shade300, width: 2)
                : (widget.task.priority > 0 && !isCompletedToday
                      ? Border.all(
                          color: _getPriorityColor(
                            widget.task.priority,
                          ).withAlpha(255),
                          width: 2,
                        )
                      : (isCompletedToday
                            ? Border.all(
                                color: Colors.green.shade300,
                                width: 1.5,
                              )
                            : null)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 左側のボタン (編集モードのみ表示)
                if (widget.isEditMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: widget.onToggleSelection,
                      child: SizedBox(
                        width: 24, // Matches checkbox size
                        height: 24,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: widget.isSelected
                                ? AppColors.primary
                                : Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: widget.isSelected
                                  ? AppColors.primary
                                  : Colors.grey.shade400,
                              width: 2,
                            ),
                          ),
                          child: widget.isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),

                // 中央の情報エリア
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.task.emoji} ${widget.task.content}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          decoration: isCompletedToday
                              ? TextDecoration.lineThrough
                              : null,
                          color: isCompletedToday
                              ? Colors.grey
                              : Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // 連続達成バッジ
                          if (widget.task.streak > 0)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withAlpha(25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.local_fire_department,
                                    size: 12,
                                    color: Colors.orange.shade700,
                                  ),
                                  Text(
                                    ' ${widget.task.streak}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade800,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // 優先度アイコン（中以上のみ）
                          if (widget.task.priority > 0 && !isCompletedToday)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                widget.task.priority == 2 ? '🔴' : '🟡',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),

                          // 期限表示
                          if (dateLabel.isNotEmpty && !isCompletedToday)
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  dateLabel,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ),

                          // サブタスク進捗
                          if (widget.task.subtasks.isNotEmpty)
                            Row(
                              children: [
                                Icon(
                                  Icons.checklist,
                                  size: 14,
                                  color: widget.task.progress == 1.0
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${widget.task.completedSubtaskCount}/${widget.task.subtasks.length}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 右側の完了ボタン (編集モード以外)
                if (!widget.isEditMode) ...[
                  const SizedBox(width: 8),
                  if (_isProcessing)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (isCompletedToday)
                    IconButton(
                      icon: Icon(
                        Icons.check_circle,
                        color: Colors.green.shade600,
                        size: 32,
                      ),
                      onPressed: _handleUncomplete,
                      tooltip: '完了を取り消す',
                    )
                  else
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0, // Compact height
                        ),
                        minimumSize: const Size(60, 32), // Smaller height
                        elevation: 0,
                      ),
                      onPressed: _handleComplete,
                      child: const Text(
                        '完了',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    Widget cardWithAnimation =
        widget.shakeAnimation != null && widget.isEditMode
        ? AnimatedBuilder(
            animation: widget.shakeAnimation!,
            builder: (context, child) {
              // Apply random amplitude and direction
              final angle =
                  widget.shakeAnimation!.value *
                  _randomAmplitude *
                  _randomDirection;
              return Transform.rotate(angle: angle, child: child);
            },
            child: contentCallback(),
          )
        : ScaleTransition(scale: _scaleAnimation, child: contentCallback());

    return Dismissible(
      key: Key(widget.task.id),
      direction: DismissDirection.none, // スワイプ削除を無効化（編集モードでもページ移動を優先）
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        print(
          'Deleting task: ${widget.task.content} (ID: ${widget.task.id})',
        ); // Debug
        if (widget.onConfirmDismiss != null) {
          return await widget.onConfirmDismiss!();
        }
        return true; // Default behavior
      },
      onDismissed: (_) => widget.onDelete(),
      child: cardWithAnimation,
    );
  }
}
