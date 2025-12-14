import 'package:flutter/material.dart';
import 'package:homeppu/core/constants/app_colors.dart';
import 'package:homeppu/shared/models/category_model.dart';
import 'package:intl/intl.dart';
import 'package:homeppu/features/tasks/presentation/widgets/recurrence_settings_sheet.dart';

class AddTaskBottomSheet extends StatefulWidget {
  final List<CategoryModel> categories;
  final String? initialCategoryId;
  final DateTime? initialScheduledDate;

  const AddTaskBottomSheet({
    super.key,
    this.categories = const [],
    this.initialCategoryId,
    this.initialScheduledDate,
  });

  @override
  State<AddTaskBottomSheet> createState() => _AddTaskBottomSheetState();
}

class _AddTaskBottomSheetState extends State<AddTaskBottomSheet> {
  final _titleController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Selection State
  String? _selectedCategoryId; // null = 'Task' (Default)

  int _priority = 0; // 0, 1, 2
  DateTime? _scheduledDate;

  // Recurrence State
  int? _recurrenceInterval;
  String? _recurrenceUnit; // null means no recurrence
  List<int>? _recurrenceDaysOfWeek;
  DateTime? _recurrenceEndDate;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;
    _scheduledDate = widget.initialScheduledDate;

    // ボトムシートが開いたら自動でフォーカス
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final type = 'todo';

    Navigator.pop(context, {
      'content': title,
      'type': type,
      'categoryId': _selectedCategoryId,
      'priority': _priority,
      'scheduledAt': _scheduledDate,
      'emoji': '📝',
      'recurrenceInterval': _recurrenceInterval,
      'recurrenceUnit': _recurrenceUnit,
      'recurrenceDaysOfWeek': _recurrenceDaysOfWeek,
      'recurrenceEndDate': _recurrenceEndDate,
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      locale: const Locale('ja'),
    );

    if (pickedDate != null) {
      if (!mounted) return;
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_scheduledDate ?? now),
      );

      if (pickedTime != null) {
        setState(() {
          _scheduledDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  Future<void> _openRecurrenceSettings() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RecurrenceSettingsSheet(
        initialInterval: _recurrenceInterval ?? 1,
        initialUnit: _recurrenceUnit ?? 'weekly',
        initialDaysOfWeek: _recurrenceDaysOfWeek,
        initialEndDate: _recurrenceEndDate,
        startDate: _scheduledDate ?? DateTime.now(),
      ),
    );

    if (result != null) {
      setState(() {
        if (result['unit'] == 'none') {
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

  String _getRecurrenceLabel() {
    if (_recurrenceUnit == null) return '繰り返し';

    final unitLabel = switch (_recurrenceUnit!) {
      'daily' => '日',
      'weekly' => '週',
      'monthly' => 'ヶ月',
      'yearly' => '年',
      _ => '',
    };

    if (_recurrenceInterval != null && _recurrenceInterval! > 1) {
      if (_recurrenceUnit == 'weekly' &&
          (_recurrenceDaysOfWeek?.isNotEmpty ?? false)) {
        return '${_recurrenceInterval}$unitLabelごと (曜日指定)';
      }
      return '${_recurrenceInterval}$unitLabelごと';
    }

    if (_recurrenceUnit == 'weekly' &&
        (_recurrenceDaysOfWeek?.isNotEmpty ?? false)) {
      return '毎週 (曜日指定)';
    }

    return '毎${unitLabel}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // カテゴリ・タイプ選択 (横スクロール)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // 1. Task (Default)
                      _buildOptionChip(
                        label: 'タスク',
                        icon: Icons.check_circle_outline,
                        isSelected: _selectedCategoryId == null,
                        onSelected: (val) {
                          if (val)
                            setState(() {
                              _selectedCategoryId = null;
                            });
                        },
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),

                      // 2. Custom Categories
                      ...widget.categories.map((cat) {
                        final isSelected = _selectedCategoryId == cat.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: _buildOptionChip(
                            label: cat.name,
                            icon: Icons.label_outline,
                            isSelected: isSelected,
                            onSelected: (val) {
                              if (val)
                                setState(() {
                                  _selectedCategoryId = cat.id;
                                });
                            },
                            color: Colors
                                .orange, // Fixed color for now, or use cat specific
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 入力エリア
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        focusNode: _focusNode,
                        decoration: const InputDecoration(
                          hintText: '新しいタスクを入力...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(fontSize: 18),
                        maxLines: 1,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    IconButton(
                      onPressed: _submit,
                      icon: const Icon(Icons.arrow_upward_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // オプションエリア (日付・優先度・同期)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // 日付選択
                      ActionChip(
                        avatar: Icon(
                          Icons.calendar_today_outlined,
                          size: 16,
                          color: _scheduledDate != null
                              ? AppColors.primary
                              : Colors.grey,
                        ),
                        label: Text(
                          _scheduledDate != null
                              ? DateFormat('M/d H:mm').format(_scheduledDate!)
                              : '日時',
                          style: TextStyle(
                            color: _scheduledDate != null
                                ? AppColors.primary
                                : Colors.grey[700],
                          ),
                        ),
                        onPressed: _pickDate,
                        backgroundColor: _scheduledDate != null
                            ? AppColors.primary.withOpacity(0.1)
                            : Colors.white,
                        shape: StadiumBorder(
                          side: BorderSide(
                            color: _scheduledDate != null
                                ? AppColors.primary
                                : Colors.grey[300]!,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 繰り返し設定
                      ActionChip(
                        avatar: Icon(
                          Icons.repeat,
                          size: 16,
                          color: _recurrenceUnit != null
                              ? AppColors.primary
                              : Colors.grey,
                        ),
                        label: Text(
                          _recurrenceUnit != null
                              ? _getRecurrenceLabel()
                              : '繰り返し',
                          style: TextStyle(
                            color: _recurrenceUnit != null
                                ? AppColors.primary
                                : Colors.grey[700],
                          ),
                        ),
                        onPressed: _openRecurrenceSettings,
                        backgroundColor: _recurrenceUnit != null
                            ? AppColors.primary.withOpacity(0.1)
                            : Colors.white,
                        side: BorderSide(
                          color: _recurrenceUnit != null
                              ? AppColors.primary
                              : Colors.grey[300]!,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 優先度
                      PopupMenuButton<int>(
                        initialValue: _priority,
                        onSelected: (int item) {
                          setState(() {
                            _priority = item;
                          });
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<int>>[
                              const PopupMenuItem<int>(
                                value: 0,
                                child: Text('優先度: 低 🟢'),
                              ),
                              const PopupMenuItem<int>(
                                value: 1,
                                child: Text('優先度: 中 🟡'),
                              ),
                              const PopupMenuItem<int>(
                                value: 2,
                                child: Text('優先度: 高 🔴'),
                              ),
                            ],
                        child: Chip(
                          avatar: Text(
                            _priority == 0
                                ? '🟢'
                                : (_priority == 1 ? '🟡' : '🔴'),
                            style: const TextStyle(fontSize: 12),
                          ),
                          label: Text(
                            _priority == 0 ? '低' : (_priority == 1 ? '中' : '高'),
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                          backgroundColor: Colors.white,
                          shape: StadiumBorder(
                            side: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required Function(bool) onSelected,
    required Color color,
  }) {
    return ChoiceChip(
      label: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected
                ? Colors.white
                : color, // Selected: White, Unselected: Color
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: onSelected,
      selectedColor: color,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: Colors.grey[100],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide.none,
      ),
      showCheckmark: false, // シンプルにするためチェックマーク非表示
    );
  }
}
