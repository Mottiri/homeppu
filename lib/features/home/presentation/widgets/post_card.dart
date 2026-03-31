import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/post_model.dart';
import '../../../../shared/widgets/public_user_avatar.dart';
import '../../../../shared/widgets/report_dialog.dart';
import '../../../../shared/services/post_service.dart';
import '../../../../shared/services/recent_reactions_service.dart';
import '../../../../shared/services/reaction_limit_service.dart';
import '../../../../shared/services/rewarded_ad_service.dart';
import '../../../../shared/services/reaction_sync_service.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/public_user_provider.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/providers/moderation_provider.dart';
import '../../../../shared/providers/virtue_shop_provider.dart';
import '../../../../shared/services/virtue_shop_service.dart';
import 'reaction_background.dart';

/// 投稿カード
class PostCard extends ConsumerStatefulWidget {
  final PostModel post;
  final VoidCallback? onDeleted;
  final VoidCallback? onReactionOverlayClosed;
  final bool isCircleOwner; // サークルオーナーかどうか
  final Function(bool)? onPinToggle; // ピン留めトグルコールバック
  final bool isDetailView; // 詳細画面表示モード（タップで遷移しない）
  final bool longPressOnlyMode; // チュートリアル用: タップ操作を無効化

  const PostCard({
    super.key,
    required this.post,
    this.onDeleted,
    this.onReactionOverlayClosed,
    this.isCircleOwner = false,
    this.onPinToggle,
    this.isDetailView = false,
    this.longPressOnlyMode = false,
  });

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool _isDeleting = false;
  bool _isNavigating = false; // ナビゲーション中フラグ（ダブルタップ防止）
  late Map<String, int> _localReactions; // ローカルでリアクション数を管理

  @override
  void initState() {
    super.initState();
    _localReactions = Map<String, int>.from(widget.post.reactions);
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 親からのpostが更新されたらローカル状態も更新
    // IDが変わった場合、またはサーバーからの最新データが取得された場合
    if (oldWidget.post.id != widget.post.id) {
      _localReactions = Map<String, int>.from(widget.post.reactions);
    } else {
      // 同じ投稿でもサーバーからの値がローカルより大きい場合は同期
      // （サーバーで他のユーザーが追加したリアクションを反映）
      widget.post.reactions.forEach((key, serverValue) {
        final localValue = _localReactions[key] ?? 0;
        if (serverValue > localValue) {
          _localReactions[key] = serverValue;
        }
      });
    }
  }

  PostModel get post => widget.post;

  /// リアクションをローカルで追加
  void _addReaction(String reactionType) {
    setState(() {
      _localReactions[reactionType] = (_localReactions[reactionType] ?? 0) + 1;
    });
  }

  /// 自分の投稿かどうか
  bool get isMyPost {
    final currentUser = FirebaseAuth.instance.currentUser;
    return currentUser != null && currentUser.uid == post.userId;
  }

  /// 投稿を削除
  Future<void> _deletePost() async {
    final deleted = await PostService().deletePost(
      context: context,
      post: post,
      onDeleted: widget.onDeleted,
    );

    if (deleted && mounted) {
      setState(() => _isDeleting = false);
    }
  }

  /// LINEスタイルのリアクションオーバーレイを表示
  Future<void> _showReactionOverlay() async {
    // BANユーザーチェック（キャッシュ済みプロバイダーから即時取得）
    final cachedUser = ref.read(currentUserProvider).valueOrNull;
    if (cachedUser != null &&
        (cachedUser.isBanned || (cachedUser.banStatus != 'none'))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppMessages.error.banned),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // 自分の投稿にはリアクションできない
    if (isMyPost) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppMessages.error.reactionOwnPost),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 管理者チェック（キャッシュ済みプロバイダーから即時取得）
    final isAdmin = ref.read(isAdminProvider).valueOrNull ?? false;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    int? remaining;
    // この投稿へのリアクション回数をチェック（SharedPreferencesはローカルI/Oのみ）
    if (!isAdmin) {
      if (currentUserId != null) {
        try {
          final snapshot = await FirebaseFirestore.instance
              .collection('reactions')
              .where('postId', isEqualTo: post.id)
              .where('userId', isEqualTo: currentUserId)
              .get(const GetOptions(source: Source.server));
          await ReactionLimitService.setReactionCount(
            post.id,
            snapshot.size,
            userId: currentUserId,
          );
        } catch (e) {
          debugPrint('Failed to sync reaction count: $e');
        }
      }

      final canReact = await ReactionLimitService.canReact(
        post.id,
        userId: currentUserId,
      );
      if (!canReact) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppMessages.error.reactionLimitReached),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      remaining = await ReactionLimitService.getRemainingReactions(
        post.id,
        userId: currentUserId,
      );
    }

    if (!mounted) return;

    final initialUser = ref.read(currentUserProvider).valueOrNull;
    Map<String, RewardedReactionUnlock> sessionUnlocks =
        _adjustUnlocksForPending(
          Map<String, RewardedReactionUnlock>.from(
            initialUser?.rewardedReactionUnlocks ?? {},
          ),
          userId: currentUserId,
        );
    bool hasSyncedUnlocks = false;
    bool isSyncingUnlocks = false;

    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6), // 暗い背景
      barrierDismissible: true, // 背景タップで閉じる
      builder: (dialogContext) {
        int sessionCount = 0; // このセッションでのタップ数
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> syncUnlocks() async {
              if (isSyncingUnlocks) return;
              final currentUser = FirebaseAuth.instance.currentUser;
              if (currentUser == null) return;
              isSyncingUnlocks = true;
              setState(() {});
              try {
                final doc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUser.uid)
                    .get(const GetOptions(source: Source.server));
                final data = doc.data();
                sessionUnlocks = _adjustUnlocksForPending(
                  _parseRewardedUnlocks(data?['rewardedReactionUnlocks']),
                  userId: currentUserId,
                );
                hasSyncedUnlocks = true;
              } catch (e) {
                debugPrint('Failed to sync rewarded unlocks: $e');
              } finally {
                isSyncingUnlocks = false;
                if (mounted) setState(() {});
              }
            }

            if (!hasSyncedUnlocks && !isSyncingUnlocks) {
              syncUnlocks();
            }

            return _ReactionOverlayDialog(
              postId: post.id,
              rewardedUnlocks: sessionUnlocks,
              onRewardedUnlocked: () async {
                await syncUnlocks();
              },
              onReactionTap: (reactionType) async {
                // 残り回数チェック
                if (!isAdmin) {
                  final currentRemaining = remaining! - sessionCount;
                  if (currentRemaining <= 0) {
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(AppMessages.error.reactionLimitReached),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                }

                // awaitの前にscaffoldMessengerとnavigatorを取得
                final scaffoldMessenger = ScaffoldMessenger.of(this.context);
                final navigator = Navigator.of(dialogContext);

                final user = ref.read(currentUserProvider).valueOrNull;
                final isSubscriber = user?.isSubscriber ?? false;
                final reaction = ReactionType.values.firstWhere(
                  (type) => type.value == reactionType,
                  orElse: () => ReactionType.heart,
                );
                final isEpic =
                    reaction.unlockType == ReactionUnlockType.subscription;
                final isEpicNonSubscriber = isEpic && !isSubscriber;

                if (isEpicNonSubscriber) {
                  final unlock = sessionUnlocks[reactionType];
                  final now = DateTime.now();
                  if (unlock == null ||
                      unlock.remaining <= 0 ||
                      !unlock.expiresAt.isAfter(now)) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(AppMessages.error.epicReactionLocked),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                  final nextRemaining = unlock.remaining - 1;
                  setState(() {
                    if (nextRemaining <= 0) {
                      sessionUnlocks.remove(reactionType);
                    } else {
                      sessionUnlocks[reactionType] = RewardedReactionUnlock(
                        remaining: nextRemaining,
                        expiresAt: unlock.expiresAt,
                      );
                    }
                  });
                }

                _addReaction(reactionType);
                if (isEpicNonSubscriber) {
                  ReactionSyncService.incrementPending(
                    reactionType,
                    userId: currentUserId,
                  );
                }
                ReactionSyncService.enqueue(currentUserId, () async {
                  await _sendReactionToServer(reactionType);
                  if (isEpicNonSubscriber) {
                    ReactionSyncService.decrementPending(
                      reactionType,
                      userId: currentUserId,
                    );
                  }
                });
                unawaited(RecentReactionsService.addReaction(reactionType));
                if (!isAdmin) {
                  await ReactionLimitService.incrementReactionCount(
                    post.id,
                    userId: currentUserId,
                  );
                  sessionCount++;

                  // 残り0回でダイアログを閉じる
                  if (remaining! - sessionCount <= 0) {
                    navigator.pop();
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(AppMessages.error.reactionLimitReached),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                }
              },
            );
          },
        );
      },
    );
    widget.onReactionOverlayClosed?.call();
  }

  /// リアクションをサーバーに送信
  Future<void> _sendReactionToServer(String reactionType) async {
    try {
      final functions = FirebaseFunctions.instanceFor(
        region: AppConstants.functionsRegion,
      );
      final callable = functions.httpsCallable('addUserReaction');
      await callable.call({'postId': post.id, 'reactionType': reactionType});
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Reaction error: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('Reaction error: $e');
    }
  }

  Map<String, RewardedReactionUnlock> _parseRewardedUnlocks(dynamic raw) {
    if (raw is! Map) return {};
    final data = Map<String, dynamic>.from(raw);
    final result = <String, RewardedReactionUnlock>{};
    data.forEach((key, value) {
      if (value is Map) {
        result[key] = RewardedReactionUnlock.fromMap(
          Map<String, dynamic>.from(value),
        );
      }
    });
    return result;
  }

  /// サーバーから取得した残数からペンディング（キュー未処理）分を差し引く
  Map<String, RewardedReactionUnlock> _adjustUnlocksForPending(
    Map<String, RewardedReactionUnlock> unlocks, {
    String? userId,
  }) {
    final adjusted = <String, RewardedReactionUnlock>{};
    for (final entry in unlocks.entries) {
      final pending = ReactionSyncService.getPending(entry.key, userId: userId);
      final adjustedRemaining = entry.value.remaining - pending;
      if (adjustedRemaining > 0) {
        adjusted[entry.key] = RewardedReactionUnlock(
          remaining: adjustedRemaining,
          expiresAt: entry.value.expiresAt,
        );
      }
    }
    return adjusted;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: widget.isDetailView
          ? const EdgeInsets.all(16)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.hardEdge, // スタンプが枠外に表示されないようにクリップ
      child: Stack(
        children: [
          // 背景リアクション（落書き風）
          Positioned.fill(
            child: ReactionBackground(
              reactions: _localReactions, // ローカル状態を使用
              postId: post.id,
            ),
          ),
          // カードコンテンツ
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: (widget.isDetailView || widget.longPressOnlyMode)
                ? null
                : () => context.push('/post/${post.id}'),
            onLongPress: () {
              // 長押しでリアクションオーバーレイ表示
              _showReactionOverlay();
            },
            child: IgnorePointer(
              // longPressOnlyMode ではカード内部のタップ系操作を無効化
              ignoring: widget.longPressOnlyMode,
              child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ユーザー情報
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          if (_isNavigating) return; // ダブルタップ防止
                          _isNavigating = true;
                          await context.push('/profile/${post.userId}');
                          if (mounted) _isNavigating = false;
                        },
                        child: PublicUserAvatar(
                          userId: post.userId,
                          avatarIndex: post.userAvatarIndex,
                          size: 44,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () async {
                                if (_isNavigating) return; // ダブルタップ防止
                                _isNavigating = true;
                                await context.push('/profile/${post.userId}');
                                if (mounted) _isNavigating = false;
                              },
                              child: Consumer(
                                builder: (context, ref, _) {
                                  final displayName =
                                      ref.watch(
                                        publicUserDisplayNameProvider(
                                          post.userId,
                                        ),
                                      ) ??
                                      post.userDisplayName;
                                  return Text(
                                    displayName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: AppColors.primary),
                                  );
                                },
                              ),
                            ),
                            Text(
                              timeago.format(post.createdAt, locale: 'ja'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      // オプションメニュー（通報・削除など）
                      _isDeleting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_horiz,
                                color: AppColors.textHint,
                                size: 20,
                              ),
                              onSelected: (value) {
                                if (value == 'report') {
                                  ReportDialog.show(
                                    context: context,
                                    contentId: post.id,
                                    contentType: 'post',
                                    targetUserId: post.userId,
                                    contentPreview: post.content,
                                  );
                                } else if (value == 'delete') {
                                  _deletePost();
                                } else if (value == 'pin') {
                                  widget.onPinToggle?.call(!post.isPinned);
                                }
                              },
                              itemBuilder: (context) => [
                                // サークルオーナーならピン留めオプションを表示
                                if (widget.isCircleOwner &&
                                    post.circleId != null)
                                  PopupMenuItem(
                                    value: 'pin',
                                    child: Row(
                                      children: [
                                        Icon(
                                          post.isPinned
                                              ? Icons.push_pin
                                              : Icons.push_pin_outlined,
                                          size: 18,
                                          color: post.isPinned
                                              ? Colors.amber
                                              : Colors.grey[700],
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          post.isPinned ? 'ピン留め解除' : 'ピン留めする',
                                        ),
                                      ],
                                    ),
                                  ),
                                // 自分の投稿なら削除オプションを表示
                                if (isMyPost)
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
                                // 他人の投稿なら通報オプションを表示
                                if (!isMyPost)
                                  const PopupMenuItem(
                                    value: 'report',
                                    child: Row(
                                      children: [
                                        Icon(Icons.flag_outlined, size: 18),
                                        SizedBox(width: 8),
                                        Text('この投稿を通報'),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // 投稿内容
                  Text(
                    post.content,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(height: 1.6),
                  ),

                  // メディア表示
                  if (post.allMedia.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _MediaGrid(mediaItems: post.allMedia),
                  ],

                  const SizedBox(height: 16),

                  // リアクションエリア
                  Row(
                    children: [
                      const Spacer(),
                      // コメント数（PostModelから取得）
                      Row(
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline,
                            size: 18,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${post.commentCount}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }
}

/// メディアグリッド表示
class _MediaGrid extends StatelessWidget {
  final List<MediaItem> mediaItems;

  const _MediaGrid({required this.mediaItems});

  @override
  Widget build(BuildContext context) {
    if (mediaItems.isEmpty) return const SizedBox.shrink();

    // メディア数に応じてレイアウトを変更
    if (mediaItems.length == 1) {
      return _buildSingleMedia(context, mediaItems.first);
    } else if (mediaItems.length == 2) {
      return _buildTwoMedia(context);
    } else if (mediaItems.length == 3) {
      return _buildThreeMedia(context);
    } else {
      return _buildFourMedia(context);
    }
  }

  Widget _buildSingleMedia(BuildContext context, MediaItem item) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: _buildMediaItem(context, item, height: 200),
    );
  }

  Widget _buildTwoMedia(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(16),
            ),
            child: _buildMediaItem(context, mediaItems[0], height: 150),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(16),
            ),
            child: _buildMediaItem(context, mediaItems[1], height: 150),
          ),
        ),
      ],
    );
  }

  Widget _buildThreeMedia(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(16),
            ),
            child: _buildMediaItem(context, mediaItems[0], height: 200),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(16),
                ),
                child: _buildMediaItem(context, mediaItems[1], height: 98),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(16),
                ),
                child: _buildMediaItem(context, mediaItems[2], height: 98),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFourMedia(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                ),
                child: _buildMediaItem(context, mediaItems[0], height: 100),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(16),
                ),
                child: _buildMediaItem(context, mediaItems[1], height: 100),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                ),
                child: _buildMediaItem(context, mediaItems[2], height: 100),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(16),
                ),
                child: _buildMediaItem(
                  context,
                  mediaItems.length > 3 ? mediaItems[3] : mediaItems[2],
                  height: 100,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMediaItem(
    BuildContext context,
    MediaItem item, {
    required double height,
  }) {
    switch (item.type) {
      case MediaType.image:
        return GestureDetector(
          onTap: () => _showFullScreenImage(context, item.url),
          child: CachedNetworkImage(
            imageUrl: item.url,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              height: height,
              color: Colors.grey.shade200,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              height: height,
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        );

      case MediaType.video:
        if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty) {
          return CachedNetworkImage(
            imageUrl: item.thumbnailUrl!,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => Container(
              height: height,
              color: Colors.grey.shade200,
              child: const Icon(Icons.videocam_off, color: Colors.grey),
            ),
          );
        }
        return Container(
          height: height,
          color: Colors.grey.shade200,
          child: const Center(
            child: Icon(
              Icons.videocam_off,
              color: Colors.grey,
              size: 48,
            ),
          ),
        );

      case MediaType.file:
        return Container(
          height: height,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.block, size: 40, color: Colors.grey),
        );
    }
  }

  void _showFullScreenImage(BuildContext context, String url) {
    // rootNavigator: true でShellRouteの外で表示（ボトムナビを非表示）
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

}

/// LINEスタイルのリアクションオーバーレイダイアログ
class _ReactionOverlayDialog extends ConsumerStatefulWidget {
  final String postId;
  final void Function(String reactionType) onReactionTap;
  final Map<String, RewardedReactionUnlock> rewardedUnlocks;
  final Future<void> Function()? onRewardedUnlocked;

  const _ReactionOverlayDialog({
    required this.postId,
    required this.onReactionTap,
    required this.rewardedUnlocks,
    this.onRewardedUnlocked,
  });

  @override
  ConsumerState<_ReactionOverlayDialog> createState() =>
      _ReactionOverlayDialogState();
}

class _ReactionOverlayDialogState extends ConsumerState<_ReactionOverlayDialog>
    with TickerProviderStateMixin {
  final _virtueShopService = VirtueShopService();
  OverlayEntry? _toastEntry;
  // バーに表示するスタンプ数
  static const _visibleCount = 5;

  late List<AnimationController> _controllers;
  late List<Animation<double>> _scaleAnimations;
  bool _showExtendedList = false;
  bool _isOpeningLockedDialog = false;
  bool _isRefreshingVirtueConfig = false;

  // 使用順にソートされたスタンプリスト
  List<ReactionType> _orderedStamps = [];

  // バーに表示するスタンプ（最初の5つ）
  List<ReactionType> get _barStamps =>
      _orderedStamps.take(_visibleCount).toList();
  // 拡張リストに表示するスタンプ（残り）
  List<ReactionType> get _extendedStamps =>
      _orderedStamps.skip(_visibleCount).toList();

  @override
  void initState() {
    super.initState();
    _controllers = [];
    _scaleAnimations = [];
    _loadOrderedStamps();
  }

  Future<void> _loadOrderedStamps() async {
    final recentList = await RecentReactionsService.getRecentReactions();
    final allStamps = List<ReactionType>.from(ReactionType.values);

    // 最近使用した順にソート
    final ordered = <ReactionType>[];
    for (final recentValue in recentList) {
      final stamp = allStamps.firstWhere(
        (s) => s.value == recentValue,
        orElse: () => allStamps.first,
      );
      if (!ordered.contains(stamp)) {
        ordered.add(stamp);
        allStamps.remove(stamp);
      }
    }
    // 残りを追加
    ordered.addAll(allStamps);

    // 購入不可かつ未所有のスタンプを除外
    final shopConfig = ref.read(virtueShopConfigProvider).valueOrNull;
    final user = ref.read(currentUserProvider).valueOrNull;
    final unlockedStamps = user?.unlockedReactionStamps.toSet() ?? <String>{};
    final isSubscriber = user?.isSubscriber ?? false;
    final rewardedUnlocks = widget.rewardedUnlocks;
    final now = DateTime.now();
    final filtered = ordered.where((stamp) {
      final isOwned = stamp.isUnlocked(
        isSubscriber: isSubscriber,
        unlockedItems: unlockedStamps,
        rewardedUnlocks: rewardedUnlocks,
        now: now,
      );
      if (isOwned) return true;
      return !(shopConfig?.isNonPurchasable('reaction_stamp', stamp.value) ?? false);
    }).toList();

    if (mounted) {
      setState(() {
        _orderedStamps = filtered;
      });
      _initAnimations();
    }
  }

  void _initAnimations() {
    // 既存のコントローラーを破棄
    for (final controller in _controllers) {
      controller.dispose();
    }
    _controllers = [];
    _scaleAnimations = [];

    // バーのスタンプにアニメーションを設定
    for (var i = 0; i < _barStamps.length; i++) {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 400),
        vsync: this,
      );
      _controllers.add(controller);

      // ぽぽんとバウンドするアニメーション（0 → 1.2 → 1.0）
      final animation = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(
            begin: 0.0,
            end: 1.2,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 60,
        ),
        TweenSequenceItem(
          tween: Tween<double>(
            begin: 1.2,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.bounceOut)),
          weight: 40,
        ),
      ]).animate(controller);
      _scaleAnimations.add(animation);

      // 遅延を付けて順番に表示
      Future.delayed(Duration(milliseconds: i * 80), () {
        if (mounted) controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _toastEntry?.remove();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _showOverlayToast(String message, {bool isError = false}) {
    _toastEntry?.remove();
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final bottom = safeBottom + 12;
    final overlay = Overlay.of(context, rootOverlay: true);

    _toastEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: 16,
          right: 16,
          bottom: bottom,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: (isError ? AppColors.error : AppColors.success)
                    .withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_toastEntry!);

    Future.delayed(const Duration(seconds: 2), () {
      _toastEntry?.remove();
      _toastEntry = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(virtueShopConfigProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final unlockedStamps = user?.unlockedReactionStamps.toSet() ?? <String>{};
    final isSubscriber = user?.isSubscriber ?? false;
    final rewardedUnlocks = widget.rewardedUnlocks;
    final now = DateTime.now();
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;

    int? remainingCount(ReactionType type) {
      if (type.rarity != ReactionRarity.epic) return null;
      if (isSubscriber) return null;
      final unlock = rewardedUnlocks[type.value];
      if (unlock == null) return null;
      if (unlock.remaining <= 0) return null;
      if (!unlock.expiresAt.isAfter(now)) return null;
      return unlock.remaining;
    }

    bool isLocked(ReactionType type) {
      return !type.isUnlocked(
        isSubscriber: isSubscriber,
        unlockedItems: unlockedStamps,
        rewardedUnlocks: rewardedUnlocks,
        now: now,
      );
    }

    return Stack(
      children: [
        // 背景タップで閉じる
        GestureDetector(
          onTap: () {
            if (_showExtendedList) {
              setState(() => _showExtendedList = false);
            } else {
              Navigator.of(context).pop();
            }
          },
          child: const SizedBox.expand(),
        ),

        // スタンプバー（ボトムナビの上、横スクロール可能）
        Positioned(
          left: 16,
          right: 16,
          bottom: 100 + safeBottom,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 5つのスタンプ
                ...List.generate(_barStamps.length, (index) {
                  final stamp = _barStamps[index];
                  return ScaleTransition(
                    scale: _scaleAnimations[index],
                    child: _buildStampButton(
                      stamp,
                      isLocked: isLocked(stamp),
                      remainingCount: remainingCount(stamp),
                    ),
                  );
                }),
                // ＋アイコン
                _buildPlusButton(),
              ],
            ),
          ),
        ),

        // 拡張リスト（＋押下で表示、アニメーション付き）
        if (_showExtendedList)
          Positioned(
            right: 40,
            bottom: 180 + safeBottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_extendedStamps.length, (index) {
                final stamp = _extendedStamps[index];
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 300 + (index * 80)),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: _buildSmallStampButton(
                    stamp,
                    isLocked: isLocked(stamp),
                    remainingCount: remainingCount(stamp),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  void _onStampTap(ReactionType type, {required bool isLocked}) {
    if (!isLocked) {
      widget.onReactionTap(type.value);
      return;
    }

    if (_isOpeningLockedDialog) return;
    _isOpeningLockedDialog = true;
    _showLockedDialog(type).whenComplete(() {
      _isOpeningLockedDialog = false;
    });
  }

  Future<void> _refreshVirtueConfigInBackground() async {
    if (_isRefreshingVirtueConfig) return;
    _isRefreshingVirtueConfig = true;
    try {
      ref.invalidate(virtueShopConfigProvider);
      await ref.read(virtueShopConfigProvider.future);
    } catch (e) {
      debugPrint('[VirtueDialog] Background config refresh failed: $e');
    } finally {
      _isRefreshingVirtueConfig = false;
    }
  }

  Future<int?> _loadReactionCost(String reactionId) async {
    int? parseCost(VirtueShopConfig? config) {
      final cost = config?.costForReaction(reactionId);
      if (cost == null || cost <= 0) return null;
      return cost;
    }

    final cachedCost = parseCost(ref.read(virtueShopConfigProvider).valueOrNull);
    if (cachedCost != null) {
      // Keep UI fast while reducing stale config risk in long sessions.
      unawaited(_refreshVirtueConfigInBackground());
      return cachedCost;
    }

    try {
      final config = await ref.read(virtueShopConfigProvider.future);
      final cost = parseCost(config);
      if (cost != null) {
        return cost;
      }
    } catch (e) {
      debugPrint('[VirtueDialog] Config read failed: $e');
    }

    try {
      final config = await ref.refresh(virtueShopConfigProvider.future);
      final cost = parseCost(config);
      if (cost != null) {
        return cost;
      }
    } catch (e) {
      debugPrint('[VirtueDialog] Config refresh failed: $e');
    }

    return null;
  }

  Future<void> _showLockedDialog(ReactionType type) async {
    if (!mounted) return;
    switch (type.unlockType) {
      case ReactionUnlockType.free:
        return;
      case ReactionUnlockType.virtue:
        final cost = await _loadReactionCost(type.value);
        if (!mounted) return;
        if (cost == null || cost <= 0) {
          _showOverlayToast(
            AppMessages.error.loadFailed('価格情報'),
            isError: true,
          );
          return;
        }

        bool isProcessing = false;
        int currentVirtue = 0;
        final currentUser = ref.read(currentUserProvider).valueOrNull;
        if (currentUser != null) {
          currentVirtue = currentUser.virtue;
          debugPrint(
            '[VirtueDialog] Using currentUserProvider virtue=$currentVirtue cost=$cost',
          );
        } else {
          bool fetchFailed = false;
          debugPrint('[VirtueDialog] currentUser unavailable. Fetching callable virtue status');
          try {
            final virtueStatus = await ref.refresh(virtueStatusProvider.future);
            currentVirtue = virtueStatus.virtue;
            debugPrint(
              '[VirtueDialog] Fetched virtue=$currentVirtue cost=$cost',
            );
          } catch (e) {
            fetchFailed = true;
            debugPrint('[VirtueDialog] Fetch failed: $e');
          }
          if (!mounted) return;
          if (fetchFailed) {
            SnackBarHelper.showError(context, AppMessages.error.network);
            return;
          }
        }
        if (!mounted) return;
        final hasEnough = currentVirtue >= cost;
        debugPrint(
          '[VirtueDialog] hasEnough=$hasEnough current=$currentVirtue cost=$cost',
        );
        await showDialog<void>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.5),
          builder: (dialogContext) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                return Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // スタンププレビュー（グロー付き）
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.rarityRare.withValues(alpha: 0.2),
                                AppColors.rarityRare.withValues(alpha: 0.1),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.rarityRare.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 16,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            type.assetPath,
                            width: 64,
                            height: 64,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Text(
                                type.emoji,
                                style: const TextStyle(fontSize: 48),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        // タイトル
                        Text(
                          AppMessages.confirm.purchaseVirtueTitle,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppMessages.confirm.purchaseVirtueMessage(cost),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        // 価格表示
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.virtue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                color: AppColors.virtue,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                AppMessages.confirm.virtueCostLabel(cost),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.virtue,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 現在の保有ポイント
                        Text(
                          hasEnough
                              ? AppMessages.confirm.virtueBalanceAfterPurchase(
                                  currentVirtue,
                                  cost,
                                )
                              : AppMessages.confirm.virtueBalanceShortage(
                                  currentVirtue,
                                  cost,
                                ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: hasEnough
                                    ? AppColors.textSecondary
                                    : AppColors.error,
                                fontWeight: hasEnough ? null : FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 20),
                        // 購入ボタン
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isProcessing || !hasEnough
                                ? null
                                : () async {
                                    setDialogState(() => isProcessing = true);
                                    final success =
                                        await _purchaseReactionStamp(type);
                                    if (!mounted || !dialogContext.mounted) {
                                      return;
                                    }
                                    if (success) {
                                      Navigator.of(dialogContext).pop();
                                      return;
                                    }
                                    setDialogState(
                                      () => isProcessing = false,
                                    );
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.virtue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: isProcessing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    AppMessages.label.purchase,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // キャンセルボタン
                        TextButton(
                          onPressed: isProcessing
                              ? null
                              : () => Navigator.of(dialogContext).pop(),
                          child: Text(
                            AppMessages.label.cancel,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
        return;
      case ReactionUnlockType.subscription:
        final rootContext = context;
        bool isProcessing = false;
        await showDialog<void>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.5),
          builder: (dialogContext) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                return Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // スタンププレビュー（グロー付き）
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.rarityEpic.withValues(alpha: 0.2),
                                AppColors.rarityEpic.withValues(alpha: 0.1),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.rarityEpic.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 16,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            type.assetPath,
                            width: 64,
                            height: 64,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Text(
                                type.emoji,
                                style: const TextStyle(fontSize: 48),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        // タイトル
                        Text(
                          AppMessages.confirm.subscriptionOnlyTitle,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppMessages.confirm.subscriptionOnlyMessageWithRewarded(
                            AppConstants.rewardedReactionHours,
                            AppConstants.rewardedReactionUses,
                          ),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        // 広告視聴オプション
                        _EpicUnlockOptionCard(
                          icon: Icons.play_circle_outline,
                          iconColor: AppColors.info,
                          title: AppMessages.confirm.rewardedUnlockTitle,
                          subtitle: AppMessages.confirm.rewardedUnlockSubtitle(
                            AppConstants.rewardedReactionUses,
                            AppConstants.rewardedReactionHours,
                          ),
                          isLoading: isProcessing,
                          onTap: isProcessing
                              ? null
                              : () async {
                                  setDialogState(() => isProcessing = true);
                                  final success = await _handleRewardedUnlock(
                                    type,
                                  );
                                  if (!mounted || !dialogContext.mounted) {
                                    return;
                                  }
                                  setDialogState(() => isProcessing = false);
                                  if (success) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        // プレミアム加入オプション
                        _EpicUnlockOptionCard(
                          icon: Icons.workspace_premium,
                          iconColor: AppColors.praise,
                          title: AppMessages.confirm.premiumSubscribeTitle,
                          subtitle: AppMessages.confirm.premiumUnlockEpicSubtitle,
                          isPremium: true,
                          onTap: isProcessing
                              ? null
                              : () {
                                  Navigator.of(dialogContext).pop();
                                  Future.microtask(() {
                                    if (!rootContext.mounted) return;
                                    rootContext.push('/premium');
                                  });
                                },
                        ),
                        const SizedBox(height: 20),
                        // キャンセルボタン
                        TextButton(
                          onPressed: isProcessing
                              ? null
                              : () => Navigator.of(dialogContext).pop(),
                          child: Text(
                            AppMessages.label.cancel,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
        return;
    }
  }

  Future<bool> _purchaseReactionStamp(ReactionType type) async {
    try {
      await _virtueShopService.purchaseVirtueItem(
        itemType: 'reaction_stamp',
        itemId: type.value,
      );
      ref.invalidate(currentUserProvider);
      ref.invalidate(virtueStatusProvider);
      ref.invalidate(virtueHistoryProvider);
      if (mounted) {
        _showOverlayToast(AppMessages.success.purchaseCompleted);
      }
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        final reason = (e.details is Map) ? e.details['reason'] : null;
        if (reason == AppMessages.reasonItemNotPurchasable) {
          _showOverlayToast(AppMessages.error.itemNotPurchasable, isError: true);
          ref.invalidate(virtueShopConfigProvider);
        } else {
          final message = e.message == AppMessages.error.notEnoughVirtue
              ? AppMessages.error.notEnoughVirtue
              : AppMessages.error.general;
          _showOverlayToast(message, isError: true);
        }
      }
      return false;
    } catch (_) {
      if (mounted) {
        _showOverlayToast(AppMessages.error.general, isError: true);
      }
      return false;
    }
  }

  Future<bool> _handleRewardedUnlock(ReactionType type) async {
    final completer = Completer<bool>();
    final rewarded = await RewardedAdService.instance.show(
      onEarned: () {
        _grantRewardedUnlock(type)
            .then((value) => completer.complete(value))
            .catchError((_) => completer.complete(false));
      },
    );

    if (!rewarded) {
      if (mounted) {
        _showOverlayToast(AppMessages.error.rewardedAdFailed, isError: true);
      }
      return false;
    }

    final success = await completer.future;
    if (mounted) {
      if (success) {
        final onRewardedUnlocked = widget.onRewardedUnlocked;
        if (onRewardedUnlocked != null) {
          await onRewardedUnlocked();
        }
        _showOverlayToast(
          AppMessages.success.rewardedUnlockGranted(
            AppConstants.rewardedReactionUses,
            AppConstants.rewardedReactionHours,
          ),
        );
      } else {
        _showOverlayToast(
          AppMessages.error.rewardedUnlockFailed,
          isError: true,
        );
      }
    }
    return success;
  }

  Future<bool> _grantRewardedUnlock(ReactionType type) async {
    try {
      final functions = FirebaseFunctions.instanceFor(
        region: AppConstants.functionsRegion,
      );
      final callable = functions.httpsCallable('grantRewardedReactionUnlock');
      await callable.call({'reactionType': type.value});
      ref.invalidate(currentUserProvider);
      return true;
    } catch (e) {
      debugPrint('Rewarded unlock error: $e');
      return false;
    }
  }

  Widget _buildStampButton(
    ReactionType type, {
    required bool isLocked,
    int? remainingCount,
  }) {
    return GestureDetector(
      onTap: () => _onStampTap(type, isLocked: isLocked),
      child: _buildStampGlow(
        type,
        size: 56,
        emojiSize: 40,
        padding: const EdgeInsets.all(6),
        isLocked: isLocked,
        remainingCount: remainingCount,
      ),
    );
  }

  Widget _buildPlusButton() {
    return GestureDetector(
      onTap: () => setState(() => _showExtendedList = !_showExtendedList),
      child: Container(
        padding: const EdgeInsets.all(6),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _showExtendedList ? Icons.close : Icons.add,
            size: 28,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildSmallStampButton(
    ReactionType type, {
    required bool isLocked,
    int? remainingCount,
  }) {
    return GestureDetector(
      onTap: () => _onStampTap(type, isLocked: isLocked),
      child: _buildStampGlow(
        type,
        size: 48,
        emojiSize: 32,
        padding: const EdgeInsets.all(4),
        isLocked: isLocked,
        remainingCount: remainingCount,
      ),
    );
  }

  Widget _buildStampGlow(
    ReactionType type, {
    required double size,
    required double emojiSize,
    required EdgeInsets padding,
    required bool isLocked,
    int? remainingCount,
  }) {
    final glowColor = type.rarityColor.withValues(
      alpha: isLocked ? 0.25 : 0.55,
    );
    final glowSize = size * 1.05;
    return Container(
      padding: padding,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: glowSize,
            height: glowSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: glowColor, blurRadius: 8, spreadRadius: 0),
              ],
            ),
          ),
          Opacity(
            opacity: isLocked ? 0.5 : 1.0,
            child: Image.asset(
              type.assetPath,
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Text(type.emoji, style: TextStyle(fontSize: emojiSize));
              },
            ),
          ),
          if (isLocked)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock, size: 12, color: Colors.white),
              ),
            ),
          if (!isLocked && remainingCount != null)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$remainingCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Epicスタンプ解放オプションカード
class _EpicUnlockOptionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isPremium;
  final bool isLoading;
  final VoidCallback? onTap;

  const _EpicUnlockOptionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.isPremium = false,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isPremium
        ? AppColors.praise.withValues(alpha: 0.5)
        : AppColors.info.withValues(alpha: 0.3);
    final bgGradient = isPremium
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.praise.withValues(alpha: 0.08),
              AppColors.praise.withValues(alpha: 0.02),
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.info.withValues(alpha: 0.05),
              AppColors.info.withValues(alpha: 0.02),
            ],
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: bgGradient,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
