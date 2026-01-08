import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/app_constants.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/post_model.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/widgets/report_dialog.dart';
import '../../../../shared/widgets/video_player_screen.dart';
import '../../../../shared/services/post_service.dart';
import '../../../../shared/services/recent_reactions_service.dart';
import '../../../../shared/services/reaction_limit_service.dart';
import 'reaction_background.dart';

/// 投稿カード
class PostCard extends StatefulWidget {
  final PostModel post;
  final VoidCallback? onDeleted;
  final bool isCircleOwner; // サークルオーナーかどうか
  final Function(bool)? onPinToggle; // ピン留めトグルコールバック
  final bool isDetailView; // 詳細画面表示モード（タップで遷移しない）

  const PostCard({
    super.key,
    required this.post,
    this.onDeleted,
    this.isCircleOwner = false,
    this.onPinToggle,
    this.isDetailView = false,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
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
    // BANユーザーチェック
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (userDoc.exists && userDoc.data()?['isBanned'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('アカウントが制限されているため、この操作はできません'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }

    // 自分の投稿にはリアクションできない
    if (isMyPost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('自分の投稿にはリアクションできません'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // この投稿へのリアクション回数をチェック
    final canReact = await ReactionLimitService.canReact(post.id);
    if (!canReact) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('この投稿へのリアクションは5回までです'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final remaining = await ReactionLimitService.getRemainingReactions(post.id);

    if (!mounted) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6), // 暗い背景
      barrierDismissible: true, // 背景タップで閉じる
      builder: (dialogContext) {
        int sessionCount = 0; // このセッションでのタップ数
        return StatefulBuilder(
          builder: (context, setState) {
            return _ReactionOverlayDialog(
              postId: post.id,
              onReactionTap: (reactionType) async {
                // 残り回数チェック
                final currentRemaining = remaining - sessionCount;
                if (currentRemaining <= 0) {
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text('この投稿へのリアクションは5回までです'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }

                // awaitの前にscaffoldMessengerとnavigatorを取得
                final scaffoldMessenger = ScaffoldMessenger.of(this.context);
                final navigator = Navigator.of(dialogContext);

                _addReaction(reactionType);
                _sendReactionToServer(reactionType);
                RecentReactionsService.addReaction(reactionType);
                await ReactionLimitService.incrementReactionCount(post.id);
                sessionCount++;

                // 残り0回でダイアログを閉じる
                if (remaining - sessionCount <= 0) {
                  navigator.pop();
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('この投稿へのリアクションは5回までです'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
  }

  /// リアクションをサーバーに送信
  Future<void> _sendReactionToServer(String reactionType) async {
    try {
      final functions = FirebaseFunctions.instanceFor(
        region: 'asia-northeast1',
      );
      final callable = functions.httpsCallable('addUserReaction');
      await callable.call({'postId': post.id, 'reactionType': reactionType});
      await RecentReactionsService.addReaction(reactionType);
    } catch (e) {
      debugPrint('Reaction error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // timeagoの日本語設定
    timeago.setLocaleMessages('ja', timeago.JaMessages());

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
          InkWell(
            onTap: widget.isDetailView
                ? null
                : () => context.push('/post/${post.id}'),
            onLongPress: () {
              // 長押しでリアクションオーバーレイ表示
              _showReactionOverlay();
            },
            borderRadius: BorderRadius.circular(20),
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
                        child: AvatarWidget(
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
                              child: Text(
                                post.userDisplayName,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: AppColors.primary),
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
        return GestureDetector(
          onTap: () => _showVideoPlayer(context, item.url),
          child: Container(
            height: height,
            color: Colors.black87,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // サムネイル（動画のプレビュー）
                if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: item.thumbnailUrl!,
                    height: height,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) =>
                        Container(color: Colors.black54),
                  )
                else
                  Container(
                    height: height,
                    width: double.infinity,
                    color: Colors.black54,
                    child: const Center(
                      child: Icon(
                        Icons.videocam,
                        color: Colors.white54,
                        size: 48,
                      ),
                    ),
                  ),
                // 再生アイコン
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ],
            ),
          ),
        );

      case MediaType.file:
        return GestureDetector(
          onTap: () => _openFile(context, item),
          child: Container(
            height: height,
            color: Colors.grey.shade100,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getFileIcon(item.fileName ?? ''),
                  size: 40,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    item.fileName ?? 'ファイル',
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (item.fileSize != null)
                  Text(
                    _formatFileSize(item.fileSize!),
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
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

  void _showVideoPlayer(BuildContext context, String url) {
    // rootNavigator: true でShellRouteの外で表示（ボトムナビを非表示）
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (context) => VideoPlayerScreen(videoUrl: url)),
    );
  }

  void _openFile(BuildContext context, MediaItem item) {
    // TODO: ファイルダウンロード・表示を実装
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${item.fileName}を開きます')));
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'txt':
        return Icons.text_snippet;
      case 'zip':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// LINEスタイルのリアクションオーバーレイダイアログ
class _ReactionOverlayDialog extends StatefulWidget {
  final String postId;
  final void Function(String reactionType) onReactionTap;

  const _ReactionOverlayDialog({
    required this.postId,
    required this.onReactionTap,
  });

  @override
  State<_ReactionOverlayDialog> createState() => _ReactionOverlayDialogState();
}

class _ReactionOverlayDialogState extends State<_ReactionOverlayDialog>
    with TickerProviderStateMixin {
  // バーに表示するスタンプ数
  static const _visibleCount = 5;

  late List<AnimationController> _controllers;
  late List<Animation<double>> _scaleAnimations;
  bool _showExtendedList = false;

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

    if (mounted) {
      setState(() {
        _orderedStamps = ordered;
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
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          bottom: 100,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 5つのスタンプ
                ...List.generate(_barStamps.length, (index) {
                  return ScaleTransition(
                    scale: _scaleAnimations[index],
                    child: _buildStampButton(_barStamps[index]),
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
            bottom: 180,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_extendedStamps.length, (index) {
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
                  child: _buildSmallStampButton(_extendedStamps[index]),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildStampButton(ReactionType type) {
    return GestureDetector(
      onTap: () => widget.onReactionTap(type.value),
      child: Container(
        padding: const EdgeInsets.all(6),
        child: Image.asset(
          type.assetPath,
          width: 56,
          height: 56,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Text(type.emoji, style: const TextStyle(fontSize: 40));
          },
        ),
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

  Widget _buildSmallStampButton(ReactionType type) {
    return GestureDetector(
      onTap: () => widget.onReactionTap(type.value),
      child: Container(
        padding: const EdgeInsets.all(4),
        child: Image.asset(
          type.assetPath,
          width: 48,
          height: 48,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Text(type.emoji, style: const TextStyle(fontSize: 32));
          },
        ),
      ),
    );
  }
}
