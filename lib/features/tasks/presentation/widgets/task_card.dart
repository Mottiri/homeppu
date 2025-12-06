import 'package:flutter/material.dart';
import '../../../../shared/models/task_model.dart';

class TaskCard extends StatefulWidget {
  final TaskModel task;
  final VoidCallback onComplete;
  final VoidCallback onUncomplete;
  final VoidCallback onDelete;

  const TaskCard({
    super.key,
    required this.task,
    required this.onComplete,
    required this.onUncomplete,
    required this.onDelete,
  });

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isCompleting = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleComplete() async {
    if (_isCompleting) return;
    setState(() => _isCompleting = true);

    await _controller.forward();
    await _controller.reverse();

    widget.onComplete();
    setState(() => _isCompleting = false);
  }

  @override
  Widget build(BuildContext context) {
    final isCompletedToday = widget.task.isCompletedToday ||
        (widget.task.isGoal && widget.task.isCompleted);

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
      onDismissed: (_) => widget.onDelete(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isCompletedToday ? Colors.green.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(13),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
            border: isCompletedToday
                ? Border.all(color: Colors.green.shade300, width: 1.5)
                : null,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: GestureDetector(
              onTap: isCompletedToday ? null : _handleComplete,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isCompletedToday
                      ? Colors.green.shade100
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: isCompletedToday
                      ? Icon(Icons.check_circle, color: Colors.green.shade600, size: 28)
                      : Text(
                          widget.task.emoji,
                          style: const TextStyle(fontSize: 24),
                        ),
                ),
              ),
            ),
            title: Text(
              widget.task.content,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                decoration: isCompletedToday ? TextDecoration.lineThrough : null,
                color: isCompletedToday ? Colors.grey : Colors.black87,
              ),
            ),
            subtitle: widget.task.streak > 0
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.local_fire_department,
                            size: 16, color: Colors.orange.shade600),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.task.streak}日連続',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
            trailing: isCompletedToday
                ? GestureDetector(
                    onTap: widget.onUncomplete,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green.shade700,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '完了',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : IconButton(
                    icon: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.check,
                        color: Theme.of(context).primaryColor,
                        size: 20,
                      ),
                    ),
                    onPressed: _handleComplete,
                  ),
          ),
        ),
      ),
    );
  }
}


