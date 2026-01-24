import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/post_model.dart';
import '../../../home/presentation/widgets/post_card.dart';

class CirclePostsList extends StatelessWidget {
  final List<PostModel> posts;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final bool canManagePins;
  final Future<void> Function(int index, PostModel post, bool isPinned)?
      onPinToggle;
  final void Function(int index)? onPostDeleted;

  const CirclePostsList({
    super.key,
    required this.posts,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.canManagePins,
    this.onPinToggle,
    this.onPostDeleted,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(
              color: AppColors.primary,
            ),
          ),
        ),
      );
    }

    if (posts.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '📝',
                  style: TextStyle(fontSize: 40),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'まだ投稿がないよ',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '最初の投稿をしてみよう！',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index == posts.length) {
          if (isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }

        final post = posts[index];
        return PostCard(
          key: ValueKey(post.id),
          post: post,
          isCircleOwner: canManagePins,
          onPinToggle: canManagePins && onPinToggle != null
              ? (isPinned) => onPinToggle!(index, post, isPinned)
              : null,
          onDeleted: onPostDeleted == null ? null : () => onPostDeleted!(index),
        );
      }, childCount: posts.length + (hasMore ? 1 : 0)),
    );
  }
}
