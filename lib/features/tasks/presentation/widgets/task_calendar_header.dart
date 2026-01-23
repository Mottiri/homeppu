import 'package:flutter/material.dart';

import '../../../../shared/models/task_model.dart';
import 'week_calendar_strip.dart';

class TaskCalendarHeader extends StatelessWidget {
  final DateTime selectedDate;
  final Map<DateTime, List<TaskModel>> taskData;
  final ValueChanged<DateTime> onDateSelected;

  const TaskCalendarHeader({
    super.key,
    required this.selectedDate,
    required this.taskData,
    required this.onDateSelected,
  });

  @override
  Widget build(BuildContext context) {
    return WeekCalendarStrip(
      selectedDate: selectedDate,
      onDateSelected: onDateSelected,
      tasks: taskData,
    );
  }
}
