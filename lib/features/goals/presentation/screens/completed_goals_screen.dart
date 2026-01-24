import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../shared/models/goal_model.dart';
import '../../../../shared/providers/goal_provider.dart';
import '../widgets/goal_card.dart';

/// 殿堂入り（達成した目標）一覧画面
class CompletedGoalsScreen extends ConsumerWidget {
  const CompletedGoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(child: Text(AppMessages.error.unauthorized)),
      );
    }

    final goalService = ref.read(goalServiceProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
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
            const SizedBox(width: 10),
            Text(AppMessages.goal.completedTitle),
          ],
        ),
      ),
      body: StreamBuilder<List<GoalModel>>(
        stream: goalService.streamCompletedGoals(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final completedGoals = snapshot.data ?? [];

          if (completedGoals.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFC107)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.emoji_events_outlined,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    AppMessages.goal.completedEmptyTitle,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppMessages.goal.completedEmptyDescription,
                    style: TextStyle(fontSize: 14, color: AppColors.textHint),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: completedGoals.length,
            itemBuilder: (context, index) {
              final goal = completedGoals[index];
              return GoalCard(
                goal: goal,
                isArchived: true,
                onTap: () => context.push('/goals/detail/${goal.id}'),
              );
            },
          );
        },
      ),
    );
  }
}
