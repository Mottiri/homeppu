import 'package:flutter/material.dart';

import '../../../../shared/models/category_model.dart';
import '../../../../shared/models/task_model.dart';
import 'task_card.dart';
import 'task_empty_view.dart';

class TaskListView extends StatelessWidget {
  final List<TaskModel> tasks;
  final String type;
  final CategoryModel? category;
  final DateTime targetDate;
  final bool isEditMode;
  final Set<String> selectedTaskIds;
  final String? highlightTaskId;
  final bool hasScrolledToHighlight;
  final ScrollController scrollController;
  final Animation<double> shakeAnimation;
  final bool isFabVisible;
  final ValueChanged<bool> onFabVisibilityChanged;
  final ValueChanged<TaskModel> onTapTask;
  final ValueChanged<TaskModel> onCompleteTask;
  final ValueChanged<TaskModel> onUncompleteTask;
  final ValueChanged<TaskModel> onDeleteTask;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<TaskModel> onLongPressTask;
  final Future<bool> Function() onConfirmDismiss;
  final VoidCallback onExitEditMode;
  final VoidCallback onDismissHighlight;
  final VoidCallback onHighlightScrolled;

  const TaskListView({
    super.key,
    required this.tasks,
    required this.type,
    required this.category,
    required this.targetDate,
    required this.isEditMode,
    required this.selectedTaskIds,
    required this.highlightTaskId,
    required this.hasScrolledToHighlight,
    required this.scrollController,
    required this.shakeAnimation,
    required this.isFabVisible,
    required this.onFabVisibilityChanged,
    required this.onTapTask,
    required this.onCompleteTask,
    required this.onUncompleteTask,
    required this.onDeleteTask,
    required this.onToggleSelection,
    required this.onLongPressTask,
    required this.onConfirmDismiss,
    required this.onExitEditMode,
    required this.onDismissHighlight,
    required this.onHighlightScrolled,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return TaskEmptyView(
        icon: _emptyIconForType(type),
        message: _emptyMessageForType(type, category),
        onTap: isEditMode ? onExitEditMode : null,
      );
    }

    final sortedTasks = [...tasks];

    final filteredTasks = sortedTasks.where((task) {
      if (task.scheduledAt == null) {
        return _isSameDay(targetDate, DateTime.now());
      }
      return _isSameDay(task.scheduledAt!, targetDate);
    }).toList();

    filteredTasks.sort((a, b) {
      if (a.priority != b.priority) return b.priority - a.priority;
      if (a.scheduledAt != null && b.scheduledAt != null) {
        return a.scheduledAt!.compareTo(b.scheduledAt!);
      }
      return 0;
    });

    if (filteredTasks.isEmpty) {
      return TaskEmptyView(
        icon: Icons.event_available,
        message: 'まだタスクがありません',
        textColor: Colors.grey.shade400,
        onTap: isEditMode ? onExitEditMode : null,
      );
    }

    return GestureDetector(
      onTap: () {
        if (highlightTaskId != null) {
          onDismissHighlight();
        }
        if (isEditMode) {
          onExitEditMode();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification) {
            final scrollDelta = notification.scrollDelta ?? 0;
            if (scrollDelta > 2 && isFabVisible) {
              onFabVisibilityChanged(false);
            } else if (scrollDelta < -2 && !isFabVisible) {
              onFabVisibilityChanged(true);
            }
          }
          return false;
        },
        child: Builder(
          builder: (context) {
            if (highlightTaskId != null && !hasScrolledToHighlight) {
              final highlightIndex = filteredTasks.indexWhere(
                (t) => t.id == highlightTaskId,
              );
              if (highlightIndex >= 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (scrollController.hasClients) {
                    final offset = highlightIndex * 100.0;
                    scrollController.animateTo(
                      offset.clamp(
                        0.0,
                        scrollController.position.maxScrollExtent,
                      ),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                    onHighlightScrolled();
                  }
                });
              }
            }

            return ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.only(bottom: 150),
              itemCount: filteredTasks.length,
              itemBuilder: (context, index) {
                final task = filteredTasks[index];
                return TaskCard(
                  task: task,
                  onTap: () => onTapTask(task),
                  onComplete: () => onCompleteTask(task),
                  onUncomplete: () => onUncompleteTask(task),
                  onDelete: () => onDeleteTask(task),
                  isEditMode: isEditMode,
                  isSelected: selectedTaskIds.contains(task.id),
                  isHighlighted: highlightTaskId == task.id,
                  onDismissHighlight: onDismissHighlight,
                  onToggleSelection: () => onToggleSelection(task.id),
                  onLongPress: () => onLongPressTask(task),
                  shakeAnimation: shakeAnimation,
                  onConfirmDismiss: onConfirmDismiss,
                );
              },
            );
          },
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _emptyMessageForType(String type, CategoryModel? category) {
    if (type == 'daily') {
      return '毎日のタスクを追加しよう！';
    }
    if (type == 'custom') {
      return '${category?.name} のタスクを追加しよう！';
    }
    return 'タスクを追加しよう！';
  }

  IconData _emptyIconForType(String type) {
    if (type == 'daily') {
      return Icons.today;
    }
    if (type == 'custom') {
      return Icons.label_outline;
    }
    return Icons.task_alt;
  }
}
