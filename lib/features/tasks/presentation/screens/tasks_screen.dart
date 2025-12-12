import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../shared/models/task_model.dart';
import '../../../../shared/models/category_model.dart';
import '../../../../shared/services/task_service.dart';
import '../../../../shared/services/category_service.dart';
import '../widgets/add_task_bottom_sheet.dart';
import '../widgets/task_detail_sheet.dart';
import '../widgets/task_card.dart';
import '../widgets/week_calendar_strip.dart';
import 'monthly_calendar_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen>
    with TickerProviderStateMixin {
  final TaskService _taskService = TaskService();
  final CategoryService _categoryService = CategoryService();
  late TabController _tabController;
  late PageController _pageController;
  final int _initialPage = 10000;
  late DateTime _anchorDate;

  // Edit Mode Interaction
  bool _isEditMode = false;
  Set<String> _selectedTaskIds = {};
  late AnimationController _shakeController;

  List<CategoryModel> _categories = [];

  // カテゴリごとのタスクリスト
  // List<TaskModel> _dailyTasks = []; // Removed
  Map<String, List<TaskModel>> _categoryTasks = {}; // categoryId -> tasks
  List<TaskModel> _defaultTasks = []; // カテゴリなしタスク

  bool _isLoading = true;
  bool _isAdding = false;

  DateTime _selectedDate = DateTime.now();
  Map<DateTime, List<TaskModel>> _taskData = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); // 初期値
    _tabController.addListener(_handleTabSelection);
    _pageController = PageController(initialPage: _initialPage);

    // アンカー日付を固定（セッション中に日付が変わってもインデックスがずれないように）
    final now = DateTime.now();
    _anchorDate = DateTime(now.year, now.month, now.day);

    // 振動アニメーション用 (小刻みに震える)
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  DateTime _getDateFromIndex(int index) {
    // _anchorDate を基準にする
    final daysDifference = index - _initialPage;
    return _anchorDate.add(Duration(days: daysDifference));
  }

  int _getPageIndex(DateTime date) {
    // _anchorDate を基準にする
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(_anchorDate).inDays;
    return _initialPage + diff;
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) {
      setState(() => _isLoading = true);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (showLoading) {
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      // カテゴリとタスクを並行取得
      final results = await Future.wait([
        _categoryService.getCategories(),
        _taskService.getTasks(userId: user.uid),
      ]);

      if (!mounted) return;

      final categories = results[0] as List<CategoryModel>;
      final tasks = results[1] as List<TaskModel>;

      // ... (rest of logic same as before until setState)

      // タブコントローラーの再構築
      // Default + Custom + AddButton (Daily is removed)
      final tabCount = 1 + categories.length + 1;

      // タスク振り分け
      // Dailyもすべて"Default Task"または"Category Task"として扱う
      // final dailyTasks = tasks.where((t) => t.type == 'daily').toList(); // Removed
      final otherTasks = tasks; // All tasks (formerly just type!='daily')

      final defaultTasks = otherTasks
          .where((t) => t.categoryId == null || t.categoryId!.isEmpty)
          .toList();
      final categoryTasks = <String, List<TaskModel>>{};

      for (var cat in categories) {
        categoryTasks[cat.id] = otherTasks
            .where((t) => t.categoryId == cat.id)
            .toList();
      }

      setState(() {
        _categories = categories;

        // _dailyTasks = dailyTasks; // Removed
        _defaultTasks = defaultTasks;
        _categoryTasks = categoryTasks;

        // カレンダー用データ生成
        _taskData = {};
        for (final task in tasks) {
          if (task.scheduledAt != null) {
            final date = DateTime(
              task.scheduledAt!.year,
              task.scheduledAt!.month,
              task.scheduledAt!.day,
            );

            if (!_taskData.containsKey(date)) {
              _taskData[date] = [];
            }
            _taskData[date]!.add(task);
          }
        }

        // ソート
        for (final key in _taskData.keys) {
          _taskData[key]!.sort((a, b) {
            if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
            if (a.priority != b.priority) return b.priority - a.priority;
            return 0;
          });
        }

        // TabControllerの再構築をsetState内で行う
        if (_tabController.length != tabCount) {
          int initialIndex = 0;
          if (_tabController.length > 0) {
            initialIndex = _tabController.index;
            // 新しいタブ数に合わせてインデックスを調整
            if (initialIndex >= tabCount) initialIndex = 0;
          }

          _tabController.dispose();
          _tabController = TabController(
            length: tabCount,
            vsync: this,
            initialIndex: initialIndex,
          );
          _tabController.addListener(_handleTabSelection);
        }

        _isLoading = false;
      });
    } catch (e) {
      // ... err handling
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('読み込みに失敗しました: $e')));
    }
  }

  // ... (handleTabSelection, showAddCategoryDialog, etc are defined at the bottom of the file)

  Future<void> _handleUpdateTask(TaskModel task, String editMode) async {
    try {
      // カレンダー連携削除済み
      await _taskService.updateTask(task, editMode: editMode);
      await _loadData();
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
      // Optimistic Update
      final updatedTask = task.copyWith(
        isCompleted: true,
        lastCompletedAt: DateTime.now(), // Approximate
      );
      setState(() {
        _updateTaskLocally(updatedTask);
      });

      // API Call
      await _taskService.completeTask(task.id);

      // Async Sync (Silent)
      await _loadData(showLoading: false);

      if (mounted) {
        // 簡易メッセージ
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 タスク完了！ (+徳ポイント)'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Revert on error
      await _loadData(showLoading: false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('完了処理に失敗しました: $e')));
      }
    }
  }

  Future<void> _deleteTask(TaskModel task) async {
    // Optimistic Update
    setState(() {
      _removeTaskLocally(task.id);
    });

    try {
      // カレンダー連携削除済み
      await _taskService.deleteTask(task.id, userId: task.userId);
      // await _loadData(); // Removed to avoid flicker
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('タスクを削除しました')));
      }
    } catch (e) {
      // Revert if needed
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
  }

  Future<void> _uncompleteTask(TaskModel task) async {
    try {
      // Optimistic Update
      final updatedTask = task.copyWith(
        isCompleted: false,
        lastCompletedAt: null,
      );
      setState(() {
        _updateTaskLocally(updatedTask);
      });

      await _taskService.uncompleteTask(task.id);
      await _loadData(showLoading: false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('完了を取り消しました'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      await _loadData(showLoading: false);
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
      useRootNavigator: true, // ボトムナビゲーションの上に表示
      showDragHandle: true, // ドラッグハンドルを表示
      backgroundColor: Colors.white, // Handleが見やすいように
      builder: (context) => TaskDetailSheet(
        task: task,
        onUpdate: _handleUpdateTask,
        onDelete: () => _deleteTask(task),
      ),
    );
  }

  void _removeTaskLocally(String taskId) {
    // 1. Remove from _defaultTasks
    _defaultTasks.removeWhere((t) => t.id == taskId);

    // 2. Remove from _categoryTasks
    for (var key in _categoryTasks.keys) {
      _categoryTasks[key]?.removeWhere((t) => t.id == taskId);
    }

    // 3. Remove from _taskData (Calendar data)
    for (var key in _taskData.keys) {
      _taskData[key]?.removeWhere((t) => t.id == taskId);
    }
  }

  void _updateTaskLocally(TaskModel updatedTask) {
    // Helper to replace task in list
    void replaceInList(List<TaskModel> list) {
      final index = list.indexWhere((t) => t.id == updatedTask.id);
      if (index != -1) {
        list[index] = updatedTask;
      }
    }

    // 1. Update in _defaultTasks
    replaceInList(_defaultTasks);

    // 2. Update in _categoryTasks
    if (updatedTask.categoryId != null &&
        _categoryTasks.containsKey(updatedTask.categoryId)) {
      replaceInList(_categoryTasks[updatedTask.categoryId!]!);
    }

    // 3. Update in _taskData
    if (updatedTask.scheduledAt != null) {
      final date = DateTime(
        updatedTask.scheduledAt!.year,
        updatedTask.scheduledAt!.month,
        updatedTask.scheduledAt!.day,
      );
      if (_taskData.containsKey(date)) {
        replaceInList(_taskData[date]!);
      }
    }
  }

  int _calculateBadgeCount(List<TaskModel> tasks) {
    return tasks.where((task) {
      if (task.scheduledAt == null) {
        return isSameDay(_selectedDate, DateTime.now());
      }
      return isSameDay(task.scheduledAt!, _selectedDate);
    }).length;
  }

  void _toggleEditMode(bool active) {
    setState(() {
      _isEditMode = active;
      if (active) {
        _shakeController.repeat(reverse: true);
        _selectedTaskIds.clear();
      } else {
        _shakeController.stop();
        _shakeController.reset();
        _selectedTaskIds.clear(); // 終了時リセット
      }
    });
  }

  void _toggleTaskSelection(String taskId) {
    setState(() {
      if (_selectedTaskIds.contains(taskId)) {
        _selectedTaskIds.remove(taskId);
      } else {
        _selectedTaskIds.add(taskId);
      }
    });
  }

  Future<bool> _confirmDelete(int count) async {
    final prefs = await SharedPreferences.getInstance();
    final skipConfirm = prefs.getBool('skipDeleteConfirm') ?? false;

    if (skipConfirm) return true;

    bool dontShowAgain = false;

    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('タスクを削除'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count件のタスクを削除しますか？\n\n※繰り返し設定のあるタスクは、今日の分のみが削除されます（次回以降は残ります）。',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: dontShowAgain,
                    onChanged: (val) {
                      setState(() {
                        dontShowAgain = val ?? false;
                      });
                    },
                  ),
                  const Text('今後表示しない'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除'),
            ),
          ],
        ),
      ),
    );

    if (result == true && dontShowAgain) {
      await prefs.setBool('skipDeleteConfirm', true);
    }

    return result ?? false;
  }

  Future<void> _deleteSelectedTasks() async {
    if (_selectedTaskIds.isEmpty) return;

    final confirm = await _confirmDelete(_selectedTaskIds.length);

    if (confirm != true) return;

    final idsToDelete = _selectedTaskIds.toList();

    // Optimistic Update
    setState(() {
      _toggleEditMode(false); // 先にモード抜ける
      for (final id in idsToDelete) {
        _removeTaskLocally(id);
      }
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Parallel delete for speed
        await Future.wait(
          idsToDelete.map(
            (id) => _taskService.deleteTask(id, userId: user.uid),
          ),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${idsToDelete.length}件を削除しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
        await _loadData(); // Sync on error
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('ログインが必要です')));
    }

    // タブ生成
    final List<Widget> tabs = [];

    // 1. デイリー -> Removed
    /*
    tabs.add(
      _buildTab(
        context,
        Icons.today,
        'デイリー',
        _calculateBadgeCount(_dailyTasks),
        Theme.of(context).primaryColor,
        onTap: () => _tabController.animateTo(0),
      ),
    );
    */

    // 1. タスク (デフォルト) - Now First Tab (Index 0)
    tabs.add(
      _buildTab(
        context,
        Icons.check_circle_outline,
        'タスク',
        _calculateBadgeCount(_defaultTasks),
        Colors.blue,
        onTap: () => _tabController.animateTo(0),
      ),
    );

    // 2. カスタムカテゴリ - Starts from Index 1
    for (int i = 0; i < _categories.length; i++) {
      final cat = _categories[i];
      final tasks = _categoryTasks[cat.id] ?? [];
      final count = _calculateBadgeCount(tasks);

      // 色は順番に適当に回すか、固定にする
      final color = [
        Colors.orange,
        Colors.green,
        Colors.purple,
        Colors.teal,
      ][i % 4];

      tabs.add(
        _buildTab(
          context,
          Icons.label_outline,
          cat.name,
          count,
          color,
          onLongPress: () => _showCategoryActionSheet(cat),
          onTap: () => _tabController.animateTo(1 + i),
        ),
      );
    }

    // 3. 追加ボタン (+) - Last Tab
    tabs.add(
      const Tab(
        height: 36,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0),
          child: Icon(Icons.add_circle_outline, size: 24, color: Colors.grey),
        ),
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: false, // キーボード表示時に背景がリサイズされてオーバーフローするのを防ぐ
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: _isEditMode
            ? Text(
                '${_selectedTaskIds.length}件 選択中',
                style: const TextStyle(fontWeight: FontWeight.bold),
              )
            : const Text('やることリスト'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: _isEditMode
            ? Colors.orange.shade50
            : Colors.transparent,
        foregroundColor: Colors.black87,
        leading: _isEditMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => _toggleEditMode(false),
              )
            : null,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true, // タブが多くなるのでスクロール可に
          tabs: tabs,
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Theme.of(context).primaryColor,
          labelPadding: const EdgeInsets.symmetric(horizontal: 12.0),
          tabAlignment: TabAlignment.start, // 左寄せ
        ),
        actions: _isEditMode
            ? [
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: _selectedTaskIds.isEmpty
                      ? null
                      : _deleteSelectedTasks,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.calendar_month),
                  onPressed: () async {
                    final selectedDate = await Navigator.push<DateTime>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MonthlyCalendarScreen(
                          initialDate: _selectedDate,
                          tasks: _taskData,
                        ),
                      ),
                    );

                    if (selectedDate != null && mounted) {
                      setState(() {
                        _selectedDate = selectedDate;
                      });
                      final page = _getPageIndex(selectedDate);
                      _pageController.jumpToPage(page);
                    }
                  },
                ),
              ],
      ),
      body: Column(
        children: [
          WeekCalendarStrip(
            selectedDate: _selectedDate,
            onDateSelected: (date) {
              setState(() => _selectedDate = date);
              final page = _getPageIndex(date);
              _pageController.jumpToPage(page);
            },
            tasks: _taskData,
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : PageView.builder(
                    controller: _pageController,
                    physics: _isEditMode
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    onPageChanged: (index) {
                      final newDate = _getDateFromIndex(index);
                      setState(() {
                        _selectedDate = newDate;
                      });
                    },
                    itemBuilder: (context, index) {
                      final date = _getDateFromIndex(index);
                      return TabBarView(
                        controller: _tabController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildTaskList(_defaultTasks, 'task', null, date),
                          ..._categories.map(
                            (cat) => _buildTaskList(
                              _categoryTasks[cat.id] ?? [],
                              'custom',
                              cat,
                              date,
                            ),
                          ),
                          const SizedBox(),
                        ],
                      );
                    },
                  ),
          ),
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

  Widget _buildTab(
    BuildContext context,
    IconData icon,
    String label,
    int count,
    Color color, {
    VoidCallback? onLongPress,
    VoidCallback? onTap,
  }) {
    return Tab(
      height: 36,
      child: InkWell(
        onLongPress: onLongPress,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),

        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCategoryActionSheet(CategoryModel category) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('カテゴリ名を変更'),
                onTap: () {
                  Navigator.pop(context);
                  _showRenameCategoryDialog(category);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'カテゴリを削除',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteCategory(category);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTaskList(
    List<TaskModel> tasks,
    String type,
    CategoryModel? category,
    DateTime targetDate,
  ) {
    // コンテンツがない場合の表示
    if (tasks.isEmpty) {
      String message = 'タスクを追加しよう！';
      IconData icon = Icons.task_alt;

      if (type == 'daily') {
        message = '毎日のタスクを追加しよう！';
        icon = Icons.today;
      } else if (type == 'custom') {
        message = '${category?.name} のタスクを追加しよう！';
        icon = Icons.label_outline;
      }

      return GestureDetector(
        onTap: () {
          if (_isEditMode) {
            _toggleEditMode(false);
          }
        },
        behavior: HitTestBehavior.opaque,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        message,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    final sortedTasks = [...tasks];

    // フィルタリング: targetDate を使用
    final filteredTasks = sortedTasks.where((task) {
      if (task.scheduledAt == null) {
        return isSameDay(targetDate, DateTime.now());
      }
      return isSameDay(task.scheduledAt!, targetDate);
    }).toList();

    filteredTasks.sort((a, b) {
      // 完了済みは下
      final aCompleted = a.isCompletedToday || a.isCompleted;
      final bCompleted = b.isCompletedToday || b.isCompleted;

      if (aCompleted != bCompleted) return aCompleted ? 1 : -1;
      // 優先度
      if (a.priority != b.priority) return b.priority - a.priority;
      // 日付
      if (a.scheduledAt != null && b.scheduledAt != null) {
        return a.scheduledAt!.compareTo(b.scheduledAt!);
      }
      return 0;
    });

    if (filteredTasks.isEmpty) {
      return GestureDetector(
        onTap: () {
          if (_isEditMode) {
            _toggleEditMode(false);
          }
        },
        behavior: HitTestBehavior.opaque,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.event_available,
                        size: 64,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'まだタスクがありません',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    // リスト表示
    // 振動アニメーション
    final shakeAnimation = Tween<double>(begin: -0.02, end: 0.02).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
    );

    return GestureDetector(
      onTap: () {
        if (_isEditMode) {
          _toggleEditMode(false);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: filteredTasks.length,
        itemBuilder: (context, index) {
          final task = filteredTasks[index];
          return TaskCard(
            task: task,
            onTap: () => _showTaskDetail(task),
            onComplete: () => _completeTask(task),
            onUncomplete: () => _uncompleteTask(task),
            onDelete: () => _deleteTask(task),
            isEditMode: _isEditMode,
            isSelected: _selectedTaskIds.contains(task.id),
            onToggleSelection: () => _toggleTaskSelection(task.id),
            onLongPress: () {
              if (!_isEditMode) {
                _toggleEditMode(true);
                _toggleTaskSelection(task.id); // 長押ししたアイテムを選択状態にする
              }
            },
            shakeAnimation: shakeAnimation,
            onConfirmDismiss: () => _confirmDelete(1),
          );
        },
      ),
    );
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) return;

    // +ボタン（最後のタブ）が押された場合
    if (_tabController.index == _tabController.length - 1) {
      // 直前のタブに戻す（UX的に）
      _tabController.animateTo(_tabController.previousIndex);
      _showAddCategoryDialog();
    } else {
      setState(() {});
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新しいカテゴリ'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'カテゴリ名 (例: 仕事, 買い物)'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context);
                await _categoryService.addCategory(name);
                _loadData(); // リロードしてタブ更新
              }
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameCategoryDialog(CategoryModel category) async {
    final controller = TextEditingController(text: category.name);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('カテゴリ名を変更'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '新しいカテゴリ名'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context);
                await _categoryService.updateCategory(category.id, name);
                _loadData();
              }
            },
            child: const Text('変更'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteCategory(CategoryModel category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('カテゴリを削除'),
        content: Text('「${category.name}」を削除しますか？\n含まれるタスクも削除されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _deleteCategoryWithTasks(category);
    }
  }

  Future<void> _deleteCategoryWithTasks(CategoryModel category) async {
    try {
      // カテゴリに関連するタスクを削除
      // ※本来はバッチ処理かサーバーサイドで行うべきだが、クライアントで簡易実装
      // 現在ロードされているタスクから探す
      final tasksToDelete = _categoryTasks[category.id] ?? <TaskModel>[]; // 型指定

      // 順次削除 (数が多いと遅いが許容)
      for (final task in tasksToDelete) {
        await _taskService.deleteTask(task.id, userId: task.userId);
      }

      await _categoryService.deleteCategory(category.id);
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('カテゴリを削除しました')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _addTask() async {
    if (_isAdding) return;
    setState(() => _isAdding = true);

    try {
      // 現在選択中のタブから初期値を決定
      final currentIndex = _tabController.index;
      String? initialCategoryId;

      // Tab mapping: 0=Default, 1..N=Categories
      if (currentIndex > 0 && currentIndex <= _categories.length) {
        final catIndex = currentIndex - 1;
        if (catIndex >= 0 && catIndex < _categories.length) {
          initialCategoryId = _categories[catIndex].id;
        }
      }

      final result = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true, // BottomNavigationBarの上に出すために必要
        builder: (context) => AddTaskBottomSheet(
          categories: _categories,
          initialCategoryId: initialCategoryId,
          initialScheduledDate: _selectedDate,
        ),
        backgroundColor: Colors.transparent,
      );

      if (result != null) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return; // Should not happen if logged in

        final content = result['content'] as String;
        final type = result['type'] as String;
        final priority = result['priority'] as int;
        final scheduledAt = result['scheduledAt'] as DateTime?;
        final emoji = result['emoji'] as String;
        final categoryId = result['categoryId'] as String?;
        final recurrenceInterval = result['recurrenceInterval'] as int?;
        final recurrenceUnit = result['recurrenceUnit'] as String?;
        final recurrenceDaysOfWeek =
            result['recurrenceDaysOfWeek'] as List<int>?;
        final recurrenceEndDate = result['recurrenceEndDate'] as DateTime?;

        await _taskService.createTask(
          userId: user.uid,
          content: content,
          emoji: emoji,
          type: type,
          scheduledAt: scheduledAt,
          priority: priority,
          categoryId: categoryId,
          recurrenceInterval: recurrenceInterval,
          recurrenceUnit: recurrenceUnit,
          recurrenceDaysOfWeek: recurrenceDaysOfWeek,
          recurrenceEndDate: recurrenceEndDate,
        );

        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('タスクを追加しました！がんばろう！'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('追加に失敗しました: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }
}
