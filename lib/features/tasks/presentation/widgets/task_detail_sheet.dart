import 'package:flutter/material.dart';
import 'package:homeppu/core/constants/app_colors.dart';
import 'package:homeppu/shared/models/task_model.dart'; // Correct import
import 'package:intl/intl.dart';

class TaskDetailSheet extends StatefulWidget {
  final TaskModel task;
  final Function(TaskModel) onUpdate;
  final VoidCallback onDelete;

  const TaskDetailSheet({
    super.key,
    required this.task,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<TaskDetailSheet> {
  late TextEditingController _titleController;
  late int _priority;
  late DateTime? _scheduledAt;
  late List<TaskItem> _subtasks;

  // サブタスク追加用
  final _subtaskController = TextEditingController();
  bool _isAddingSubtask = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.content);
    _priority = widget.task.priority;
    _scheduledAt = widget.task.scheduledAt;
    _subtasks = List.from(widget.task.subtasks);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtaskController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // 変更があれば保存処理
    // 注: 実際の実装ではViewModel経由で部分更新APIを呼ぶか、Task全体を更新する
    // ここでは簡易的にNavigator.popで変更内容を返すか、Providerを直接呼ぶ

    // 今回は変更内容をまとめて返すパターン
    final updatedTask = widget.task.copyWith(
      content: _titleController.text.trim(),
      priority: _priority,
      scheduledAt: _scheduledAt,
      subtasks: _subtasks,
    );

    // コールバック経由で更新
    widget.onUpdate(updatedTask);

    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteTask() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('タスクの削除'),
        content: const Text('このタスクを削除してもよろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      widget.onDelete();
      if (mounted) Navigator.pop(context);
    }
  }

  void _addSubtask() {
    final title = _subtaskController.text.trim();
    if (title.isEmpty) return;

    setState(() {
      _subtasks.add(
        TaskItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(), // 簡易ID
          title: title,
          isCompleted: false,
        ),
      );
      _subtaskController.clear();
      _isAddingSubtask = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ヘッダー: タイトル編集と閉じるボタン
          Row(
            children: [
              // 優先度アイコン（タップで変更）
              GestureDetector(
                onTap: () {
                  setState(() => _priority = (_priority + 1) % 3);
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _priority == 2
                        ? Colors.red[50]
                        : (_priority == 1
                              ? Colors.orange[50]
                              : Colors.green[50]),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _priority == 2 ? '🔴' : (_priority == 1 ? '🟡' : '🟢'),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(border: InputBorder.none),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Divider(),

          // 日付設定
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text(
              _scheduledAt == null
                  ? '日時を設定'
                  : DateFormat('yyyy/MM/dd HH:mm').format(_scheduledAt!),
            ),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _scheduledAt ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null && mounted) {
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(
                    _scheduledAt ?? DateTime.now(),
                  ),
                );
                if (time != null) {
                  setState(() {
                    _scheduledAt = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                  });
                }
              }
            },
          ),

          const SizedBox(height: 16),
          const Text(
            'サブタスク',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),

          // サブタスクリスト
          ..._subtasks.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return CheckboxListTile(
              value: item.isCompleted,
              title: Text(
                item.title,
                style: TextStyle(
                  decoration: item.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                  color: item.isCompleted ? Colors.grey : Colors.black,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              secondary: IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  setState(() {
                    _subtasks.removeAt(index);
                  });
                },
              ),
              onChanged: (bool? val) {
                setState(() {
                  _subtasks[index] = item.copyWith(isCompleted: val);
                });
              },
            );
          }).toList(),

          // サブタスク追加エリア
          if (_isAddingSubtask)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subtaskController,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'サブタスクを入力'),
                    onSubmitted: (_) => _addSubtask(),
                  ),
                ),
                IconButton(
                  onPressed: _addSubtask,
                  icon: const Icon(Icons.check, color: AppColors.primary),
                ),
              ],
            )
          else
            TextButton.icon(
              onPressed: () => setState(() => _isAddingSubtask = true),
              icon: const Icon(Icons.add),
              label: const Text('サブタスクを追加'),
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
            ),

          const SizedBox(height: 24),

          // アクションボタン
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _deleteTask,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('削除', style: TextStyle(color: Colors.red)),
              ),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('保存'),
              ),
            ],
          ),
          // キーボード対策の余白
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }
}
