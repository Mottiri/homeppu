import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:async';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../shared/models/post_model.dart';
import '../../../../shared/models/comment_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/moderation_provider.dart';
import '../../../../shared/services/moderation_service.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/widgets/report_dialog.dart';

import '../../../home/presentation/widgets/post_card.dart';

/// 投稿詳細画面
class PostDetailScreen extends ConsumerStatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _commentController = TextEditingController();
  bool _isSending = false;
  Timer? _refreshTimer;
  late final Stream<DocumentSnapshot> _postStream;
  late final Stream<QuerySnapshot> _commentsStream;

  @override
  void initState() {
    super.initState();

    // ストリームを初期化（ビルドごとの再接続を防ぐ）
    _postStream = FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .snapshots();

    _commentsStream = FirebaseFirestore.instance
        .collection('comments')
        .where('postId', isEqualTo: widget.postId)
        .orderBy('createdAt', descending: false)
        .snapshots();

    // 30秒ごとに画面を更新して、時間経過で表示されるべきコメントを表示する
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isSending = true);

    try {
      // モデレーション付きコメント作成（Cloud Functions経由）
      final moderationService = ref.read(moderationServiceProvider);
      await moderationService.createCommentWithModeration(
        postId: widget.postId,
        content: content,
        userDisplayName: user.displayName,
        userAvatarIndex: user.avatarIndex,
      );

      _commentController.clear();

      // 徳ポイント状態を更新
      ref.invalidate(virtueStatusProvider);
    } on ModerationException catch (e) {
      if (mounted) {
        // ネガティブコンテンツが検出された場合
        await NegativeContentDialog.show(context: context, message: e.message);
        // 徳ポイント状態を更新
        ref.invalidate(virtueStatusProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppMessages.error.general),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    timeago.setLocaleMessages('ja', timeago.JaMessages());

    // ユーザーのヘッダー色を取得
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final primaryColor = currentUser?.headerPrimaryColor != null
        ? Color(currentUser!.headerPrimaryColor!)
        : AppColors.primary;
    final secondaryColor = currentUser?.headerSecondaryColor != null
        ? Color(currentUser!.headerSecondaryColor!)
        : AppColors.secondary;

    // ユーザーの色でグラデーションを作成
    final userGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        primaryColor.withValues(alpha: 0.25),
        secondaryColor.withValues(alpha: 0.15),
        const Color(0xFFFDF8F3),
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: userGradient),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: _postStream,
                  builder: (context, postSnapshot) {
                    if (postSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      );
                    }

                    if (!postSnapshot.hasData || !postSnapshot.data!.exists) {
                      // 投稿が存在しない場合、トーストを表示して戻る
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(AppMessages.error.postDeletedNotice),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          context.pop();
                        }
                      });
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      );
                    }

                    final post = PostModel.fromFirestore(postSnapshot.data!);

                    // 非表示の投稿（削除済み）の場合、トーストを表示して戻る
                    if (!post.isVisible) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(AppMessages.error.postDeletedNotice),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          context.pop();
                        }
                      });
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      );
                    }

                    return CustomScrollView(
                      slivers: [
                        // 戻るボタン（スクロールで非表示）
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: () => context.pop(),
                                  icon: const Icon(Icons.arrow_back_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 投稿本体（PostCardウィジェットを再利用）
                        SliverToBoxAdapter(
                          child: PostCard(post: post, isDetailView: true),
                        ),

                        // コメントヘッダー
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            child: Text(
                              'コメント',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),

                        // コメントリスト
                        StreamBuilder<QuerySnapshot>(
                          stream: _commentsStream,
                          builder: (context, commentSnapshot) {
                            if (!commentSnapshot.hasData) {
                              return const SliverToBoxAdapter(
                                child: Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(20),
                                    child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final comments = commentSnapshot.data!.docs
                                .map((doc) => CommentModel.fromFirestore(doc))
                                .where((c) => c.isVisibleNow)
                                .toList();

                            if (comments.isEmpty) {
                              return SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.all(40),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        const Text(
                                          '💬',
                                          style: TextStyle(fontSize: 40),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'まだコメントがないよ',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: AppColors.textSecondary,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '最初のコメントを送ってみよう！',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }

                            return SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final comment = comments[index];
                                return _CommentTile(comment: comment);
                              }, childCount: comments.length),
                            );
                          },
                        ),

                        // スペーサー
                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
                      ],
                    );
                  },
                ),
              ),

              // コメント入力エリア
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: currentUser?.isBanned == true
                      // BANユーザー向けメッセージ
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.block,
                                color: AppColors.error.withValues(alpha: 0.7),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'アカウント制限中のため、コメントできません',
                                  style: TextStyle(
                                    color: AppColors.error.withValues(
                                      alpha: 0.8,
                                    ),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      // 通常のコメント入力欄
                      : Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _commentController,
                                maxLines: null,
                                maxLength: AppConstants.maxCommentLength,
                                decoration: InputDecoration(
                                  hintText: '温かいコメントを送ろう☺️',
                                  counterText: '',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed:
                                  _commentController.text.trim().isEmpty ||
                                      _isSending
                                  ? null
                                  : _sendComment,
                              icon: _isSending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary,
                                      ),
                                    )
                                  : Icon(
                                      Icons.send_rounded,
                                      color:
                                          _commentController.text.trim().isEmpty
                                          ? AppColors.textHint
                                          : AppColors.primary,
                                    ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// コメントタイル
class _CommentTile extends StatelessWidget {
  final CommentModel comment;

  const _CommentTile({required this.comment});

  void _navigateToProfile(BuildContext context) {
    context.push('/profile/${comment.userId}');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // アバター（タップでプロフィールへ）
          GestureDetector(
            onTap: () => _navigateToProfile(context),
            child: AvatarWidget(avatarIndex: comment.userAvatarIndex, size: 36),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // ユーザー名（タップでプロフィールへ）
                      GestureDetector(
                        onTap: () => _navigateToProfile(context),
                        child: Text(
                          comment.userDisplayName,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeago.format(comment.createdAt, locale: 'ja'),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    comment.content,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
