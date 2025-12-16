import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../tasks/presentation/widgets/add_task_bottom_sheet.dart';
import '../../../../shared/services/task_service.dart';
import '../../../../shared/services/category_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/task_screen_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// メイン画面のシェル（ボトムナビゲーション）
class MainShell extends ConsumerStatefulWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  late Animation<double> _rotationAnimation;
  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  int _getCurrentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/circles')) return 1;
    if (location.startsWith('/tasks')) return 2;
    if (location.startsWith('/profile') || location.startsWith('/user'))
      return 3;
    return 0;
  }

  void _handleCenterButtonTap(BuildContext context, bool isTaskScreen) async {
    if (isTaskScreen) {
      // タスク作成ボトムシートを表示
      await _showAddTaskSheet(context);
    } else {
      // 投稿作成画面へ遷移
      context.push('/create-post');
    }
  }

  Future<void> _showAddTaskSheet(BuildContext context) async {
    final categoryService = CategoryService();
    final taskService = TaskService();
    final categories = await categoryService.getCategories();

    if (!mounted) return;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => AddTaskBottomSheet(
        categories: categories,
        initialCategoryId: null,
        initialScheduledDate: ref.read(selectedDateProvider),
      ),
      backgroundColor: Colors.transparent,
    );

    if (result != null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final content = result['content'] as String;
      final type = result['type'] as String;
      final priority = result['priority'] as int;
      final scheduledAt = result['scheduledAt'] as DateTime?;
      final emoji = result['emoji'] as String;
      final categoryId = result['categoryId'] as String?;
      final recurrenceInterval = result['recurrenceInterval'] as int?;
      final recurrenceUnit = result['recurrenceUnit'] as String?;
      final recurrenceDaysOfWeek = result['recurrenceDaysOfWeek'] as List<int>?;
      final recurrenceEndDate = result['recurrenceEndDate'] as DateTime?;
      final memo = result['memo'] as String?;
      final goalId = result['goalId'] as String?;
      final reminders = result['reminders'] as List<Map<String, dynamic>>?;

      await taskService.createTask(
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
        memo: memo,
        goalId: goalId,
        reminders: reminders,
      );

      // タスク画面をリフレッシュ
      if (mounted) {
        // 作成したタスクの日付を渡し、リフレッシュを要求
        // TasksScreen側で targetDate を受け取ってその日付にジャンプする
        context.go(
          '/tasks',
          extra: {
            'forceRefresh': true,
            'targetDate': scheduledAt ?? DateTime.now(),
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _getCurrentIndex(context);
    final isTaskScreen = currentIndex == 2;

    // 画面が変わったときにアニメーション
    if (currentIndex != _previousIndex) {
      if (isTaskScreen) {
        _rotationController.forward();
      } else if (_previousIndex == 2) {
        _rotationController.reverse();
      }
      _previousIndex = currentIndex;
    }

    // タスク画面用の色
    final taskButtonGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF81C784), // 淡いグリーン
        const Color(0xFF66BB6A),
      ],
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: widget.child,
      extendBody: true,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // ホーム
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'ホーム',
                  isActive: currentIndex == 0,
                  onTap: () => context.go('/home'),
                ),

                // サークル
                _NavItem(
                  icon: Icons.groups_outlined,
                  activeIcon: Icons.groups_rounded,
                  label: 'サークル',
                  isActive: currentIndex == 1,
                  onTap: () => context.go('/circles'),
                ),

                // 中央ボタン（投稿/タスク作成）
                GestureDetector(
                  onTap: () => _handleCenterButtonTap(context, isTaskScreen),
                  child: AnimatedBuilder(
                    animation: _rotationAnimation,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _rotationAnimation.value * 3.14159, // 180度回転
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: isTaskScreen
                                ? taskButtonGradient
                                : AppColors.primaryGradient,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: isTaskScreen
                                    ? const Color(0xFF66BB6A).withOpacity(0.4)
                                    : AppColors.primary.withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            isTaskScreen ? Icons.add_task : Icons.add_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // タスク
                _NavItem(
                  icon: Icons.check_circle_outline,
                  activeIcon: Icons.check_circle_rounded,
                  label: 'タスク',
                  isActive: currentIndex == 2,
                  onTap: () => context.go('/tasks'),
                ),

                // マイページ
                _NavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person_rounded,
                  label: 'マイページ',
                  isActive: currentIndex == 3,
                  onTap: () => context.go('/profile'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ナビゲーションアイテム
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? AppColors.primary : AppColors.textHint,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? AppColors.primary : AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
