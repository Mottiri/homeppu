import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../shared/models/task_model.dart';
import '../../../../shared/services/task_service.dart';
import '../widgets/add_task_dialog.dart';
import '../widgets/task_card.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with SingleTickerProviderStateMixin {
  final TaskService _taskService = TaskService();
  late TabController _tabController;
  
  List<TaskModel> _dailyTasks = [];
  List<TaskModel> _goalTasks = [];
  bool _isLoading = true;
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      print('TasksScreen: Loading tasks...');
      final tasks = await _taskService.getTasks();
      print('TasksScreen: Got ${tasks.length} tasks');
      for (final task in tasks) {
        print('TasksScreen: Task - id: ${task.id}, type: ${task.type}, content: ${task.content}');
      }
      if (!mounted) return;
      setState(() {
        _dailyTasks = tasks.where((t) => t.type == 'daily').toList();
        _goalTasks = tasks.where((t) => t.type == 'goal').toList();
        print('TasksScreen: Daily tasks: ${_dailyTasks.length}, Goal tasks: ${_goalTasks.length}');
        _isLoading = false;
      });
    } catch (e) {
      print('TasksScreen: Error loading tasks: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('タスクの読み込みに失敗しました: $e')),
      );
    }
  }

  Future<void> _addTask() async {
    if (_isAdding) return;
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const AddTaskDialog(),
    );

    if (result != null && mounted) {
      setState(() => _isAdding = true);
      try {
        await _taskService.createTask(
          content: result['content'],
          emoji: result['emoji'],
          type: result['type'],
        );
        await _loadTasks();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✨ タスクを追加しました！'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('タスクの追加に失敗しました: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isAdding = false);
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
          // 既に完了済みの場合
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
        // エラーメッセージをユーザーフレンドリーに
        String errorMessage = '完了処理に失敗しました';
        if (e.toString().contains('already-exists')) {
          errorMessage = '✅ このタスクは既に完了しています';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    }
  }

  Future<void> _deleteTask(TaskModel task) async {
    try {
      await _taskService.deleteTask(task.id);
      await _loadTasks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('タスクを削除しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除に失敗しました: $e')),
        );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.message!)),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('取り消しに失敗しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('ログインが必要です')),
      );
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
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.today, size: 20),
                  const SizedBox(width: 8),
                  const Text('デイリー'),
                  if (_dailyTasks.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_dailyTasks.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.flag, size: 20),
                  const SizedBox(width: 8),
                  const Text('目標'),
                  if (_goalTasks.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_goalTasks.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Theme.of(context).primaryColor,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTaskList(_dailyTasks, 'daily'),
                _buildTaskList(_goalTasks, 'goal'),
              ],
            ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 120), // ナビゲーションバーの上に配置
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

  Widget _buildTaskList(List<TaskModel> tasks, String type) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type == 'daily' ? Icons.today : Icons.flag,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              type == 'daily'
                  ? '毎日のタスクを追加しよう！'
                  : '目標を設定しよう！',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '完了すると徳ポイントがもらえるよ ✨',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 100), // FABの分のスペース
          ],
        ),
      );
    }

    // 完了状態でソート（未完了を上に）
    final sortedTasks = [...tasks];
    sortedTasks.sort((a, b) {
      final aCompleted = a.isCompletedToday || (a.isGoal && a.isCompleted);
      final bCompleted = b.isCompletedToday || (b.isGoal && b.isCompleted);
      if (aCompleted && !bCompleted) return 1;
      if (!aCompleted && bCompleted) return -1;
      return 0;
    });

    // 進捗を計算
    final completedCount = sortedTasks
        .where((t) => t.isCompletedToday || (t.isGoal && t.isCompleted))
        .length;
    final progress = tasks.isEmpty ? 0.0 : completedCount / tasks.length;

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // 進捗バー
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor.withAlpha(25),
                  Theme.of(context).primaryColor.withAlpha(13),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      type == 'daily' ? '今日の進捗' : '目標達成状況',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '$completedCount / ${tasks.length}',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white,
                    minHeight: 8,
                  ),
                ),
                if (progress == 1.0) ...[
                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      '🎉 全部完了！素晴らしい！',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // タスクリスト
          ...sortedTasks.map((task) => TaskCard(
                task: task,
                onComplete: () => _completeTask(task),
                onUncomplete: () => _uncompleteTask(task),
                onDelete: () => _deleteTask(task),
              )),
        ],
      ),
    );
  }
}


