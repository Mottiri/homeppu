// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:homeppu/core/constants/app_colors.dart';

class RecurrenceSettingsSheet extends StatefulWidget {
  final int initialInterval;
  final String initialUnit; // 'daily', 'weekly', 'monthly', 'yearly'
  final List<int>? initialDaysOfWeek;
  final DateTime? initialEndDate;
  final DateTime? startDate; // For display reference

  const RecurrenceSettingsSheet({
    super.key,
    this.initialInterval = 1,
    this.initialUnit = 'weekly',
    this.initialDaysOfWeek,
    this.initialEndDate,
    this.startDate,
  });

  @override
  State<RecurrenceSettingsSheet> createState() =>
      _RecurrenceSettingsSheetState();
}

class _RecurrenceSettingsSheetState extends State<RecurrenceSettingsSheet> {
  late int _interval;
  late String _unit;
  late List<int> _daysOfWeek; // 1=Mon, 7=Sun
  DateTime? _endDate;
  bool _hasEndDate = false;

  final List<String> _units = ['daily', 'weekly', 'monthly', 'yearly'];
  final Map<String, String> _unitLabels = {
    'daily': '日',
    'weekly': '週間',
    'monthly': 'ヶ月',
    'yearly': '年',
  };

  @override
  void initState() {
    super.initState();
    _interval = widget.initialInterval;
    _unit = widget.initialUnit;
    _daysOfWeek = widget.initialDaysOfWeek ?? [];
    _endDate = widget.initialEndDate;
    _hasEndDate = _endDate != null;

    // If weekly and no days selected, select current day or start date day
    if (_unit == 'weekly' && _daysOfWeek.isEmpty) {
      // Default to "today" or startDate's weekday
      final refDate = widget.startDate ?? DateTime.now();
      _daysOfWeek.add(refDate.weekday);
    }
  }

  void _onSave() {
    Navigator.pop(context, {
      'interval': _interval,
      'unit': _unit,
      'daysOfWeek': _unit == 'weekly' ? _daysOfWeek : null,
      'endDate': _hasEndDate ? _endDate : null,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom:
            MediaQuery.of(context).viewInsets.bottom +
            16, // Keyboard adjustment
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: AppColors.textPrimary,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Text(
                  '繰り返し',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: _onSave,
                child: const Text(
                  '完了',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Interval Section
                  const Text(
                    '間隔:',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Interval Number Input
                      Container(
                        width: 80,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextField(
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center, // Center text
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18, // Larger font
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            focusedBorder:
                                InputBorder.none, // Ensure no border on focus
                            enabledBorder: InputBorder.none, // Ensure no border
                            errorBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            filled: false, // Turn off theme fill
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          controller:
                              TextEditingController(text: _interval.toString())
                                ..selection = TextSelection.collapsed(
                                  offset: _interval.toString().length,
                                ),
                          onChanged: (val) {
                            final n = int.tryParse(val);
                            if (n != null && n > 0) {
                              setState(() => _interval = n);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Unit Dropdown
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _unit,
                              dropdownColor: AppColors.surface,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                              icon: const Icon(
                                Icons.arrow_drop_down,
                                color: AppColors.textPrimary,
                              ),
                              items: _units.map((u) {
                                return DropdownMenuItem(
                                  value: u,
                                  child: Text(
                                    _unitLabels[u]!,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _unit = val);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Days of Week (Only for Weekly)
                  if (_unit == 'weekly') ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (index) {
                        // 0=Sunday for UI display usually? Or Mon-Sun?
                        // Google Tasks image starts with Sunday (日 月 火 ...)
                        // DateTime.weekday: 1=Mon, ..., 7=Sun
                        // Let's map 0..6 to Sun..Sat for display
                        // index 0 -> Sunday (weekday 7)
                        // index 1 -> Monday (weekday 1)
                        final days = ['日', '月', '火', '水', '木', '金', '土'];
                        final weekday = index == 0
                            ? 7
                            : index; // 0->7(Sun), 1->1(Mon)
                        final isSelected = _daysOfWeek.contains(weekday);

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                // Prevent unselecting the last day? no, allow it but ensure logic defaults if empty
                                _daysOfWeek.remove(weekday);
                              } else {
                                _daysOfWeek.add(weekday);
                              }
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? Colors.transparent
                                    : Colors.grey.shade300,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              days[index],
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.textPrimary,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],

                  const SizedBox(height: 24),
                  const Divider(color: Colors.grey), // Light divider
                  const SizedBox(height: 16),

                  // End Condition
                  const Text(
                    '終了条件',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),

                  // Option 1: None
                  RadioListTile<bool>(
                    value: false,
                    groupValue: _hasEndDate,
                    onChanged: (val) => setState(() => _hasEndDate = false),
                    title: const Text(
                      '指定しない',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                    activeColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                  ),

                  // Option 2: On Date
                  RadioListTile<bool>(
                    value: true,
                    groupValue: _hasEndDate,
                    onChanged: (val) {
                      setState(() {
                        _hasEndDate = true;
                        _endDate ??= DateTime.now().add(
                          const Duration(days: 30),
                        );
                      });
                    },
                    title: Row(
                      children: [
                        const Text(
                          '終了日',
                          style: TextStyle(color: AppColors.textPrimary),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              if (!_hasEndDate) {
                                setState(() {
                                  _hasEndDate = true;
                                  _endDate ??= DateTime.now();
                                });
                              }
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _endDate ?? DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 1825),
                                ), // 5 years
                                locale: const Locale('ja'), // 日本語化
                                builder: (context, child) {
                                  return Theme(
                                    data: ThemeData.light().copyWith(
                                      colorScheme: const ColorScheme.light(
                                        primary: AppColors.primary,
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (date != null) {
                                setState(() => _endDate = date);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _hasEndDate
                                      ? AppColors.primary
                                      : Colors.grey.shade300,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _endDate != null
                                    ? DateFormat('yyyy年M月d日').format(_endDate!)
                                    : '日付を選択',
                                style: TextStyle(
                                  color: _hasEndDate
                                      ? AppColors.primary
                                      : AppColors.textHint,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    activeColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                  ),

                  const SizedBox(height: 24),

                  // 繰り返し解除ボタン
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context, {
                        'unit': 'none', // 特別な値で「解除」を示す
                        'interval': null,
                        'daysOfWeek': null,
                        'endDate': null,
                      });
                    },
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                    label: const Text(
                      '繰り返しを解除',
                      style: TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
