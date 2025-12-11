import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../shared/models/task_model.dart';
import '../../../../shared/services/task_service.dart';
import '../../../../shared/services/calendar_service.dart';
import '../widgets/add_task_bottom_sheet.dart';
import '../widgets/task_detail_sheet.dart';
import '../widgets/task_card.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen>
    with SingleTickerProviderStateMixin {
  final TaskService _taskService = TaskService();
  final CalendarService _calendarService = CalendarService();
  late TabController _tabController;

  List<TaskModel> _dailyTasks = [];
  List<TaskModel> _todoTasks = [];
  List<TaskModel> _goalTasks = [];
  bool _isLoading = true;
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadTasks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final tasks = await _taskService.getTasks();
      if (!mounted) return;

      setState(() {
        _dailyTasks = tasks.where((t) => t.type == 'daily').toList();
        _todoTasks = tasks.where((t) => t.type == 'todo').toList();
        _goalTasks = tasks.where((t) => t.type == 'goal').toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('タスクの読み込みに失敗しました: $e')));
    }
  }

  Future<void> _addTask() async {
    if (_isAdding) return;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddTaskBottomSheet(),
    );

    if (result != null && mounted) {
      setState(() => _isAdding = true);
      String? calendarEventId;

      try {
        // Googleカレンダー連携
        if (result['syncGoogleCalendar'] == true &&
            result['scheduledAt'] != null) {
          calendarEventId = await _calendarService.createEvent(
            title: result['content'],
            description: '',
            startTime: result['scheduledAt'],
            endTime: (result['scheduledAt'] as DateTime).add(
              const Duration(hours: 1),
            ),
          );
        }

        await _taskService.createTask(
          content: result['content'],
          emoji: result['emoji'],
          type: result['type'],
          scheduledAt: result['scheduledAt'],
          priority: result['priority'] ?? 0,
          googleCalendarEventId: calendarEventId,
        );

        await _loadTasks();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                calendarEventId != null
                    ? '✨ カレンダー連携タスクを追加しました！'
                    : '✨ タスクを追加しました！',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('タスクの追加に失敗しました: $e')));
        }
      } finally {
        if (mounted) setState(() => _isAdding = false);
      }
    }
  }

  Future<void> _handleUpdateTask(TaskModel task) async {
    try {
      // カレンダー連携があれば更新
      if (task.googleCalendarEventId != null && task.scheduledAt != null) {
        await _calendarService.updateEvent(
          eventId: task.googleCalendarEventId!,
          title: task.content,
          description: '',
          startTime: task.scheduledAt!,
          endTime: task.scheduledAt!.add(const Duration(hours: 1)),
        );
      }
      // TODO: 新規に日付がついてGoogle連携ONにされた場合のロジックも必要だが、DetailSheetでまだ連携スイッチを実装していないため保留

      await _taskService.updateTask(task);
      await _loadTasks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新に失敗しました: $e')));
      }
    }
  }

  Future<void> _completeTask(TaskModel task) async {
    try {
      final result = await _taskService.completeTask(task.id);
      await _loadTasks();

      if (mounted) {
        if (result.virtueGain > 0) {
          String message = '🎉 +${result.virtueGain}徳ポイント獲得！';
          if (result.streakBonus > 0) {
            message += '\n🔥 ${result.streak}日連続ボーナス！';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ このタスクは既に完了しています'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = '完了処理に失敗しました';
        if (e.toString().contains('already-exists')) {
          errorMessage = '✅ このタスクは既に完了しています';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    }
  }

  Future<void> _deleteTask(TaskModel task) async {
    try {
      if (task.googleCalendarEventId != null) {
        await _calendarService.deleteEvent(task.googleCalendarEventId!);
      }
      await _taskService.deleteTask(task.id);
      await _loadTasks();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('タスクを削除しました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
  }

  Future<void> _uncompleteTask(TaskModel task) async {
    try {
      final result = await _taskService.uncompleteTask(task.id);
      await _loadTasks();

      if (mounted) {
        if (result.success && result.virtueLoss > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('完了を取り消しました（-${result.virtueLoss}徳ポイント）'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        } else if (result.message != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(result.message!)));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('完了を取り消しました'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('取り消しに失敗しました: $e')));
      }
    }
  }

  void _showTaskDetail(TaskModel task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        task: task,
        onUpdate: _handleUpdateTask,
        onDelete: () => _deleteTask(task),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('ログインが必要です')));
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('やることリスト'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            _buildTab(
              context,
              Icons.today,
              'デイリー',
              _dailyTasks.length,
              Theme.of(context).primaryColor,
            ),
            _buildTab(
              context,
              Icons.check_circle_outline,
              'やること',
              _todoTasks.length,
              Colors.blue,
            ),
            _buildTab(
              context,
              Icons.flag,
              '目標',
              _goalTasks.length,
              Colors.orange,
            ),
          ],
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Theme.of(context).primaryColor,
          labelPadding: EdgeInsets.zero, // 画面幅が狭い場合のためにパディングを詰める
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTaskList(_dailyTasks, 'daily'),
                _buildTaskList(_todoTasks, 'todo'),
                _buildTaskList(_goalTasks, 'goal'),
              ],
            ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 120),
        child: FloatingActionButton(
          onPressed: _isAdding ? null : _addTask,
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          elevation: 4,
          child: _isAdding
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.add, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Tab _buildTab(
    BuildContext context,
    IconData icon,
    String label,
    int count,
    Color color,
  ) {
    return Tab(
      height: 36, // 明示的に高さを指定してレイアウトを安定させる
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)), // 少し小さく
            if (count > 0) ...[
              const SizedBox(width: 2), // マージン削減
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1,
                ), // パディング削減
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10, // フォントサイズ調整
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList(List<TaskModel> tasks, String type) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type == 'daily'
                  ? Icons.today
                  : (type == 'todo' ? Icons.check_circle_outline : Icons.flag),
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              type == 'daily'
                  ? '毎日のタスクを追加しよう！'
                  : (type == 'todo' ? 'やることを追加しよう！' : '目標を設定しよう！'),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            const SizedBox(height: 100),
          ],
        ),
      );
    }

    final sortedTasks = [...tasks];
    // 日付順や優先度順にソート（必要に応じて改善）
    sortedTasks.sort((a, b) {
      // 完了は下
      final aCompleted =
          a.isCompletedToday ||
          (a.isGoal && a.isCompleted) ||
          (a.isTodo && a.isCompleted);
      final bCompleted =
          b.isCompletedToday ||
          (b.isGoal && b.isCompleted) ||
          (b.isTodo && b.isCompleted);
      if (aCompleted != bCompleted) return aCompleted ? 1 : -1;

      // 優先度高い順
      if (a.priority != b.priority) return b.priority - a.priority;

      // 日付近い順
      if (a.scheduledAt != null && b.scheduledAt != null)
        return a.scheduledAt!.compareTo(b.scheduledAt!);

      return 0;
    });

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          ...sortedTasks.map(
            (task) => TaskCard(
              task: task,
              onComplete: () => _completeTask(task),
              onUncomplete: () => _uncompleteTask(task),
              onDelete: () => _deleteTask(task),
              onTap: () => _showTaskDetail(task),
            ),
          ),
        ],
      ),
    );
  }
}
