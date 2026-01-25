import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/goal_model.dart';
import '../../../../shared/providers/goal_provider.dart';
import '../widgets/goal_card_with_stats.dart';
import '../widgets/empty_goals_view.dart';

class GoalListScreen extends ConsumerStatefulWidget {
  const GoalListScreen({super.key});

  @override
  ConsumerState<GoalListScreen> createState() => _GoalListScreenState();
}

class _GoalListScreenState extends ConsumerState<GoalListScreen>
    with TickerProviderStateMixin {
  bool _isReorderMode = false; // 並び替えモード
  late AnimationController _fabController;
  late Animation<double> _fabScaleAnimation;
  late AnimationController _jiggleController; // プルプルアニメーション用

  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fabScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _fabController, curve: Curves.easeInOut));

    _jiggleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _fabController.dispose();
    _jiggleController.dispose();
    super.dispose();
  }

  void _toggleReorderMode() {
    setState(() {
      _isReorderMode = !_isReorderMode;
      if (_isReorderMode) {
        _jiggleController.repeat(reverse: true);
      } else {
        _jiggleController.stop();
        _jiggleController.reset();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(child: Text(AppMessages.error.unauthorized)),
      );
    }

    final goalService = ref.read(goalServiceProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ヘッダーセクション
            _buildHeader(),

            // 進行中の目標
            StreamBuilder<List<GoalModel>>(
              stream: goalService.streamActiveGoals(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        AppMessages.goal.streamError,
                        style: TextStyle(color: AppColors.error),
                      ),
                    ),
                  );
                }
                final goals = snapshot.data ?? [];

                if (goals.isEmpty) {
                  return EmptyGoalsView(
                    onCreatePressed: () => context.push('/goals/create'),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.rocket_launch_rounded,
                              size: 16,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppMessages.goal.inProgressTitle,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${goals.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // 並び替えボタン
                          if (goals.length > 1)
                            TextButton.icon(
                              onPressed: _toggleReorderMode,
                              icon: Icon(
                                _isReorderMode ? Icons.check : Icons.swap_vert,
                                size: 18,
                                color: _isReorderMode
                                    ? Colors.green
                                    : AppColors.textSecondary,
                              ),
                              label: Text(
                                _isReorderMode
                                    ? AppMessages.goal.reorderDone
                                    : AppMessages.goal.reorderLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _isReorderMode
                                      ? Colors.green
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: goals.length,
                      proxyDecorator: (child, index, animation) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) {
                            final elevation = lerpDouble(
                              0,
                              8,
                              animation.value,
                            )!;
                            return Material(
                              elevation: elevation,
                              color: Colors.transparent,
                              shadowColor: Colors.black.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(20),
                              child: child,
                            );
                          },
                          child: child,
                        );
                      },
                      onReorder: (oldIndex, newIndex) async {
                        // Optimistic Update
                        final reorderedGoals = List<GoalModel>.from(goals);
                        if (oldIndex < newIndex) {
                          newIndex -= 1;
                        }
                        final item = reorderedGoals.removeAt(oldIndex);
                        reorderedGoals.insert(newIndex, item);

                        // Firestore更新
                        await goalService.reorderGoals(reorderedGoals);
                      },
                      itemBuilder: (context, index) {
                        final goal = goals[index];
                        // ランダムなオフセットで各カードが異なるタイミングで震える
                        final randomOffset = (index % 3) * 0.3;

                        Widget cardWidget = GoalCardWithStats(
                          goal: goal,
                          isReorderMode: _isReorderMode,
                          onDetailTap: _isReorderMode
                              ? null
                              : () => context.push('/goals/detail/${goal.id}'),
                        );
                        // 並び替えモード時のみプルプル
                        if (_isReorderMode) {
                          cardWidget = AnimatedBuilder(
                            animation: _jiggleController,
                            builder: (context, child) {
                              // -1.5度 〜 +1.5度 の回転
                              final angle =
                                  (_jiggleController.value - 0.5) * 0.05;
                              return Transform.rotate(
                                angle: angle + (randomOffset * 0.01),
                                child: child,
                              );
                            },
                            child: cardWidget,
                          );
                        }

                        return ReorderableDragStartListener(
                          key: ValueKey(goal.id),
                          index: index,
                          enabled: _isReorderMode, // 並び替えモード時のみ即座にドラッグ可能
                          child: cardWidget,
                        );
                      },
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),

            // 殿堂入りセクション
            _buildArchiveSection(goalService, user.uid),
          ],
        ),
      ),
      floatingActionButton: _buildFab(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.flag_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Text(AppMessages.goal.title),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.08),
            AppColors.secondary.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppMessages.goal.headerTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppMessages.goal.headerDescription,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.trending_up_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveSection(dynamic goalService, String userId) {
    // 殿堂入りボタン（タップで遷移）
    return GestureDetector(
      onTap: () => context.push('/goals/completed'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFFFFFBE6), const Color(0xFFFFF8E1)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFFD700).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFC107)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppMessages.goal.hallOfFameTitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFB8860B),
                ),
              ),
            ),
            Text(
              AppMessages.goal.hallOfFameSubtitle,
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFFB8860B).withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: const Color(0xFFB8860B)),
          ],
        ),
      ),
    );
  }

  Widget _buildFab() {
    return GestureDetector(
      onTapDown: (_) => _fabController.forward(),
      onTapUp: (_) {
        _fabController.reverse();
        context.push('/goals/create');
      },
      onTapCancel: () => _fabController.reverse(),
      child: AnimatedBuilder(
        animation: _fabScaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _fabScaleAnimation.value, child: child);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                AppMessages.goal.newGoal,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
