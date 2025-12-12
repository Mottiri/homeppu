import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:homeppu/core/constants/app_colors.dart';
import 'package:homeppu/shared/models/task_model.dart';

class WeekCalendarStrip extends StatefulWidget {
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;
  final Map<DateTime, List<TaskModel>> tasks; // TaskModelのリストに変更

  const WeekCalendarStrip({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.tasks = const {},
  });

  @override
  State<WeekCalendarStrip> createState() => _WeekCalendarStripState();
}

class _WeekCalendarStripState extends State<WeekCalendarStrip> {
  late PageController _pageController;
  late DateTime _currentWeekStart;
  late DateTime _currentMonth; // 表示中の月を保持

  @override
  void initState() {
    super.initState();
    _currentWeekStart = _getStartOfWeek(widget.selectedDate);
    _currentMonth = widget.selectedDate; // 初期値は選択日
    _pageController = PageController(initialPage: 1000);
  }

  @override
  void didUpdateWidget(WeekCalendarStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDate != oldWidget.selectedDate) {
      // 外部から選択日が変更された場合（タップ時など）
      // 月表示も更新する
      setState(() {
        _currentMonth = widget.selectedDate;
        // 外部変更時はその日付がある週までジャンプする
        final newDateStart = _getStartOfWeek(widget.selectedDate);
        final diffDays = newDateStart.difference(_currentWeekStart).inDays;
        final diffWeeks = (diffDays / 7).round();
        final targetPage = 1000 + diffWeeks;
        if (_pageController.hasClients &&
            _pageController.page != targetPage.toDouble()) {
          _pageController.jumpToPage(targetPage);
        }
      });
    }
  }

  DateTime _getStartOfWeek(DateTime date) {
    // 月曜日始まり
    return date.subtract(Duration(days: date.weekday - 1));
  }

  DateTime _getDateForPage(int pageIndex) {
    final weekOffset = pageIndex - 1000;
    return _currentWeekStart.add(Duration(days: weekOffset * 7));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 月表示 (例: 2023年 12月)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('yyyy年 M月').format(_currentMonth),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.today,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  onPressed: () {
                    final now = DateTime.now();
                    widget.onDateSelected(now);

                    // 強制的にスクロール位置も戻す
                    // （選択日が既に今日だった場合、didUpdateWidgetが反応しないため）
                    final newDateStart = _getStartOfWeek(now);
                    final diffDays = newDateStart
                        .difference(_currentWeekStart)
                        .inDays;
                    final diffWeeks = (diffDays / 7).round();
                    final targetPage = 1000 + diffWeeks;

                    if (_pageController.hasClients) {
                      _pageController.jumpToPage(targetPage);
                    }
                    setState(() {
                      _currentMonth = now;
                    });
                  },
                  tooltip: '今日に戻る',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),

          // 日付ストリップ (スクロール可能)
          SizedBox(
            height: 60,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                // ページが変わったら、その週の「木曜日（真ん中）」あたりの月を取得して表示を更新する
                // これにより、週の過半数が含まれる月を表示できる
                final weekStart = _getDateForPage(index);
                final thursday = weekStart.add(const Duration(days: 3));
                if (_currentMonth.year != thursday.year ||
                    _currentMonth.month != thursday.month) {
                  setState(() {
                    _currentMonth = thursday;
                  });
                }
              },
              itemBuilder: (context, index) {
                final weekStart = _getDateForPage(index);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(7, (dayIndex) {
                    final date = weekStart.add(Duration(days: dayIndex));
                    final isSelected = isSameDay(date, widget.selectedDate);
                    final isToday = isSameDay(date, DateTime.now());

                    // タスク取得
                    final taskList =
                        widget.tasks[DateTime(
                          date.year,
                          date.month,
                          date.day,
                        )] ??
                        [];
                    final hasTask = taskList.isNotEmpty;

                    // 表示用タスク（最大3つくらいまでドットを表示、または一番重要なタスクの色を表示）
                    // ユーザー要望：タイトルのみでタスクカードを表示。画面が崩れない程度に。
                    // Stripは幅が狭いので、色付きの細いバーまたはドットで表現するのが限界に近いが
                    // 縦に並べるスペースはある程度ある。
                    // 優先度の高い順にトップのタスクの色を表示しつつ、
                    // テキストを表示するのは難しい（幅35px程度）。
                    // "Mtg" くらいなら入る。

                    return Expanded(
                      child: GestureDetector(
                        onTap: () => widget.onDateSelected(date),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateFormat('E', 'ja').format(date),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? AppColors.primary
                                    : (date.weekday == 7
                                          ? Colors.red
                                          : (date.weekday == 6
                                                ? Colors.blue
                                                : AppColors.textSecondary)),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              width: 36,
                              height: 45, // カプセル高さ
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                border: isToday && !isSelected
                                    ? Border.all(
                                        color: AppColors.primary,
                                        width: 2.0,
                                      )
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${date.day}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (hasTask)
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.primary,
                                      ),
                                    )
                                  else
                                    const SizedBox(height: 4),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
