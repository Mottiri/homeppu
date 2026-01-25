import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/models/post_model.dart';
import '../../../../shared/services/post_service.dart';
import '../../../home/presentation/widgets/reaction_background.dart';

/// プロフィール画面用の投稿カード
class ProfilePostCard extends StatefulWidget {
  final PostModel post;
  final bool isMyProfile;
  final VoidCallback? onDeleted;
  final void Function(bool isFavorite)? onFavoriteToggled;

  const ProfilePostCard({
    super.key,
    required this.post,
    this.isMyProfile = false,
    this.onDeleted,
    this.onFavoriteToggled,
  });

  @override
  State<ProfilePostCard> createState() => _ProfilePostCardState();
}

class _ProfilePostCardState extends State<ProfilePostCard> {
  bool _isDeleting = false;

  Future<void> _deletePost() async {
    setState(() => _isDeleting = true);

    final deleted = await PostService().deletePost(
      context: context,
      post: widget.post,
      onDeleted: widget.onDeleted,
    );

    if (!deleted && mounted) {
      setState(() => _isDeleting = false);
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final newValue = !widget.post.isFavorite;
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post.id)
          .update({'isFavorite': newValue});

      if (mounted) {
        final message = newValue
            ? AppMessages.success.favoriteAdded
            : AppMessages.success.favoriteRemoved;
        SnackBarHelper.showSuccess(
          context,
          message,
          duration: const Duration(seconds: 1),
        );
        // リストを即時更新
        widget.onFavoriteToggled?.call(newValue);
      }
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // リアクション背景
          if (widget.post.reactions.isNotEmpty)
            Positioned.fill(
              child: ReactionBackground(
                reactions: widget.post.reactions,
                postId: widget.post.id,
                opacity: 0.15,
                maxIcons: 15,
              ),
            ),
          // コンテンツ
          InkWell(
            onTap: () => context.push('/post/${widget.post.id}'),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ヘッダー（自分のプロフィールなら削除ボタン）
                  if (widget.isMyProfile)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // お気に入りアイコン
                        if (widget.post.isFavorite)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.star,
                              size: 18,
                              color: Colors.amber,
                            ),
                          ),
                        if (_isDeleting)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_horiz,
                              color: AppColors.textHint,
                              size: 20,
                            ),
                            onSelected: (value) {
                              if (value == 'delete') {
                                _deletePost();
                              } else if (value == 'favorite') {
                                _toggleFavorite();
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'favorite',
                                child: Row(
                                  children: [
                                    Icon(
                                      widget.post.isFavorite
                                          ? Icons.star
                                          : Icons.star_outline,
                                      size: 18,
                                      color: Colors.amber,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      widget.post.isFavorite
                                          ? 'お気に入りから削除'
                                          : 'お気に入りに追加',
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'この投稿を削除',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),

                  // サークル名バッジ（サークル投稿の場合）
                  if (widget.post.circleId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('circles')
                            .doc(widget.post.circleId)
                            .get(),
                        builder: (context, snapshot) {
                          // ロード中は何も表示しない
                          if (!snapshot.hasData) {
                            return const SizedBox.shrink();
                          }
                          // サークルが削除されている場合
                          if (!snapshot.data!.exists) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.group_off_outlined,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '削除済みサークル',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          final circleName =
                              snapshot.data!.get('name') as String? ?? 'サークル';
                          return GestureDetector(
                            onTap: () =>
                                context.push('/circle/${widget.post.circleId}'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.group_outlined,
                                    size: 14,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    circleName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  // 投稿内容
                  Text(
                    widget.post.content,
                    style: Theme.of(context).textTheme.bodyLarge,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),

                  // フッター
                  Row(
                    children: [
                      // 時間
                      Text(
                        timeago.format(widget.post.createdAt, locale: 'ja'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textHint,
                        ),
                      ),

                      // メディアアイコン
                      if (widget.post.allMedia.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        ..._buildMediaIcons(),
                      ],

                      const Spacer(),
                      // リアクション数
                      Row(
                        children: [
                          Icon(Icons.favorite, size: 16, color: AppColors.love),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.post.reactions.values.fold(0, (a, b) => a + b)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 12),
                          // コメント数（PostModelから取得）
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.chat_bubble_outline,
                                size: 16,
                                color: AppColors.textHint,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${widget.post.commentCount}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// メディアアイコンを生成
  List<Widget> _buildMediaIcons() {
    final imageCount = widget.post.allMedia
        .where((m) => m.type == MediaType.image)
        .length;
    final videoCount = widget.post.allMedia
        .where((m) => m.type == MediaType.video)
        .length;

    final icons = <Widget>[];

    if (imageCount > 0) {
      icons.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.image_outlined,
              size: 16,
              color: AppColors.textHint,
            ),
            if (imageCount > 1) ...[
              const SizedBox(width: 2),
              Text(
                '$imageCount',
                style: const TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
            ],
          ],
        ),
      );
    }

    if (videoCount > 0) {
      if (icons.isNotEmpty) icons.add(const SizedBox(width: 8));
      icons.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_outlined,
              size: 16,
              color: AppColors.textHint,
            ),
            if (videoCount > 1) ...[
              const SizedBox(width: 2),
              Text(
                '$videoCount',
                style: const TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
            ],
          ],
        ),
      );
    }

    return icons;
  }
}
