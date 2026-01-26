// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../tasks/presentation/widgets/add_task_bottom_sheet.dart';
import '../../../../shared/services/task_service.dart';
import '../../../../shared/services/category_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/task_screen_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../shared/providers/auth_provider.dart'; // currentUserProvider
import 'home_screen.dart'; // timelineRefreshProvider, homeScrollToTopProvider
import '../../../circle/presentation/screens/circles_screen.dart'; // circleScrollToTopProvider

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
    if (location.startsWith('/profile') || location.startsWith('/user')) {
      return 3;
    }
    return 0;
  }

  void _handleCenterButtonTap(BuildContext context, int currentIndex) async {
    // BANチェック
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.isBanned == true) {
      final message = currentUser?.banStatus == 'permanent'
          ? AppMessages.error.accountSuspended
          : AppMessages.error.banned;
      SnackBarHelper.showError(context, message);
      return;
    }

    if (currentIndex == 2) {
      // タスク画面：タスク作成ボトムシートを表示
      await _showAddTaskSheet(context);
    } else if (currentIndex == 1) {
      // サークル画面：サークル作成画面へ遷移
      context.push('/create-circle');
    } else {
      // その他（ホーム等）：投稿作成画面へ遷移
      final result = await context.push<bool>('/create-post');

      // 投稿作成成功後、タイムラインをリロード
      if (result == true && mounted) {
        ref.read(timelineRefreshProvider.notifier).state++;
      }
    }
  }

  Future<void> _showAddTaskSheet(BuildContext context) async {
    final categoryService = CategoryService();
    final taskService = TaskService();
    final categories = await categoryService.getCategories();

    if (!mounted) return;

    // 現在選択中のカテゴリIDを取得
    final selectedCategoryId = ref.read(selectedCategoryIdProvider);

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => AddTaskBottomSheet(
        categories: categories,
        initialCategoryId: selectedCategoryId,
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
    // 永久BANチェック
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    if (currentUser?.banStatus == 'permanent') {
      // 描画完了後に遷移
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (GoRouterState.of(context).matchedLocation != '/ban-appeal') {
          context.go('/ban-appeal');
        }
      });
    }

    final currentIndex = _getCurrentIndex(context);

    // 画面が変わったときにアニメーション
    if (currentIndex != _previousIndex) {
      final wasSpecialScreen = _previousIndex == 1 || _previousIndex == 2;
      final isSpecialScreen = currentIndex == 1 || currentIndex == 2;

      if (isSpecialScreen && !wasSpecialScreen) {
        // ホーム/マイページ → サークル/タスク: 回転アニメーション
        _rotationController.forward();
      } else if (!isSpecialScreen && wasSpecialScreen) {
        // サークル/タスク → ホーム/マイページ: 逆回転
        _rotationController.reverse();
      } else if (isSpecialScreen && wasSpecialScreen) {
        // サークル ↔ タスク: 一度戻して再び回転
        _rotationController.reverse().then((_) {
          if (mounted) _rotationController.forward();
        });
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
              color: AppColors.primary.withValues(alpha: 0.1),
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
                  onTap: () {
                    if (currentIndex == 0) {
                      // 既にホーム画面の場合はスクロールトップ
                      ref.read(homeScrollToTopProvider.notifier).state++;
                    } else {
                      context.go('/home');
                    }
                  },
                ),

                // サークル
                _NavItem(
                  icon: Icons.groups_outlined,
                  activeIcon: Icons.groups_rounded,
                  label: 'サークル',
                  isActive: currentIndex == 1,
                  onTap: () {
                    if (currentIndex == 1) {
                      // 既にサークル画面の場合はスクロールトップ
                      ref.read(circleScrollToTopProvider.notifier).state++;
                    } else {
                      context.go('/circles');
                    }
                  },
                ),

                // 中央ボタン（投稿/タスク作成/サークル作成）
                GestureDetector(
                  onTap: () => _handleCenterButtonTap(context, currentIndex),
                  child: AnimatedBuilder(
                    animation: _rotationAnimation,
                    builder: (context, child) {
                      // 画面ごとのカラーとアイコン
                      final isTaskScreen = currentIndex == 2;
                      final isCircleScreen = currentIndex == 1;
                      final isSpecialScreen = isTaskScreen || isCircleScreen;

                      // サークル用シアングラデーション
                      const circleButtonGradient = LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF4DD0E1), // シアン明
                          Color(0xFF00ACC1), // シアン暗
                        ],
                      );

                      LinearGradient buttonGradient;
                      Color shadowColor;
                      IconData buttonIcon;
                      double iconSize;

                      if (isTaskScreen) {
                        buttonGradient = taskButtonGradient;
                        shadowColor = const Color(0xFF66BB6A);
                        buttonIcon = Icons.add_task;
                        iconSize = 28;
                      } else if (isCircleScreen) {
                        buttonGradient = circleButtonGradient;
                        shadowColor = const Color(0xFF00ACC1);
                        buttonIcon = Icons.group_add_rounded;
                        iconSize = 26; // サークルアイコンを小さく
                      } else {
                        buttonGradient = AppColors.primaryGradient;
                        shadowColor = AppColors.primary;
                        buttonIcon = Icons.add_rounded;
                        iconSize = 32;
                      }

                      // 回転角度: ホーム→特別画面で180度回転
                      final rotationAngle = isSpecialScreen
                          ? _rotationAnimation.value * 3.14159
                          : 0.0;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: buttonGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: shadowColor.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Transform.rotate(
                          angle: rotationAngle,
                          child: Transform.rotate(
                            // タスク・サークルアイコンを90度左回転で正しい向きに
                            angle: (isTaskScreen || isCircleScreen)
                                ? -1.5708
                                : 0, // -90度
                            child: Icon(
                              buttonIcon,
                              color: Colors.white,
                              size: iconSize,
                            ),
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
