import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:homeppu/core/constants/app_colors.dart';
import 'package:homeppu/shared/models/task_model.dart';

class MonthlyCalendarScreen extends StatefulWidget {
  final DateTime initialDate;
  final Map<DateTime, List<TaskModel>> tasks; // TaskModelのリストに変更

  const MonthlyCalendarScreen({
    super.key,
    required this.initialDate,
    required this.tasks,
  });

  @override
  State<MonthlyCalendarScreen> createState() => _MonthlyCalendarScreenState();
}

class _MonthlyCalendarScreenState extends State<MonthlyCalendarScreen> {
  late PageController _pageController;
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
    _pageController = PageController(initialPage: 1000); // 1000ヶ月目を基準
  }

  DateTime _getMonthForPage(int pageIndex) {
    final monthOffset = pageIndex - 1000;
    return DateTime(_currentMonth.year, _currentMonth.month + monthOffset);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text('カレンダー'),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemBuilder: (context, index) {
          final month = _getMonthForPage(index);
          return _buildMonthView(month);
        },
      ),
    );
  }

  Widget _buildMonthView(DateTime month) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final firstWeekday = firstDayOfMonth.weekday; // 1(Mon) - 7(Sun)

    // Adjust for Sunday start if needed (Here Mon start)
    // ほめっぷ usually Mon start? Standard Japanese is often Sun?
    // WeekCalendarStrip was Mon start. Let's stick to Mon start for consistency.

    // Grid cells calculation
    final totalCells = daysInMonth + (firstWeekday - 1);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              ),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: month,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                    initialDatePickerMode: DatePickerMode.year,
                    locale: const Locale('ja'), // 日本語化
                  );
                  if (picked != null) {
                    // 選択された年月と現在の表示年月（基準点）との差分を計算してページジャンプ
                    // ただしPageViewは1000スタートなので、差分計算が複雑。
                    // シンプルに再計算してjumpToPageする
                    final diffMonths =
                        (picked.year - _currentMonth.year) * 12 +
                        (picked.month - _currentMonth.month);
                    _pageController.jumpToPage(1000 + diffMonths);
                  }
                },
                child: Row(
                  children: [
                    Text(
                      DateFormat('yyyy年').format(month),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('M月').format(month),
                      style: const TextStyle(
                        fontSize: 24, // 月だけ大きく
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_drop_down,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              ),
            ],
          ),
        ),
        // Days Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['月', '火', '水', '木', '金', '土', '日'].map((day) {
            return SizedBox(
              width: 35,
              child: Center(
                child: Text(
                  day,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 1,
              mainAxisSpacing: 1,
              childAspectRatio: 0.45, // さらに縦長にして画面埋める
            ),
            itemCount:
                totalCells + (7 - totalCells % 7) % 7, // Pad to end of row
            itemBuilder: (context, index) {
              if (index < firstWeekday - 1) {
                return const SizedBox();
              }
              final day = index - (firstWeekday - 1) + 1;
              if (day > daysInMonth) {
                return const SizedBox();
              }

              final date = DateTime(month.year, month.month, day);
              final taskList =
                  widget.tasks[DateTime(date.year, date.month, date.day)] ?? [];
              final isToday = isSameDay(date, DateTime.now());

              return GestureDetector(
                onTap: () {
                  Navigator.pop(context, date);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isToday
                        ? AppColors.primary.withOpacity(0.1)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(4), // 角丸を少し小さく
                    border: isToday
                        ? Border.all(color: AppColors.primary)
                        : Border.all(
                            color: Colors.grey.shade200,
                            width: 0.5,
                          ), // 枠線追加で視認性向上
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start, // 上寄せ
                    crossAxisAlignment: CrossAxisAlignment.stretch, // 幅いっぱいに
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2, left: 4),
                        child: Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 10,
                            color: isToday
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontWeight: isToday
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),

                      // タスク表示エリア
                      // 未完了タスクを優先表示（完了済みは後回し→省略時に優先非表示）
                      ...(() {
                        final sortedTasks = List<TaskModel>.from(taskList)
                          ..sort((a, b) {
                            // 未完了を先に (isCompleted: false = 0, true = 1)
                            final compA = a.isCompleted ? 1 : 0;
                            final compB = b.isCompleted ? 1 : 0;
                            if (compA != compB) return compA - compB;
                            // 同じ完了状態なら優先度で降順 (高い方が先)
                            return b.priority - a.priority;
                          });
                        return sortedTasks.take(3);
                      })().map((task) {
                        // 色設定 (Googleカレンダー風に濃い色で)
                        Color bgColor;
                        Color textColor = Colors.white;

                        if (task.isCompleted) {
                          bgColor = Colors.grey;
                        } else if (task.priority == 2) {
                          bgColor = Colors.red.shade400;
                        } else if (task.priority == 1) {
                          bgColor = Colors.orange.shade400;
                        } else {
                          bgColor = Colors.blue.shade400; // 青系
                        }

                        return Container(
                          margin: const EdgeInsets.only(
                            bottom: 1.5,
                            left: 1,
                            right: 1,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 0.5,
                          ),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            task.content,
                            style: TextStyle(
                              fontSize: 9, // 少しサイズアップ
                              color: textColor,
                              fontWeight: FontWeight.w500,
                              decoration: task.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: Colors.white,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),

                      if (taskList.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            '+${taskList.length - 3}',
                            style: const TextStyle(
                              fontSize: 8,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
