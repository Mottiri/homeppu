import 'package:flutter/material.dart';
import 'package:homeppu/core/constants/app_colors.dart';
import 'package:intl/intl.dart';

class AddTaskBottomSheet extends StatefulWidget {
  const AddTaskBottomSheet({super.key});

  @override
  State<AddTaskBottomSheet> createState() => _AddTaskBottomSheetState();
}

class _AddTaskBottomSheetState extends State<AddTaskBottomSheet> {
  final _titleController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String _selectedType = 'daily'; // daily, todo, goal
  int _priority = 0; // 0, 1, 2
  DateTime? _scheduledDate;
  bool _syncGoogleCalendar = false;

  final List<String> _types = ['daily', 'todo', 'goal'];
  final Map<String, String> _typeLabels = {
    'daily': '毎日',
    'todo': 'やること',
    'goal': '目標',
  };
  final Map<String, IconData> _typeIcons = {
    'daily': Icons.loop,
    'todo': Icons.check_circle_outline,
    'goal': Icons.flag_outlined,
  };

  @override
  void initState() {
    super.initState();
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

    Navigator.pop(context, {
      'content': title,
      'type': _selectedType,
      'priority': _priority,
      'scheduledAt': _scheduledDate,
      'syncGoogleCalendar': _syncGoogleCalendar,
      'emoji': _getEmojiForType(_selectedType), // 簡易的にタイプから決定（後で編集可能）
    });
  }

  String _getEmojiForType(String type) {
    switch (type) {
      case 'daily':
        return '✨';
      case 'todo':
        return '📝';
      case 'goal':
        return '🎯';
      default:
        return '✨';
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
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
          // 日時指定したらタイプを自動でtodoに切り替え（便利機能）
          if (_selectedType == 'daily') {
            _selectedType = 'todo';
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // キーボードの上のパディング
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ヘッダー: タイプ選択
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _types.map((type) {
                  final isSelected = _selectedType == type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Row(
                        children: [
                          Icon(
                            _typeIcons[type],
                            size: 16,
                            color: isSelected ? Colors.white : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(_typeLabels[type]!),
                        ],
                      ),
                      selected: isSelected,
                      onSelected: (bool selected) {
                        if (selected) {
                          setState(() {
                            _selectedType = type;
                            // タイプ変更時のリセットロジック
                            if (type == 'daily') {
                              _scheduledDate = null;
                            }
                          });
                        }
                      },
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[700],
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      backgroundColor: Colors.grey[100],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide.none,
                      ),
                    ),
                  );
                }).toList(),
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
                // 送信ボタン
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
                        _priority == 0 ? '🟢' : (_priority == 1 ? '🟡' : '🔴'),
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
                  const SizedBox(width: 8),

                  // カレンダー同期スイッチ
                  FilterChip(
                    label: const Text('Google連携'),
                    avatar: const Icon(Icons.sync, size: 16),
                    selected: _syncGoogleCalendar,
                    onSelected: (bool value) async {
                      if (value && _scheduledDate == null) {
                        // 同期ONにするなら日時必須 -> 日時ピッカーを開く
                        await _pickDate();
                        // キャンセルされたらONにしない
                        if (_scheduledDate == null) return;
                      }
                      setState(() {
                        _syncGoogleCalendar = value;
                      });
                    },
                    selectedColor: Colors.blue.withOpacity(0.2),
                    labelStyle: TextStyle(
                      color: _syncGoogleCalendar
                          ? Colors.blue[800]
                          : Colors.grey[700],
                    ),
                    checkmarkColor: Colors.blue[800],
                    side: BorderSide(
                      color: _syncGoogleCalendar
                          ? Colors.blue
                          : Colors.grey[300]!,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
