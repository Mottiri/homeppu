import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:homeppu/core/constants/app_colors.dart';
import 'package:homeppu/shared/models/task_model.dart';
import 'package:homeppu/features/tasks/presentation/widgets/recurrence_settings_sheet.dart';
import 'package:homeppu/shared/services/media_service.dart';
import 'package:homeppu/shared/models/goal_model.dart';
import 'package:homeppu/shared/providers/goal_provider.dart';
import 'package:intl/intl.dart';

class TaskDetailSheet extends ConsumerStatefulWidget {
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
  ConsumerState<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends ConsumerState<TaskDetailSheet> {
  late TextEditingController _titleController;
  late TextEditingController _memoController;
  late int _priority;
  late DateTime? _scheduledAt;
  late List<TaskItem> _subtasks;
  late List<String> _attachmentUrls;
  String? _selectedGoalId;

  final MediaService _mediaService = MediaService();
  bool _isUploading = false;

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
    _memoController = TextEditingController(text: widget.task.memo);
    _priority = widget.task.priority;
    _scheduledAt = widget.task.scheduledAt;
    _subtasks = List.from(widget.task.subtasks);
    _recurrenceInterval = widget.task.recurrenceInterval;
    _recurrenceUnit = widget.task.recurrenceUnit;
    _recurrenceDaysOfWeek = widget.task.recurrenceDaysOfWeek != null
        ? List.from(widget.task.recurrenceDaysOfWeek!)
        : null;
    _recurrenceEndDate = widget.task.recurrenceEndDate;
    _attachmentUrls = List.from(widget.task.attachmentUrls);
    _selectedGoalId = widget.task.goalId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _memoController.dispose();
    _subtaskController.dispose();
    super.dispose();
  }

  void _notifyUpdate([String editMode = 'single']) {
    // 繰り返し設定がクリアされたかどうか
    final clearRecurrence =
        widget.task.recurrenceGroupId != null && _recurrenceUnit == null;

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
      memo: _memoController.text.trim().isEmpty
          ? null
          : _memoController.text.trim(),
      attachmentUrls: _attachmentUrls,
      goalId: _selectedGoalId,
      clearRecurrence: clearRecurrence,
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
    // サブタスク追加後はフォーカスを外す（メモ等のフォーカスに戻らないようにする）
    FocusScope.of(context).unfocus();
  }

  Future<void> _pickAttachment() async {
    setState(() => _isUploading = true);
    try {
      // 画像のみ選択 (image_pickerを使用、またはfile_pickerでフィルタ)
      // MediaServiceのpickImagesはXFileを返すので、ここではpickFiles(type: image)の方が既存ロジックに近いかもだが
      // ユーザー要望は「画像添付だけで良い」
      final images = await _mediaService.pickImages(maxCount: 1);
      if (images.isEmpty) {
        setState(() => _isUploading = false);
        return;
      }

      final filePath = images.first.path;

      // アップロード
      final url = await _mediaService.uploadTaskAttachment(
        filePath: filePath,
        userId: widget.task.userId,
        taskId: widget.task.id,
      );

      setState(() {
        _attachmentUrls.add(url);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('アップロードに失敗しました: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _showFullImage(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentItem(String url) {
    // 画像のみを扱う前提だが、念のため拡張子チェックは残す、あるいは全て画像として扱う
    final name = '画像 ${_attachmentUrls.indexOf(url) + 1}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _showFullImage(url),
            child: Container(
              width: 60, // 少し大きくする
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
                image: DecorationImage(
                  image: NetworkImage(url),
                  fit: BoxFit.cover,
                ),
              ),
              child: null, // ImageはDecorationImageで表示
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => _showFullImage(url),
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  decoration: TextDecoration.underline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: Colors.grey),
            onPressed: () {
              setState(() {
                _attachmentUrls.remove(url);
              });
            },
          ),
        ],
      ),
    );
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
        if (result['unit'] == 'none') {
          // 繰り返しを解除
          _recurrenceInterval = null;
          _recurrenceUnit = null;
          _recurrenceDaysOfWeek = null;
          _recurrenceEndDate = null;
        } else {
          _recurrenceInterval = result['interval'];
          _recurrenceUnit = result['unit'];
          _recurrenceDaysOfWeek = result['daysOfWeek'];
          _recurrenceEndDate = result['endDate'];
        }
      });
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
        // 繰り返しルールの変更がある場合のみ、今後も変更するか聞く
        if (_hasRecurrenceRuleChanges()) {
          final editMode = await showDialog<String>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('繰り返し設定の変更'), // 文言修正
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
            return;
          }

          _notifyUpdate(editMode);
        } else {
          // ルール以外の変更（タイトル、メモ、サブタスク完了など）は、単発変更として保存
          _notifyUpdate('single');
        }

        if (mounted) Navigator.pop(context);
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: SafeArea(
                bottom: false,
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: GestureDetector(
                                onTap: () {
                                  setState(
                                    () => _priority = (_priority + 1) % 3,
                                  );
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
                            IconButton(
                              onPressed: _deleteTask,
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.grey,
                              ),
                            ),
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

                        // Date Picker
                        InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _scheduledAt ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                              locale: const Locale('ja'),
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

                        // Recurrence
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
                                // 繰り返し解除ボタン
                                if (_recurrenceUnit != null)
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _recurrenceInterval = null;
                                        _recurrenceUnit = null;
                                        _recurrenceDaysOfWeek = null;
                                        _recurrenceEndDate = null;
                                      });
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const Divider(height: 1),

                        // Memo Area
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.notes, color: Colors.grey),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextField(
                                  controller: _memoController,
                                  maxLines: null,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'メモを追加',
                                    isCollapsed: true,
                                  ),
                                  style: const TextStyle(fontSize: 16),
                                  textInputAction:
                                      TextInputAction.done, // キーボードを閉じるボタンを表示
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Divider(height: 1),

                        // Attachments Area
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.image,
                                    color: Colors.grey,
                                  ), // Changed icon to image
                                  const SizedBox(width: 16),
                                  const Text(
                                    '画像添付',
                                    style: TextStyle(fontSize: 16),
                                  ), // Changed text
                                  const Spacer(),
                                  if (_isUploading)
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else
                                    IconButton(
                                      onPressed: _pickAttachment,
                                      icon: const Icon(
                                        Icons.add_photo_alternate,
                                        color: AppColors.primary,
                                      ), // Changed icon
                                    ),
                                ],
                              ),
                              if (_attachmentUrls.isNotEmpty)
                                ..._attachmentUrls.map(
                                  (url) => _buildAttachmentItem(url),
                                ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // Goal Linking Section
                        if (FirebaseAuth.instance.currentUser != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.flag_rounded,
                                      color: _selectedGoalId != null
                                          ? AppColors.primary
                                          : Colors.grey,
                                    ),
                                    const SizedBox(width: 16),
                                    const Text(
                                      '目標と紐づけ',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Consumer(
                                  builder: (context, ref, child) {
                                    final goalService = ref.watch(
                                      goalServiceProvider,
                                    );
                                    return StreamBuilder<List<GoalModel>>(
                                      stream: goalService.streamActiveGoals(
                                        FirebaseAuth.instance.currentUser!.uid,
                                      ),
                                      builder: (context, snapshot) {
                                        if (!snapshot.hasData ||
                                            snapshot.data!.isEmpty) {
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              left: 40,
                                            ),
                                            child: Text(
                                              '紐づけ可能な目標がありません',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey[500],
                                              ),
                                            ),
                                          );
                                        }
                                        final goals = snapshot.data!;
                                        return SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          padding: const EdgeInsets.only(
                                            left: 40,
                                          ),
                                          child: Row(
                                            children: [
                                              // 目標なしオプション
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                child: ChoiceChip(
                                                  label: const Text('なし'),
                                                  selected:
                                                      _selectedGoalId == null,
                                                  onSelected: (val) {
                                                    if (val) {
                                                      setState(
                                                        () => _selectedGoalId =
                                                            null,
                                                      );
                                                    }
                                                  },
                                                  selectedColor:
                                                      Colors.grey[300],
                                                  backgroundColor:
                                                      Colors.grey[100],
                                                  showCheckmark: false,
                                                ),
                                              ),
                                              // 目標リスト
                                              ...goals.map((goal) {
                                                final isSelected =
                                                    _selectedGoalId == goal.id;
                                                final goalColor = Color(
                                                  goal.colorValue,
                                                );
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 8,
                                                      ),
                                                  child: ChoiceChip(
                                                    avatar: Icon(
                                                      Icons.flag_rounded,
                                                      size: 16,
                                                      color: isSelected
                                                          ? Colors.white
                                                          : goalColor,
                                                    ),
                                                    label: Text(goal.title),
                                                    selected: isSelected,
                                                    onSelected: (val) {
                                                      setState(() {
                                                        _selectedGoalId = val
                                                            ? goal.id
                                                            : null;
                                                      });
                                                    },
                                                    selectedColor: goalColor,
                                                    backgroundColor: goalColor
                                                        .withOpacity(0.1),
                                                    labelStyle: TextStyle(
                                                      color: isSelected
                                                          ? Colors.white
                                                          : Colors.black87,
                                                      fontWeight: isSelected
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                    ),
                                                    showCheckmark: false,
                                                  ),
                                                );
                                              }),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),

                        const Divider(height: 1),
                        const SizedBox(height: 12),

                        // Subtasks List
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

                        // Add Subtask
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
                            onTap: () =>
                                setState(() => _isAddingSubtask = true),
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
        (_memoController.text.trim() != (widget.task.memo ?? '')) ||
        !listEquals(_attachmentUrls, widget.task.attachmentUrls) ||
        _selectedGoalId != widget.task.goalId ||
        _hasRecurrenceRuleChanges();
  }

  bool _hasRecurrenceRuleChanges() {
    return _recurrenceInterval != widget.task.recurrenceInterval ||
        _recurrenceUnit != widget.task.recurrenceUnit ||
        !listEquals(_recurrenceDaysOfWeek, widget.task.recurrenceDaysOfWeek) ||
        _recurrenceEndDate != widget.task.recurrenceEndDate;
  }

  bool listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      // TaskItem special compare handled by TaskItem.==,
      // string comparison is standard.
      // TaskItem has == implemented.
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
