import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:async';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../shared/models/post_model.dart';
import '../../../../shared/models/comment_model.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/moderation_provider.dart';
import '../../../../shared/services/moderation_service.dart';
import '../../../../shared/services/circle_service.dart';
import '../../../../shared/services/comment_thanks_service.dart';
import '../../../../shared/widgets/public_user_avatar.dart';
import '../../../../shared/widgets/report_dialog.dart';
import '../../../../shared/widgets/ad_banner.dart';
import '../../../../shared/providers/tutorial_phase2_provider.dart';
import '../../../../shared/widgets/tutorial_overlay.dart';

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
  final GlobalKey _tutorialOverlayStackKey = GlobalKey();
  final GlobalKey _tutorialTargetCommentKey = GlobalKey();
  Rect? _tutorialCommentRect;
  bool _phase2TutorialInitialized = false;
  TutorialPhase2Step? _lastLoggedPhase2Step;
  bool _didAutoScrollToComment = false;
  int _commentScrollRetryCount = 0;
  String? _tutorialTargetCommentId;
  bool _tutorialScrollFallback = false;
  bool? _lastLoggedPhase2OverlayVisible;
  bool? _lastLoggedHasTutorialTarget;
  int? _lastLoggedCommentCount;

  bool _isRectNearlyEqual(Rect? a, Rect? b, {double tolerance = 0.5}) {
    if (a == null || b == null) return a == b;
    return (a.left - b.left).abs() <= tolerance &&
        (a.top - b.top).abs() <= tolerance &&
        (a.width - b.width).abs() <= tolerance &&
        (a.height - b.height).abs() <= tolerance;
  }

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
        final isCommentRateLimit =
            e.code == 'resource-exhausted' &&
            e.message.contains('コメントは60秒で2回までです');
        if (isCommentRateLimit) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              backgroundColor: AppColors.error,
            ),
          );
        } else {
          // ネガティブコンテンツが検出された場合
          await NegativeContentDialog.show(context: context, message: e.message);
        }
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

  Future<void> _resolveTutorialCommentRect() async {
    debugPrint('[TUTORIAL_PHASE2] resolve rect requested');
    final rect = await resolveRectWithRetry(
      _tutorialTargetCommentKey,
      ancestorKey: _tutorialOverlayStackKey,
    );
    debugPrint('[TUTORIAL_PHASE2] resolve rect result: $rect');
    if (!mounted) return;
    if (_isRectNearlyEqual(rect, _tutorialCommentRect)) return;
    debugPrint(
      '[TUTORIAL_PHASE2] update rect: old=$_tutorialCommentRect new=$rect',
    );
    setState(() => _tutorialCommentRect = rect);
  }

  void _maybeAutoScrollToComment() {
    if (_didAutoScrollToComment) return;
    debugPrint(
      '[TUTORIAL_PHASE2] schedule auto-scroll '
      'didAuto=$_didAutoScrollToComment retry=$_commentScrollRetryCount',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _didAutoScrollToComment) return;
      final targetContext = _tutorialTargetCommentKey.currentContext;
      if (targetContext == null) {
        debugPrint(
          '[TUTORIAL_PHASE2] target context not ready '
          'retry=$_commentScrollRetryCount/12',
        );
        if (_commentScrollRetryCount < 12) {
          _commentScrollRetryCount++;
          await Future.delayed(const Duration(milliseconds: 120));
          if (mounted) setState(() {});
        } else {
          debugPrint(
            '[TUTORIAL_PHASE2] fallback activated: retry limit reached',
          );
          if (mounted) {
            setState(() {
              _tutorialScrollFallback = true;
              _didAutoScrollToComment = true;
            });
          }
        }
        return;
      }
      debugPrint('[TUTORIAL_PHASE2] target context resolved');
      _didAutoScrollToComment = true;
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
      if (!mounted) return;
      debugPrint('[TUTORIAL_PHASE2] ensureVisible done');
      await _resolveTutorialCommentRect();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    timeago.setLocaleMessages('ja', timeago.JaMessages());

    // ユーザーのヘッダー色を取得
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final tutorialStep = ref.watch(tutorialPhase2Provider);
    if (_lastLoggedPhase2Step != tutorialStep) {
      debugPrint(
        '[TUTORIAL_PHASE2] step changed: $_lastLoggedPhase2Step -> $tutorialStep',
      );
      _lastLoggedPhase2Step = tutorialStep;
      // g) ステップ変更時のリセット
      if (tutorialStep != TutorialPhase2Step.commentLongPress) {
        _didAutoScrollToComment = false;
        _commentScrollRetryCount = 0;
        _tutorialTargetCommentId = null;
        _tutorialScrollFallback = false;
      }
    }
    final isSubscriber = currentUser?.isSubscriber ?? false;
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
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
    final topInset = MediaQuery.paddingOf(context).top;
    final appBarReservedHeight =
        topInset + kToolbarHeight + (isSubscriber ? 0 : 58);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        forceMaterialTransparency: true,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        bottom: isSubscriber
            ? null
            : const PreferredSize(
                preferredSize: Size.fromHeight(58),
                child: AdBanner(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                ),
              ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: userGradient),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(height: appBarReservedHeight),
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
                    final currentUserId = currentUser?.uid;
                    final isOwnPost =
                        currentUserId != null && currentUserId == post.userId;

                    if (isOwnPost &&
                        currentUser != null &&
                        !_phase2TutorialInitialized) {
                      _phase2TutorialInitialized = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        ref
                            .read(tutorialPhase2Provider.notifier)
                            .restoreOrStart(currentUser);
                      });
                    }

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

                    return Stack(
                      key: _tutorialOverlayStackKey,
                      clipBehavior: Clip.none,
                      children: [
                        CustomScrollView(
                          physics: (tutorialStep ==
                                      TutorialPhase2Step.commentLongPress &&
                                  !_tutorialScrollFallback)
                              ? const NeverScrollableScrollPhysics()
                              : null,
                          slivers: [
                            // 投稿本体（PostCardウィジェットを再利用）
                            SliverToBoxAdapter(
                              child: _buildPostCard(post, currentUser, isAdmin),
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
                                  if (_tutorialCommentRect != null) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (!mounted) return;
                                      setState(() => _tutorialCommentRect = null);
                                    });
                                  }
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

                                // b) ターゲットコメントIDの固定
                                final isCommentLongPress = tutorialStep ==
                                        TutorialPhase2Step.commentLongPress &&
                                    isOwnPost;

                                // ターゲットID消失時の再選定
                                if (isCommentLongPress &&
                                    _tutorialTargetCommentId != null) {
                                  final idStillExists = comments.any(
                                    (c) => c.id == _tutorialTargetCommentId,
                                  );
                                  if (!idStillExists) {
                                    debugPrint(
                                      '[TUTORIAL_PHASE2] target ID '
                                      '$_tutorialTargetCommentId disappeared, '
                                      're-selecting',
                                    );
                                    final replacement = comments
                                        .cast<CommentModel?>()
                                        .firstWhere(
                                          (c) => c!.userId != post.userId,
                                          orElse: () => null,
                                        );
                                    _tutorialTargetCommentId =
                                        replacement?.id;
                                    _didAutoScrollToComment = false;
                                    _commentScrollRetryCount = 0;
                                    _tutorialCommentRect = null;
                                    _tutorialScrollFallback = false;
                                    debugPrint(
                                      '[TUTORIAL_PHASE2] re-selected target: '
                                      '$_tutorialTargetCommentId',
                                    );
                                  }
                                }

                                // 初回ターゲット検出時にIDを固定
                                if (isCommentLongPress &&
                                    _tutorialTargetCommentId == null) {
                                  final firstNonOwner = comments
                                      .cast<CommentModel?>()
                                      .firstWhere(
                                        (c) => c!.userId != post.userId,
                                        orElse: () => null,
                                      );
                                  if (firstNonOwner != null) {
                                    _tutorialTargetCommentId =
                                        firstNonOwner.id;
                                    debugPrint(
                                      '[TUTORIAL_PHASE2] fixed target ID: '
                                      '$_tutorialTargetCommentId',
                                    );
                                  }
                                }

                                final tutorialTargetIndex = isCommentLongPress &&
                                        _tutorialTargetCommentId != null
                                    ? comments.indexWhere(
                                        (c) =>
                                            c.id ==
                                            _tutorialTargetCommentId,
                                      )
                                    : -1;
                                final hasTutorialTarget = tutorialTargetIndex >= 0;
                                final commentCount = comments.length;
                                if (_lastLoggedCommentCount != commentCount ||
                                    _lastLoggedHasTutorialTarget !=
                                        hasTutorialTarget) {
                                  debugPrint(
                                    '[TUTORIAL_PHASE2] comments=$commentCount '
                                    'hasTarget=$hasTutorialTarget '
                                    'targetIndex=$tutorialTargetIndex '
                                    'targetId=$_tutorialTargetCommentId '
                                    'step=$tutorialStep '
                                    'isOwnPost=$isOwnPost',
                                  );
                                  _lastLoggedCommentCount = commentCount;
                                  _lastLoggedHasTutorialTarget =
                                      hasTutorialTarget;
                                }

                                // e) 処理順序の制御: 自動スクロール → rect解決を統合
                                // フォールバック時はrect解決・overlay表示をスキップ
                                if (isCommentLongPress &&
                                    hasTutorialTarget &&
                                    !_tutorialScrollFallback) {
                                  if (!_didAutoScrollToComment) {
                                    // Phase 1: スクロール → rect解決
                                    _maybeAutoScrollToComment();
                                  } else if (_tutorialCommentRect == null) {
                                    // Phase 2: スクロール済み、rect再解決
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      _resolveTutorialCommentRect();
                                    });
                                  }
                                } else if (!(isCommentLongPress &&
                                        hasTutorialTarget) &&
                                    _tutorialCommentRect != null) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (!mounted) return;
                                    setState(() => _tutorialCommentRect = null);
                                  });
                                }

                                // c) eager build閾値チェック
                                final useEagerBuild = isCommentLongPress &&
                                    hasTutorialTarget &&
                                    commentCount <= 200;

                                // c) コメント200件超の場合はeager buildせずフォールバック
                                if (isCommentLongPress &&
                                    hasTutorialTarget &&
                                    commentCount > 200 &&
                                    !_tutorialScrollFallback) {
                                  debugPrint(
                                    '[TUTORIAL_PHASE2] fallback activated: '
                                    'comments=$commentCount > 200',
                                  );
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    if (!mounted) return;
                                    setState(() {
                                      _tutorialScrollFallback = true;
                                      _didAutoScrollToComment = true;
                                    });
                                  });
                                }

                                // コメントタイルビルダー
                                Widget buildCommentTile(
                                  CommentModel comment,
                                  bool isTutorialTarget,
                                ) {
                                  // f) フォールバック時は全非オーナーコメントに
                                  //    onThanksCompletedを付与
                                  final isNonOwnerComment =
                                      comment.userId != post.userId;
                                  final shouldAttachCallback =
                                      isCommentLongPress &&
                                          (isTutorialTarget ||
                                              (_tutorialScrollFallback &&
                                                  isNonOwnerComment));
                                  return _CommentTile(
                                    // Keep a stable key so long-press flow
                                    // is not disposed when tutorial state
                                    // switches to inactive.
                                    key: ValueKey(comment.id),
                                    comment: comment,
                                    postOwnerId: post.userId,
                                    disableTapActions: isTutorialTarget &&
                                        !_tutorialScrollFallback,
                                    spotlightCardKey: isTutorialTarget &&
                                            !_tutorialScrollFallback
                                        ? _tutorialTargetCommentKey
                                        : null,
                                    onThanksCompleted: shouldAttachCallback
                                        ? () async {
                                            await ref
                                                .read(
                                                  tutorialPhase2Provider
                                                      .notifier,
                                                )
                                                .markCompleted();
                                          }
                                        : null,
                                  );
                                }

                                // c) eager build切り替え
                                if (useEagerBuild) {
                                  return SliverToBoxAdapter(
                                    child: Column(
                                      children: [
                                        for (int i = 0;
                                            i < comments.length;
                                            i++)
                                          buildCommentTile(
                                            comments[i],
                                            hasTutorialTarget &&
                                                i == tutorialTargetIndex,
                                          ),
                                      ],
                                    ),
                                  );
                                }

                                return SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final comment = comments[index];
                                      final isTutorialTarget =
                                          hasTutorialTarget &&
                                              index == tutorialTargetIndex;
                                      return buildCommentTile(
                                        comment,
                                        isTutorialTarget,
                                      );
                                    },
                                    childCount: comments.length,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        if (isOwnPost && tutorialStep == TutorialPhase2Step.detailIntro)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: -appBarReservedHeight,
                            bottom: 0,
                            child: TutorialOverlay(
                              message: AppMessages.tutorial.postDetailOverview,
                              onMaskTap: () async {
                                await ref
                                    .read(tutorialPhase2Provider.notifier)
                                    .advance();
                              },
                              bubbleBottomOffset:
                                  MediaQuery.of(context).padding.bottom + 16,
                            ),
                          ),
                        if (isOwnPost && tutorialStep == TutorialPhase2Step.aiCommentNote)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: -appBarReservedHeight,
                            bottom: 0,
                            child: TutorialOverlay(
                              message: AppMessages.tutorial.postDetailAiCommentNote,
                              onMaskTap: () async {
                                await ref
                                    .read(tutorialPhase2Provider.notifier)
                                    .advance();
                              },
                              bubbleBottomOffset:
                                  MediaQuery.of(context).padding.bottom + 16,
                            ),
                          ),
                        if (isOwnPost &&
                            tutorialStep == TutorialPhase2Step.commentLongPress &&
                            _tutorialCommentRect != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: -appBarReservedHeight,
                            bottom: 0,
                            child: TutorialOverlay(
                              message: AppMessages.tutorial.postDetailLongPressComment,
                              // Overlay is shifted upward to cover AppBar area,
                              // so shift spotlight down by the same amount.
                              spotlightRect: _tutorialCommentRect!.shift(
                                Offset(0, appBarReservedHeight),
                              ),
                              passThroughSpotlight: true,
                              onMaskTap: () {},
                            ),
                          ),
                        Builder(
                          builder: (context) {
                            final overlayVisible = isOwnPost &&
                                tutorialStep ==
                                    TutorialPhase2Step.commentLongPress &&
                                _tutorialCommentRect != null;
                            if (_lastLoggedPhase2OverlayVisible !=
                                overlayVisible) {
                              debugPrint(
                                '[TUTORIAL_PHASE2] overlayVisible=$overlayVisible '
                                'step=$tutorialStep rect=$_tutorialCommentRect',
                              );
                              _lastLoggedPhase2OverlayVisible =
                                  overlayVisible;
                            }
                            return const SizedBox.shrink();
                          },
                        ),
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
                  top: false,
                  child: IgnorePointer(
                    ignoring:
                        tutorialStep == TutorialPhase2Step.commentLongPress,
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostCard(
    PostModel post,
    UserModel? currentUser,
    bool isAdmin,
  ) {
    if (post.circleId == null) {
      return PostCard(post: post, isDetailView: true);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('circles')
          .doc(post.circleId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final ownerId = data?['ownerId'] as String?;
        final subOwnerId = data?['subOwnerId'] as String?;
        final currentUserId = currentUser?.uid;
        final canManagePins =
            currentUserId != null &&
            (currentUserId == ownerId || currentUserId == subOwnerId || isAdmin);

        return PostCard(
          post: post,
          isDetailView: true,
          isCircleOwner: canManagePins,
          onPinToggle: canManagePins
              ? (isPinned) async {
                  final circleService = ref.read(circleServiceProvider);
                  await circleService.togglePinPost(post.id, isPinned);
                }
              : null,
        );
      },
    );
  }
}

/// コメントタイル
class _CommentTile extends StatefulWidget {
  final CommentModel comment;
  final String postOwnerId;
  final bool disableTapActions;
  final Future<void> Function()? onThanksCompleted;
  final Key? spotlightCardKey;

  const _CommentTile({
    super.key,
    required this.comment,
    required this.postOwnerId,
    this.disableTapActions = false,
    this.onThanksCompleted,
    this.spotlightCardKey,
  });

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _optimisticThanked = false;
  bool _isSubmitting = false;

  bool get _isThanked =>
      widget.comment.thanksLikedByPostOwner || _optimisticThanked;

  void _navigateToProfile(BuildContext context) {
    if (widget.disableTapActions) return;
    context.push('/profile/${widget.comment.userId}');
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final canThanks = currentUserId != null &&
        currentUserId == widget.postOwnerId &&
        widget.comment.userId != currentUserId;
    final showThanksStatus = canThanks && _isThanked;

    Future<void> handleThanksTap() async {
      if (!canThanks || _isThanked) return;

      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      icon: const Icon(Icons.favorite_rounded),
                      label: Text(AppMessages.stamp.thanksAction),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: Text(AppMessages.label.cancel),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (confirmed != true) return;

      setState(() {
        _isSubmitting = true;
        _optimisticThanked = true;
      });

      try {
        final service = CommentThanksService();
        await service.likeCommentAsPostOwner(widget.comment.id);
        if (!context.mounted) return;
      } catch (_) {
        if (!context.mounted) return;
        setState(() => _optimisticThanked = false);
      } finally {
        if (mounted) {
          setState(() => _isSubmitting = false);
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: widget.disableTapActions
                ? null
                : () => _navigateToProfile(context),
            child: PublicUserAvatar(
              userId: widget.comment.userId,
              avatarIndex: widget.comment.userAvatarIndex,
              size: 36,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onLongPress: canThanks && !_isSubmitting
                  ? () async {
                      // 先にボトムシートを開いて通常フローを開始し、
                      // その直後にチュートリアルを完了する。
                      final thanksFlow = handleThanksTap();
                      final onThanksCompleted = widget.onThanksCompleted;
                      if (onThanksCompleted != null) {
                        unawaited(onThanksCompleted());
                      }
                      await thanksFlow;
                    }
                  : null,
              child: Container(
                key: widget.spotlightCardKey,
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
                        GestureDetector(
                          onTap: widget.disableTapActions
                              ? null
                              : () => _navigateToProfile(context),
                          child: Text(
                            widget.comment.userDisplayName,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeago.format(widget.comment.createdAt, locale: 'ja'),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.comment.content,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                    if (showThanksStatus) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.favorite_rounded,
                            size: 16,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            AppMessages.stamp.thanksSent,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ],
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
