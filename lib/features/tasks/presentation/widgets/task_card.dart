import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../shared/models/task_model.dart';

class TaskCard extends StatefulWidget {
  final TaskModel task;
  final VoidCallback onComplete;
  final VoidCallback onUncomplete;
  final VoidCallback onDelete;
  final VoidCallback onTap; // 詳細を開く

  const TaskCard({
    super.key,
    required this.task,
    required this.onComplete,
    required this.onUncomplete,
    required this.onDelete,
    required this.onTap,
  });

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleComplete() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    await _controller.forward();
    await _controller.reverse();

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

    return Dismissible(
      key: Key(widget.task.id),
      direction: DismissDirection.endToStart,
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
        // スワイプ削除確認は親側で行うか、ここで行うか。
        // タップで詳細が開くので、スワイプ削除は「サクッと削除」として残す
        return true;
      },
      onDismissed: (_) => widget.onDelete(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GestureDetector(
          onTap: widget.onTap, // カード全体タップで詳細
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              // 優先度に応じて背景色を微調整、またはボーダー
              color: isCompletedToday ? Colors.green.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(13),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
              border: widget.task.priority > 0 && !isCompletedToday
                  ? Border.all(
                      color: _getPriorityColor(
                        widget.task.priority,
                      ).withOpacity(1),
                      width: 2,
                    )
                  : (isCompletedToday
                        ? Border.all(color: Colors.green.shade300, width: 1.5)
                        : null),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // 左側の完了ボタン
                  GestureDetector(
                    onTap: isCompletedToday || _isProcessing
                        ? null
                        : _handleComplete,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _isProcessing
                            ? Colors.orange.shade50
                            : isCompletedToday
                            ? Colors.green.shade100
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: _isProcessing
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.orange.shade600,
                                ),
                              )
                            : isCompletedToday
                            ? Icon(
                                Icons.check_circle,
                                color: Colors.green.shade600,
                                size: 28,
                              )
                            : Text(
                                widget.task.emoji,
                                style: const TextStyle(fontSize: 24),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 中央の情報エリア
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.task.content,
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
                                  color: Colors.orange.withOpacity(0.1),
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

                  // 右側のステータス/完了解除
                  if (isCompletedToday && !_isProcessing)
                    GestureDetector(
                      onTap: _handleUncomplete,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.5),
                          ),
                        ),
                        child: const Text(
                          '戻す',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  if (!isCompletedToday)
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
