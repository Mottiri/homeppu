import 'package:flutter/material.dart';
import 'package:homeppu/core/constants/app_colors.dart';
import 'package:homeppu/shared/models/task_model.dart';
import 'package:homeppu/features/tasks/presentation/widgets/recurrence_settings_sheet.dart';
import 'package:intl/intl.dart';

class TaskDetailSheet extends StatefulWidget {
  final TaskModel task;
  final Function(TaskModel, String) onUpdate;
  final Function({bool deleteAll}) onDelete;

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

  // Recurrence State
  int? _recurrenceInterval;
  String? _recurrenceUnit;
  List<int>? _recurrenceDaysOfWeek;
  DateTime? _recurrenceEndDate;

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
    _recurrenceInterval = widget.task.recurrenceInterval;
    _recurrenceUnit = widget.task.recurrenceUnit;
    _recurrenceDaysOfWeek = widget.task.recurrenceDaysOfWeek != null
        ? List.from(widget.task.recurrenceDaysOfWeek!)
        : null;
    _recurrenceEndDate = widget.task.recurrenceEndDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtaskController.dispose();
    super.dispose();
  }

  void _notifyUpdate([String editMode = 'single']) {
    // 変更内容を親に通知（保存）
    final updatedTask = widget.task.copyWith(
      content: _titleController.text.trim(),
      priority: _priority,
      scheduledAt: _scheduledAt,
      subtasks: _subtasks,
      recurrenceInterval: _recurrenceInterval,
      recurrenceUnit: _recurrenceUnit,
      recurrenceDaysOfWeek: _recurrenceDaysOfWeek,
      recurrenceEndDate: _recurrenceEndDate,
    );
    widget.onUpdate(updatedTask, editMode);
  }

  Future<void> _deleteTask() async {
    if (widget.task.recurrenceGroupId == null) {
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
        widget.onDelete(deleteAll: false);
        if (mounted) Navigator.pop(context);
      }
    } else {
      // 繰り返しタスクの場合
      final deleteMode = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('繰り返しタスクの削除'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'single'),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('このタスクのみ削除'),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'future'),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('これ以降のタスクも削除', style: TextStyle(color: Colors.red)),
              ),
            ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('キャンセル', style: TextStyle(color: Colors.grey)),
              ),
            ),
          ],
        ),
      );

      if (deleteMode == 'single') {
        widget.onDelete(deleteAll: false);
        if (mounted) Navigator.pop(context);
      } else if (deleteMode == 'future') {
        widget.onDelete(deleteAll: true);
        if (mounted) Navigator.pop(context);
      }
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

  String _getRecurrenceText() {
    if (_recurrenceUnit == null) return '繰り返さない';
    final unitLabel = {
      'daily': '日',
      'weekly': '週',
      'monthly': 'ヶ月',
      'yearly': '年',
    }[_recurrenceUnit];

    String text = '$_recurrenceInterval$unitLabelごとに繰り返し';

    if (_recurrenceUnit == 'weekly' &&
        _recurrenceDaysOfWeek != null &&
        _recurrenceDaysOfWeek!.isNotEmpty) {
      final days = ['日', '月', '火', '水', '木', '金', '土'];
      // recurrenceDaysOfWeek: 1=Mon...7=Sun.
      // days index: 0=Sun...6=Sat.
      // Map 1->1(Mon), 7->0(Sun).
      final sortedDays = List<int>.from(_recurrenceDaysOfWeek!)..sort();
      final dayStr = sortedDays.map((d) => days[d == 7 ? 0 : d]).join('・');
      text += ' ($dayStr)';
    }

    if (_recurrenceEndDate != null) {
      text += '\n終了: ${DateFormat('yyyy/MM/dd').format(_recurrenceEndDate!)}';
    }

    return text;
  }

  Future<void> _showRecurrenceSettings() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RecurrenceSettingsSheet(
        initialInterval: _recurrenceInterval ?? 1,
        initialUnit: _recurrenceUnit ?? 'weekly',
        initialDaysOfWeek: _recurrenceDaysOfWeek,
        initialEndDate: _recurrenceEndDate,
        startDate: _scheduledAt,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _recurrenceInterval = result['interval'];
        _recurrenceUnit = result['unit'];
        _recurrenceDaysOfWeek = result['daysOfWeek'];
        _recurrenceEndDate = result['endDate'];
      });
      // 即座に保存した方が良いかどうかは_notifyUpdateの戦略次第だが、現状はPopScopeがカバーしている。
      // しかし、ユーザーが「完了」を押して戻ってきた時点でUI反映はOK。
      // Pop時に保存される。
    }
  }

  @override
  Widget build(BuildContext context) {
    // コンテンツの高さ（キーボード考慮）
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      canPop: false, // 手動制御
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 変更がない場合はそのまま閉じる
        if (!_hasChanges()) {
          Navigator.pop(context);
          return;
        }

        // 繰り返しタスクでなければそのまま保存して閉じる
        if (widget.task.recurrenceGroupId == null) {
          _notifyUpdate('single');
          Navigator.pop(context);
          return;
        }

        // 繰り返しタスクの場合、更新範囲を確認
        final editMode = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('繰り返しタスクの変更'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'single'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('このタスクのみ変更'),
                ),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'future'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('これ以降のタスクも変更'),
                ),
              ),
              const Divider(),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('キャンセル', style: TextStyle(color: Colors.grey)),
                ),
              ),
            ],
          ),
        );

        if (editMode == 'cancel' || editMode == null) {
          // キャンセルなら閉じない
          return;
        }

        _notifyUpdate(editMode);
        if (mounted) Navigator.pop(context);
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        // フルスクリーンではなく、内容に応じた高さにするが、キーボード分は確保
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Stack(
          children: [
            // メインコンテンツ (スクロール可能)
            Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: SafeArea(
                bottom: false, // viewInsets handles bottom
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    24,
                    24,
                    24,
                    80,
                  ), // Extra bottom padding
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ヘッダー: タイトル編集とアクション
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 優先度
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: GestureDetector(
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
                                  _priority == 2
                                      ? '🔴'
                                      : (_priority == 1 ? '🟡' : '🟢'),
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // タイトル
                          Expanded(
                            child: TextField(
                              controller: _titleController,
                              maxLines: null,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: 'タイトルを入力',
                              ),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          // 削除ボタン
                          IconButton(
                            onPressed: _deleteTask,
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.grey,
                            ),
                          ),
                          // 完了ボタン (明示的に閉じるとき用)
                          IconButton(
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(
                              Icons.check,
                              color: AppColors.primary,
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 日付設定 (リストアイテム風)
                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _scheduledAt ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                            locale: const Locale('ja'), // 日本語化
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
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                color: _scheduledAt != null
                                    ? AppColors.primary
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 16),
                              Text(
                                _scheduledAt == null
                                    ? '日時を追加'
                                    : DateFormat(
                                        'yyyy/MM/dd HH:mm',
                                      ).format(_scheduledAt!),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: _scheduledAt != null
                                      ? Colors.black
                                      : Colors.grey[600],
                                ),
                              ),
                              if (_scheduledAt != null) ...[
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 20),
                                  onPressed: () =>
                                      setState(() => _scheduledAt = null),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // 繰り返し設定
                      InkWell(
                        onTap: _showRecurrenceSettings,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.repeat,
                                color: _recurrenceUnit != null
                                    ? AppColors.primary
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  _getRecurrenceText(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _recurrenceUnit != null
                                        ? Colors.black
                                        : Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // サブタスクリスト
                      if (_subtasks.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ..._subtasks.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          return Row(
                            children: [
                              Checkbox(
                                value: item.isCompleted,
                                onChanged: (val) {
                                  setState(() {
                                    _subtasks[index] = item.copyWith(
                                      isCompleted: val,
                                    );
                                  });
                                },
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: TextStyle(
                                    decoration: item.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: item.isCompleted
                                        ? Colors.grey
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _subtasks.removeAt(index);
                                  });
                                },
                              ),
                            ],
                          );
                        }),
                      ],

                      // サブタスク追加
                      if (_isAddingSubtask)
                        Padding(
                          padding: const EdgeInsets.only(left: 12, top: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.subdirectory_arrow_right,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _subtaskController,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                    hintText: 'サブタスクを入力',
                                    border: InputBorder.none,
                                  ),
                                  onSubmitted: (_) => _addSubtask(),
                                ),
                              ),
                              IconButton(
                                onPressed: _addSubtask,
                                icon: const Icon(
                                  Icons.check,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        InkWell(
                          onTap: () => setState(() => _isAddingSubtask = true),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.subdirectory_arrow_right,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  'サブタスクを追加',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasChanges() {
    return _titleController.text.trim() != widget.task.content ||
        _priority != widget.task.priority ||
        _scheduledAt != widget.task.scheduledAt ||
        !listEquals(_subtasks, widget.task.subtasks) ||
        _recurrenceInterval != widget.task.recurrenceInterval ||
        _recurrenceUnit != widget.task.recurrenceUnit ||
        !listEquals(_recurrenceDaysOfWeek, widget.task.recurrenceDaysOfWeek) ||
        _recurrenceEndDate != widget.task.recurrenceEndDate;
  }

  // listEquals helper since standard equals checks reference
  bool listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    // TaskItem equality check is needed if T is TaskItem, but simplistic string check or deep check logic:
    // Here we might need a better check. For now assume reference or simplistic checks.
    // For List<int> (recurrenceDaysOfWeek) it works if we loop.
    for (int i = 0; i < a.length; i++) {
      if (a[i].toString() != b[i].toString()) return false;
    }
    return true;
  }
}
