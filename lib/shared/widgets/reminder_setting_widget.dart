import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// リマインダー設定ウィジェット
/// 複数のリマインダーを追加/削除可能
class ReminderSettingWidget extends StatefulWidget {
  final List<Map<String, dynamic>> reminders;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool isGoal; // true: 目標（日単位デフォルト）, false: タスク（分単位デフォルト）

  const ReminderSettingWidget({
    super.key,
    required this.reminders,
    required this.onChanged,
    this.isGoal = false,
  });

  @override
  State<ReminderSettingWidget> createState() => _ReminderSettingWidgetState();
}

class _ReminderSettingWidgetState extends State<ReminderSettingWidget> {
  late List<Map<String, dynamic>> _reminders;
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _reminders = List.from(widget.reminders);
    _initControllers();
  }

  void _initControllers() {
    _controllers = _reminders.map((r) {
      final value = r['value'] as int? ?? 1;
      return TextEditingController(text: value.toString());
    }).toList();

    _focusNodes = List.generate(_reminders.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _addReminder() {
    final newReminder = {
      'value': widget.isGoal ? 1 : 30,
      'unit': widget.isGoal ? 'days' : 'minutes',
    };
    setState(() {
      _reminders.add(Map.from(newReminder));
      _controllers.add(
        TextEditingController(text: newReminder['value'].toString()),
      );
      _focusNodes.add(FocusNode());
    });
    widget.onChanged(List.from(_reminders));
  }

  void _removeReminder(int index) {
    setState(() {
      _reminders.removeAt(index);
      _controllers[index].dispose();
      _controllers.removeAt(index);
      _focusNodes[index].dispose();
      _focusNodes.removeAt(index);
    });
    widget.onChanged(List.from(_reminders));
  }

  void _updateValue(int index) {
    final text = _controllers[index].text;
    final parsed = int.tryParse(text);
    if (parsed != null && parsed > 0) {
      _reminders[index] = Map<String, dynamic>.from(_reminders[index])
        ..['value'] = parsed;
      widget.onChanged(List.from(_reminders));
    }
  }

  void _updateUnit(int index, String unit) {
    setState(() {
      _reminders[index] = Map<String, dynamic>.from(_reminders[index])
        ..['unit'] = unit;
    });
    widget.onChanged(List.from(_reminders));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ヘッダー
        Row(
          children: [
            Icon(
              Icons.notifications_outlined,
              size: 18,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 6),
            Text(
              '事前通知',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
            const Spacer(),
            // 追加ボタン
            TextButton.icon(
              onPressed: _addReminder,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('追加'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // リマインダーリスト
        if (_reminders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '通知なし',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          ...List.generate(_reminders.length, (index) {
            final reminder = _reminders[index];
            final unit = reminder['unit'] as String? ?? 'minutes';

            return Padding(
              key: ValueKey('reminder_$index'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  // 数値入力
                  SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      // フォーカスが外れたときに値を更新
                      onEditingComplete: () => _updateValue(index),
                      onTapOutside: (_) {
                        _updateValue(index);
                        _focusNodes[index].unfocus();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 単位プルダウン
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: unit,
                        isDense: true,
                        items: [
                          if (!widget.isGoal)
                            const DropdownMenuItem(
                              value: 'minutes',
                              child: Text('分'),
                            ),
                          const DropdownMenuItem(
                            value: 'hours',
                            child: Text('時間'),
                          ),
                          const DropdownMenuItem(
                            value: 'days',
                            child: Text('日'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            _updateUnit(index, v);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  Text(
                    '前',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const Spacer(),

                  // 削除ボタン
                  IconButton(
                    onPressed: () => _removeReminder(index),
                    icon: Icon(
                      Icons.remove_circle_outline,
                      color: Colors.red[400],
                      size: 22,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
