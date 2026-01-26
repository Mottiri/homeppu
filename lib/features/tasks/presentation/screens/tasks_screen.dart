import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:confetti/confetti.dart';
import '../../../../shared/models/task_model.dart';
import '../../../../shared/models/category_model.dart';
import '../../../../shared/providers/task_screen_provider.dart';
import '../../../../shared/services/task_service.dart';
import '../../../../shared/services/category_service.dart';
import '../../../../shared/services/post_service.dart';
import '../../../../shared/services/goal_service.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/utils/dialog_helper.dart';
import '../../../../core/constants/app_messages.dart';

import '../widgets/task_detail_sheet.dart';
import '../widgets/task_calendar_header.dart';
import '../widgets/task_filter_bar.dart';
import '../widgets/task_edit_mode_bar.dart';
import '../widgets/task_list_view.dart';

class TasksScreen extends ConsumerStatefulWidget {
  final String? highlightTaskId;
  final int? highlightRequestId;
  final DateTime? targetDate;
  final String? targetCategoryId;

  const TasksScreen({
    super.key,
    this.highlightTaskId,
    this.highlightRequestId,
    this.targetDate,
    this.targetCategoryId,
  });

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _highlightPulseDuration =
      Duration(milliseconds: 800);
  static final Duration _highlightDisplayDuration = Duration(
    milliseconds: _highlightPulseDuration.inMilliseconds * 2,
  );
  final TaskService _taskService = TaskService();
  final CategoryService _categoryService = CategoryService();
  final PostService _postService = PostService();
  final GoalService _goalService = GoalService();
  late TabController _tabController;
  late PageController _pageController;
  final int _initialPage = 10000;
  late DateTime _anchorDate;
  bool _suppressNextPageChange = false;

  // Edit Mode Interaction
  bool _isEditMode = false;
  final Set<String> _selectedTaskIds = {};
  late AnimationController _shakeController;

  // Confetti Controller for streak milestone celebration
  late ConfettiController _confettiController;

  List<CategoryModel> _categories = [];

  // カテゴリごとのタスクリスト
  // List<TaskModel> _dailyTasks = []; // Removed
  Map<String, List<TaskModel>> _categoryTasks = {}; // categoryId -> tasks
  List<TaskModel> _defaultTasks = []; // カテゴリなしタスク

  bool _isLoading = true;

  DateTime _selectedDate = DateTime.now();
  Map<DateTime, List<TaskModel>> _taskData = {};

  // 直近で完了したタスクのID (即時ソートによるジャンプを防ぐため)
  final Set<String> _recentlyCompletedTaskIds = {};

  // ハイライト対象タスクID
  String? _highlightTaskId;

  // ??????????ID
  int? _highlightRequestId;

  // 目標カテゴリID（外部から指定された場合）
  String? _targetCategoryId;

  // タスクリストのScrollController
  final ScrollController _taskListScrollController = ScrollController();
  bool _hasScrolledToHighlight = false;

  // FAB表示制御
  bool _isFabVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _tabController = TabController(length: 2, vsync: this); // 初期値
    _tabController.addListener(_handleTabSelection);

    // アンカー日付を固定（セッション中に日付が変わってもインデックスがずれないように）
    final now = DateTime.now();
    _anchorDate = DateTime(now.year, now.month, now.day);

    // 目標日付がある場合はその日付に移動
    if (widget.targetDate != null) {
      _selectedDate = widget.targetDate!;
      // 初期ページをtargetDateに基づいて計算
      final targetDateOnly = DateTime(
        widget.targetDate!.year,
        widget.targetDate!.month,
        widget.targetDate!.day,
      );
      final diff = targetDateOnly.difference(_anchorDate).inDays;
      _pageController = PageController(initialPage: _initialPage + diff);
    } else {
      _pageController = PageController(initialPage: _initialPage);
    }

    // プロバイダーの初期値を設定
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(selectedDateProvider.notifier).state = _selectedDate;
      }
    });

    // 振動アニメーション用 (小刻みに震える)
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    // Confetti controller for milestone celebrations
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );

    // ハイライト対象の設定
    _highlightTaskId = widget.highlightTaskId;
    _highlightRequestId = widget.highlightRequestId;

    // 目標カテゴリIDの設定
    _targetCategoryId = widget.targetCategoryId;

    _loadData();
  }

  @override
  void didUpdateWidget(TasksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final requestChanged = widget.highlightRequestId != null &&
        widget.highlightRequestId != _highlightRequestId;
    final shouldClearHighlight =
        widget.highlightRequestId == null && _highlightRequestId != null;
    final targetCategoryChanged =
        widget.targetCategoryId != oldWidget.targetCategoryId;
    final shouldApplyTargetCategory = requestChanged || targetCategoryChanged;
    if (requestChanged || shouldClearHighlight) {
      setState(() {
        _highlightTaskId = widget.highlightTaskId;
        _highlightRequestId = widget.highlightRequestId;
        _hasScrolledToHighlight = false;
      });
    }
    if (shouldApplyTargetCategory) {
      if (widget.targetCategoryId == null) {
        _targetCategoryId = null;
        if (_tabController.index != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_tabController.index != 0) {
              _tabController.animateTo(0);
            }
          });
        }
      }
      if (widget.targetCategoryId != null) {
        final targetIndex = _categories.indexWhere(
          (category) => category.id == widget.targetCategoryId,
        );
        if (targetIndex >= 0) {
          final tabIndex = targetIndex + 1;
          if (_tabController.index != tabIndex &&
              tabIndex < _tabController.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_tabController.index != tabIndex &&
                  tabIndex < _tabController.length) {
                _tabController.animateTo(tabIndex);
              }
            });
          }
        } else {
          _targetCategoryId = widget.targetCategoryId;
        }
      }
    }

    if (widget.targetDate != null &&
        widget.targetDate != oldWidget.targetDate) {
      setState(() {
        _selectedDate = widget.targetDate!;
      });
      final page = _getPageIndex(_selectedDate);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(selectedDateProvider.notifier).state = _selectedDate;
        _jumpToPageIfNeeded(page);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _pageController.dispose();
    _shakeController.dispose();
    _confettiController.dispose();
    _taskListScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // アプリがフォアグラウンドに戻ったときにサーバーからリフレッシュ
    if (state == AppLifecycleState.resumed) {
      _loadData(showLoading: false, forceRefresh: true);
    }
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


  void _jumpToPageIfNeeded(int page) {
    if (!_pageController.hasClients) return;
    final currentPage =
        _pageController.page?.round() ?? _pageController.initialPage;
    if (currentPage == page) return;
    _suppressNextPageChange = true;
    _pageController.jumpToPage(page);
  }

  void _setSelectedDate(
    DateTime date, {
    bool jumpToPage = false,
    bool clearHighlight = false,
  }) {
    setState(() {
      _selectedDate = date;
      if (clearHighlight) {
        _highlightTaskId = null;
        _hasScrolledToHighlight = false;
      }
    });
    ref.read(selectedDateProvider.notifier).state = date;
    if (jumpToPage) {
      final page = _getPageIndex(date);
      _jumpToPageIfNeeded(page);
    }
  }

  void _handleHighlightScrolled() {
    if (_hasScrolledToHighlight) return;
    _hasScrolledToHighlight = true;
    Future.delayed(_highlightDisplayDuration, () {
      if (!mounted) return;
      setState(() {
        _highlightTaskId = null;
        _hasScrolledToHighlight = false;
      });
    });
  }

  Future<void> _loadData({
    bool showLoading = true,
    bool forceRefresh = true, // デフォルトでサーバーから取得
  }) async {
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
        _taskService.getTasks(userId: user.uid, forceRefresh: forceRefresh),
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
            if (a.priority != b.priority) return b.priority - a.priority;
            return 0;
          });
        }

        // TabControllerの再構築をsetState内で行う
        if (_tabController.length != tabCount) {
          int initialIndex = 0;

          // targetCategoryIdが指定されている場合、そのカテゴリのタブに移動
          if (_targetCategoryId != null) {
            final catIndex = categories.indexWhere(
              (c) => c.id == _targetCategoryId,
            );
            if (catIndex >= 0) {
              // index 0 = タスク(デフォルト), 1+ = カスタムカテゴリ
              initialIndex = catIndex + 1;
            }
            // 一度使用したらクリア
            _targetCategoryId = null;
          } else if (_tabController.length > 0) {
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
      SnackBarHelper.showError(context, AppMessages.error.general);
      debugPrint('読み込みに失敗: $e');
    }
  }

  // ... (handleTabSelection, showAddCategoryDialog, etc are defined at the bottom of the file)

  Future<void> _handleUpdateTask(TaskModel task, String editMode) async {
    try {
      // Optimistic Update: 即座にローカルUIを更新
      setState(() {
        _updateTaskLocally(task);
      });

      // カレンダー連携削除済み
      await _taskService.updateTask(task, editMode: editMode);

      // サーバー同期（サイレント）
      await _loadData(showLoading: false);
    } catch (e) {
      // エラー時はリロード
      await _loadData(showLoading: false);
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
        debugPrint('更新に失敗: $e');
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
        _recentlyCompletedTaskIds.add(task.id);
        _updateTaskLocally(updatedTask);
      });

      // API Call - returns new streak count
      final newStreak = await _taskService.completeTask(task.id);

      // Update local task with new streak for real-time display
      if (mounted && newStreak > 0) {
        final taskWithStreak = task.copyWith(
          isCompleted: true,
          lastCompletedAt: DateTime.now(),
          streak: newStreak,
        );
        setState(() {
          _updateTaskLocally(taskWithStreak);
        });
      }

      // Check for milestone achievement (streak)
      bool isMilestone = TaskService.isMilestone(newStreak);

      // Check for Goal completion
      bool isGoalCompleted = false;
      String? goalTitle;
      if (task.goalId != null && task.goalId!.isNotEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final progress = await _goalService.getGoalProgress(
            task.goalId!,
            userId: user.uid,
          );
          final completedCount = progress[0] + 1; // +1 for this task
          final totalCount = progress[1];
          if (completedCount >= totalCount && totalCount > 0) {
            isGoalCompleted = true;
            // 目標タイトルを取得
            final goalDoc = await FirebaseFirestore.instance
                .collection('goals')
                .doc(task.goalId!)
                .get();
            if (goalDoc.exists) {
              goalTitle = goalDoc.data()?['title'] as String? ?? '目標';
            } else {
              goalTitle = '目標';
            }
          }
        }
      }

      // Use a variable to track if a post was actually made
      bool didPost = false;

      // Auto-post if milestone or goal completion
      if (isMilestone || isGoalCompleted) {
        final user = FirebaseAuth.instance.currentUser;
        final userAsync = ref.read(currentUserProvider);
        final userData = userAsync.valueOrNull;

        if (user != null && userData != null) {
          // Check Auto Post Settings
          final autoPostSettings = userData.autoPostSettings;
          final isMilestoneEnabled = autoPostSettings['milestones'] ?? true;
          final isGoalEnabled = autoPostSettings['goals'] ?? true;

          bool shouldPost = false;
          bool isGoalPost = false;

          if (isGoalCompleted && isGoalEnabled) {
            shouldPost = true;
            isGoalPost = true;
          } else if (isMilestone && isMilestoneEnabled) {
            shouldPost = true;
            isGoalPost = false;
          }

          if (shouldPost) {
            final postId = await _postService.createTaskCompletionPost(
              userId: user.uid,
              userDisplayName: userData.displayName,
              userAvatarIndex: userData.avatarIndex,
              taskContent: task.content,
              streak: newStreak,
              isGoalCompletion: isGoalPost,
              goalTitle: goalTitle,
            );

            // Save post ID to task for undo
            if (postId != null) {
              await _taskService.saveCompletionPostId(task.id, postId);
              didPost = true;
            }
          }

          // Celebration!
          if (mounted) {
            _confettiController.play();
          }
        }
      }

      if (mounted) {
        // Custom snackbar message
        String message;
        if (isGoalCompleted) {
          message = didPost
              ? AppMessages.success.goalCompletedWithPost
              : AppMessages.success.goalCompleted;
        } else if (isMilestone) {
          final milestoneMsg = TaskService.getMilestoneMessage(newStreak);
          message = didPost
              ? AppMessages.success.taskMilestoneWithPost(newStreak, milestoneMsg)
              : AppMessages.success.taskMilestone(newStreak, milestoneMsg);
        } else {
          message = AppMessages.success.taskCompletedWithVirtue(newStreak);
        }

        SnackBarHelper.showSuccess(
          context,
          message,
          duration: Duration(seconds: isMilestone || isGoalCompleted ? 4 : 2),
        );
      }
    } catch (e) {
      // Revert on error
      await _loadData(showLoading: false);
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
        debugPrint('完了処理に失敗: $e');
      }
    }
  }

  Future<void> _deleteTask(TaskModel task, {bool deleteAll = false}) async {
    // Optimistic Update
    setState(() {
      if (deleteAll && task.recurrenceGroupId != null) {
        _removeTaskSeriesLocally(
          task.recurrenceGroupId!,
          task.scheduledAt ?? DateTime.now(),
        );
      } else {
        _removeTaskLocally(task.id);
      }
      // 選択中リストからも削除（一括削除でエラーにならないように）
      _selectedTaskIds.remove(task.id);
    });

    try {
      // カレンダー連携削除済み
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _taskService.deleteTask(
          task.id,
          userId: user.uid,
          recurrenceGroupId: task.recurrenceGroupId,
          deleteAll: deleteAll,
          startDate: task.scheduledAt,
        );
      }

      // await _loadData(); // Removed to avoid flicker
      if (mounted) {
        SnackBarHelper.showSuccess(context, AppMessages.success.taskDeleted);
      }
    } catch (e) {
      // Revert if needed
      _loadData();
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
        debugPrint('削除に失敗: $e');
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
        _recentlyCompletedTaskIds.remove(task.id);
        _updateTaskLocally(updatedTask);
      });

      // API Call - returns postId to delete if any
      final postIdToDelete = await _taskService.uncompleteTask(task.id);

      // Delete auto-post if it exists
      bool postDeleted = false;
      if (postIdToDelete != null && postIdToDelete.isNotEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          postDeleted = await _postService.deletePostById(
            postIdToDelete,
            user.uid,
          );
        }
      }

      await _loadData(showLoading: false);

      if (mounted) {
        final message = postDeleted
            ? AppMessages.success.taskCompletionRevertedWithPostDeleted
            : AppMessages.success.taskCompletionReverted;
        SnackBarHelper.showInfo(context, message);
      }
    } catch (e) {
      await _loadData(showLoading: false);
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
        debugPrint('取り消しに失敗: $e');
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
        onDelete: ({bool deleteAll = false}) =>
            _deleteTask(task, deleteAll: deleteAll),
        categories: _categories,
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

  void _removeTaskSeriesLocally(String groupId, DateTime startDate) {
    bool shouldRemove(TaskModel t) {
      if (t.recurrenceGroupId != groupId) return false;
      if (t.scheduledAt == null) return false;
      // scheduledAt >= startDate
      return t.scheduledAt!.isAtSameMomentAs(startDate) ||
          t.scheduledAt!.isAfter(startDate);
    }

    // 1. Remove from _defaultTasks
    _defaultTasks.removeWhere(shouldRemove);

    // 2. Remove from _categoryTasks
    for (var key in _categoryTasks.keys) {
      _categoryTasks[key]?.removeWhere(shouldRemove);
    }

    // 3. Remove from _taskData
    for (var key in _taskData.keys) {
      // 日付がstartDateより前の場合はチェック不要だが、
      // 念のため全チェックするか、日付比較でskipする。
      // _taskData key is DateTime (00:00:00).
      // If key < startDate (ignoring time?), wait.
      // startDate includes time probably. comparison should be safe.
      _taskData[key]?.removeWhere(shouldRemove);
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
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(AppMessages.confirm.deleteTasksTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppMessages.confirm.deleteTasksMessage(count),
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
                  Text(AppMessages.label.dontShowAgain),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppMessages.label.cancel),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppMessages.label.delete),
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
        SnackBarHelper.showSuccess(
          context,
          AppMessages.success.taskDeletedCount(idsToDelete.length),
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
        debugPrint('削除に失敗: $e');
        await _loadData(); // Sync on error
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(child: Text(AppMessages.error.loginRequired)),
      );
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

    final filterBar = TaskFilterBar(
      controller: _tabController,
      tabs: tabs,
    );

    return Scaffold(
      resizeToAvoidBottomInset: false, // キーボード表示時に背景がリサイズされてオーバーフローするのを防ぐ
      backgroundColor: Colors.grey.shade50,
      appBar: _isEditMode
          ? TaskEditModeBar(
              selectedCount: _selectedTaskIds.length,
              onClose: () => _toggleEditMode(false),
              onDelete: _selectedTaskIds.isEmpty ? null : _deleteSelectedTasks,
              bottom: filterBar,
            )
          : AppBar(
              title: const Text('やることリスト'),
              centerTitle: true,
              elevation: 0,
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.black87,
              bottom: filterBar,
              actions: [
                IconButton(
                  icon: const Icon(Icons.flag_outlined),
                  onPressed: () => context.push('/goals'),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_month),
                  onPressed: () async {
                    final selectedDate = await context.push<DateTime>(
                      '/monthly-calendar',
                      extra: {'initialDate': _selectedDate, 'tasks': _taskData},
                    );

                    if (selectedDate != null && mounted) {
                      _setSelectedDate(
                        selectedDate,
                        jumpToPage: true,
                        clearHighlight: true,
                      );
                    }
                  },
                ),
              ],
            ),
      body: Stack(
        children: [
          // Main content
          Column(
            children: [
              TaskCalendarHeader(
                selectedDate: _selectedDate,
                onDateSelected: (date) {
                  _setSelectedDate(
                    date,
                    jumpToPage: true,
                    clearHighlight: true,
                  );
                },
                taskData: _taskData,
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : PageView.builder(
                        controller: _pageController,
                        physics: const PageScrollPhysics(),
                        onPageChanged: (index) {
                          if (_suppressNextPageChange) {
                            _suppressNextPageChange = false;
                            return;
                          }
                          final newDate = _getDateFromIndex(index);
                          _setSelectedDate(newDate, clearHighlight: true);
                        },
                        itemBuilder: (context, index) {
                          final date = _getDateFromIndex(index);
                          final shakeAnimation =
                              Tween<double>(begin: -0.02, end: 0.02).animate(
                                CurvedAnimation(
                                  parent: _shakeController,
                                  curve: Curves.easeInOut,
                                ),
                              );

                          return TabBarView(
                            controller: _tabController,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              TaskListView(
                                tasks: _defaultTasks,
                                type: 'task',
                                category: null,
                                targetDate: date,
                                isEditMode: _isEditMode,
                                selectedTaskIds: _selectedTaskIds,
                                highlightTaskId: _highlightTaskId,
                                hasScrolledToHighlight: _hasScrolledToHighlight,
                                scrollController: _taskListScrollController,
                                shakeAnimation: shakeAnimation,
                                isFabVisible: _isFabVisible,
                                onFabVisibilityChanged: (isVisible) {
                                  setState(() => _isFabVisible = isVisible);
                                },
                                onTapTask: _showTaskDetail,
                                onCompleteTask: _completeTask,
                                onUncompleteTask: _uncompleteTask,
                                onDeleteTask: _deleteTask,
                                onToggleSelection: _toggleTaskSelection,
                                onLongPressTask: (task) {
                                  if (!_isEditMode) {
                                    _toggleEditMode(true);
                                    _toggleTaskSelection(task.id);
                                  }
                                },
                                onConfirmDismiss: () => _confirmDelete(1),
                                onExitEditMode: () => _toggleEditMode(false),
                                onDismissHighlight: () =>
                                    setState(() => _highlightTaskId = null),
                                onHighlightScrolled: _handleHighlightScrolled,
                              ),
                              ..._categories.map(
                                (cat) => TaskListView(
                                  tasks: _categoryTasks[cat.id] ?? [],
                                  type: 'custom',
                                  category: cat,
                                  targetDate: date,
                                  isEditMode: _isEditMode,
                                  selectedTaskIds: _selectedTaskIds,
                                  highlightTaskId: _highlightTaskId,
                                  hasScrolledToHighlight: _hasScrolledToHighlight,
                                  scrollController: _taskListScrollController,
                                  shakeAnimation: shakeAnimation,
                                  isFabVisible: _isFabVisible,
                                  onFabVisibilityChanged: (isVisible) {
                                    setState(() => _isFabVisible = isVisible);
                                  },
                                  onTapTask: _showTaskDetail,
                                  onCompleteTask: _completeTask,
                                  onUncompleteTask: _uncompleteTask,
                                  onDeleteTask: _deleteTask,
                                  onToggleSelection: _toggleTaskSelection,
                                  onLongPressTask: (task) {
                                    if (!_isEditMode) {
                                      _toggleEditMode(true);
                                      _toggleTaskSelection(task.id);
                                    }
                                  },
                                  onConfirmDismiss: () => _confirmDelete(1),
                                  onExitEditMode: () => _toggleEditMode(false),
                                  onDismissHighlight: () =>
                                      setState(() => _highlightTaskId = null),
                                  onHighlightScrolled: _handleHighlightScrolled,
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
          // Confetti animation for milestone celebrations
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [
                Colors.green,
                Colors.blue,
                Colors.pink,
                Colors.orange,
                Colors.purple,
                Colors.yellow,
              ],
              numberOfParticles: 30,
              gravity: 0.2,
            ),
          ),
        ],
      ),
      // FABは削除（ボトムナビの中央ボタンに移動）
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

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) return;

    // +ボタン（最後のタブ）が押された場合
    if (_tabController.index == _tabController.length - 1) {
      // 直前のタブに戻す（UX的に）
      _tabController.animateTo(_tabController.previousIndex);
      _showAddCategoryDialog();
    } else {
      // 選択中のカテゴリIDをProviderに設定
      String? selectedCategoryId;
      if (_tabController.index == 0) {
        // デフォルト（タスク）タブ
        selectedCategoryId = null;
      } else if (_tabController.index > 0 &&
          _tabController.index <= _categories.length) {
        // カスタムカテゴリタブ
        selectedCategoryId = _categories[_tabController.index - 1].id;
      }
      ref.read(selectedCategoryIdProvider.notifier).state = selectedCategoryId;
      setState(() {});
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final name = await DialogHelper.showInputDialog(
      context: context,
      title: '新しいカテゴリ',
      hintText: 'カテゴリ名 (例: 仕事, 買い物)',
      confirmText: '追加',
    );
    if (name != null && name.trim().isNotEmpty) {
      await _categoryService.addCategory(name.trim());
      _loadData(); // リロードしてタブ更新
    }
  }

  Future<void> _showRenameCategoryDialog(CategoryModel category) async {
    final name = await DialogHelper.showInputDialog(
      context: context,
      title: 'カテゴリ名を変更',
      initialValue: category.name,
      hintText: '新しいカテゴリ名',
      confirmText: '変更',
    );
    if (name != null && name.trim().isNotEmpty) {
      await _categoryService.updateCategory(category.id, name.trim());
      _loadData();
    }
  }

  Future<void> _confirmDeleteCategory(CategoryModel category) async {
    final confirm = await DialogHelper.showConfirmDialog(
      context: context,
      title: AppMessages.confirm.deleteCategoryTitle,
      message: AppMessages.confirm.deleteCategoryMessage(category.name),
      confirmText: AppMessages.label.delete,
      isDangerous: true,
      barrierDismissible: false,
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
        SnackBarHelper.showSuccess(context, AppMessages.success.categoryDeleted);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
        debugPrint('カテゴリ削除に失敗: $e');
      }
    }
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
