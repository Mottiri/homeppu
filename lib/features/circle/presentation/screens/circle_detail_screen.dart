// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/models/circle_model.dart';
import '../../../../shared/models/post_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/circle_service.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/utils/dialog_helper.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../shared/widgets/infinite_scroll_listener.dart';
import '../../../../shared/widgets/load_more_footer.dart';
import '../widgets/circle_actions.dart';
import '../widgets/circle_header.dart';
import '../widgets/circle_posts_list.dart';

/// サークル詳細画面
class CircleDetailScreen extends ConsumerStatefulWidget {
  final String circleId;

  const CircleDetailScreen({super.key, required this.circleId});

  @override
  ConsumerState<CircleDetailScreen> createState() => _CircleDetailScreenState();
}

class _CircleDetailScreenState extends ConsumerState<CircleDetailScreen> {
  bool _isJoining = false;
  bool _hasPendingRequest = false;
  bool _hasCheckedPending = false;
  String? _lastCheckedUserId;
  bool _hasShownDeletedToast = false; // 削除済みトースト表示済みフラグ
  bool _isDeleting = false; // 削除中フラグ（自分で削除中の場合）

  // 投稿リスト用の状態変数（プル更新方式）
  List<PostModel> _posts = [];
  DocumentSnapshot? _lastDocument;
  bool _hasMorePosts = true;
  bool _isLoadingPosts = true;
  bool _isLoadingMorePosts = false;
  bool _isScrollable = false; // レイアウト後に再評価
  final ScrollController _scrollController = ScrollController();

  void _updatePinnedState(String postId, {required bool isPinned, bool clearTop = false}) {
    if (!mounted) return;
    bool changed = false;
    final updated = _posts.map((post) {
      if (post.id != postId) return post;
      final next = post.copyWith(
        isPinned: isPinned,
        isPinnedTop: clearTop ? false : post.isPinnedTop,
      );
      changed = true;
      return next;
    }).toList();
    if (changed) {
      setState(() => _posts = updated);
    }
  }

  void _setTopPinned(String postId) {
    if (!mounted) return;
    bool changed = false;
    final updated = _posts.map((post) {
      if (post.id == postId) {
        if (!post.isPinned || !post.isPinnedTop) changed = true;
        return post.copyWith(isPinned: true, isPinnedTop: true);
      }
      if (post.isPinnedTop) {
        changed = true;
        return post.copyWith(isPinnedTop: false);
      }
      return post;
    }).toList();
    if (changed) {
      setState(() => _posts = updated);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 投稿リストを読み込み
  Future<void> _loadPosts() async {
    setState(() => _isLoadingPosts = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('circleId', isEqualTo: widget.circleId)
          .where('isVisible', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(AppConstants.postsPerPage)
          .get();

      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      if (mounted) {
        setState(() {
          _posts = posts;
          _lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
          _hasMorePosts = snapshot.docs.length == AppConstants.postsPerPage;
          _isLoadingPosts = false;
        });
        // レイアウト後にスクロール可能か再評価
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateScrollable();
        });
      }
    } catch (e) {
      debugPrint('Error loading circle posts: $e');
      if (mounted) {
        setState(() {
          _isLoadingPosts = false;
          _hasMorePosts = false; // エラー時はLoadMoreFooter表示抑制
        });
      }
    }
  }

  /// スクロール可能かを再評価
  void _updateScrollable() {
    if (!mounted) return;
    final scrollable =
        _scrollController.hasClients &&
        _scrollController.position.maxScrollExtent > 0;
    if (_isScrollable != scrollable) {
      setState(() => _isScrollable = scrollable);
    }
  }

  /// 追加読み込み（無限スクロール）
  Future<void> _loadMorePosts() async {
    if (!_hasMorePosts || _isLoadingMorePosts || _lastDocument == null) return;

    setState(() => _isLoadingMorePosts = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('circleId', isEqualTo: widget.circleId)
          .where('isVisible', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(AppConstants.postsPerPage)
          .startAfterDocument(_lastDocument!)
          .get();

      final newPosts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      if (mounted) {
        setState(() {
          _posts.addAll(newPosts);
          _lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
          _hasMorePosts = snapshot.docs.length == AppConstants.postsPerPage;
          _isLoadingMorePosts = false;
        });
        // レイアウト後にスクロール可能か再評価
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateScrollable();
        });
      }
    } catch (e) {
      debugPrint('Error loading more circle posts: $e');
      if (mounted) {
        setState(() => _isLoadingMorePosts = false);
      }
    }
  }

  Future<void> _checkPendingRequest(String userId) async {
    if (_hasCheckedPending && _lastCheckedUserId == userId) return;

    final circleService = ref.read(circleServiceProvider);
    final hasPending = await circleService.hasPendingRequest(
      widget.circleId,
      userId,
    );

    if (mounted) {
      setState(() {
        _hasPendingRequest = hasPending;
        _hasCheckedPending = true;
        _lastCheckedUserId = userId;
      });
    }
  }

  Future<void> _handleJoin(CircleModel circle, String userId) async {
    if (_isJoining) return;

    // BANユーザーチェック
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.isBanned == true) {
      SnackBarHelper.showError(context, AppMessages.error.banned);
      return;
    }

    // ルールがある場合は同意ダイアログを表示
    if (circle.rules != null && circle.rules!.isNotEmpty) {
      final agreed = await _showRulesConsentDialog(circle.rules!);
      if (agreed != true) return;
    }

    setState(() => _isJoining = true);

    try {
      final circleService = ref.read(circleServiceProvider);

      if (circle.isPublic) {
        // 公開サークル: 即参加
        await circleService.joinCircle(widget.circleId);
        if (mounted) {
          SnackBarHelper.showSuccess(context, AppMessages.success.circleJoined);
        }
      } else {
        // 招待制サークル: 参加申請
        final confirm = await DialogHelper.showConfirmDialog(
          context: context,
          title: AppMessages.circle.joinRequestTitle,
          message: AppMessages.circle.joinRequestMessage,
          confirmText: AppMessages.circle.joinRequestConfirm,
        );

        if (confirm == true) {
          await circleService.sendJoinRequest(widget.circleId, userId);
          if (mounted) {
            setState(() => _hasPendingRequest = true);
            SnackBarHelper.showSuccess(
              context,
              AppMessages.circle.joinRequestSent,
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
        debugPrint('サークル参加エラー: $e');
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _handleLeave(String userId) async {
    final confirm = await DialogHelper.showConfirmDialog(
      context: context,
      title: AppMessages.circle.leaveTitle,
      message: AppMessages.circle.leaveMessage,
      confirmText: AppMessages.circle.leaveConfirm,
      isDangerous: true,
      barrierDismissible: false,
    );

    if (confirm == true) {
      try {
        final circleService = ref.read(circleServiceProvider);
        await circleService.leaveCircle(widget.circleId);

        if (mounted) {
          // 状態をリセット
          setState(() {
            _hasPendingRequest = false;
            _hasCheckedPending = false; // 再度チェックさせるためにfalseに
          });

          // 最新の状態を確認（招待制の場合など）
          _checkPendingRequest(userId);

          SnackBarHelper.showSuccess(context, AppMessages.success.circleLeft);
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(context, AppMessages.error.general);
          debugPrint('退会エラー: $e');
        }
      }
    }
  }

  /// サークル削除ダイアログ
  Future<void> _showDeleteDialog(CircleModel circle) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[400], size: 28),
            const SizedBox(width: 8),
            Text(AppMessages.circle.deleteTitle),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppMessages.circle.deletePrompt(circle.name),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                AppMessages.circle.deleteDetails,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: AppMessages.circle.deleteReasonLabel,
                  hintText: AppMessages.circle.deleteReasonHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.message_outlined),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppMessages.label.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(AppMessages.circle.deleteConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _handleDeleteCircle(circle, reasonController.text.trim());
    reasonController.dispose();
  }

  /// サークル削除処理
  Future<void> _handleDeleteCircle(CircleModel circle, String? reason) async {
    // 削除中フラグをセット（isDeletedチェックをスキップするため）
    setState(() => _isDeleting = true);

    // 削除中のSnackBarを表示（一覧画面に戻るまで表示）
    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
    if (scaffoldMessenger == null) return;

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            Text(AppMessages.circle.deleteInProgress),
          ],
        ),
        duration: const Duration(minutes: 5), // 長めに設定（後で消す）
        backgroundColor: Colors.orange,
      ),
    );

    try {
      final circleService = ref.read(circleServiceProvider);

      await circleService.deleteCircle(
        circleId: circle.id,
        reason: reason?.isEmpty == true ? null : reason,
      );

      scaffoldMessenger.hideCurrentSnackBar();

      if (mounted) {
        SnackBarHelper.showSuccess(context, AppMessages.success.circleDeleted);
        // go()で一覧に戻る（forceRefreshで強制リロード）
        context.go('/circles', extra: {'forceRefresh': true});
      }
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
        debugPrint('削除失敗: $e');
      }
    }
  }

  /// ルール同意ダイアログ（参加前）
  Future<bool?> _showRulesConsentDialog(String rules) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.description_outlined, color: Colors.grey[700]),
            const SizedBox(width: 8),
            Text(AppMessages.circle.rulesTitle),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Text(
                  rules,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[800],
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppMessages.circle.rulesConsentMessage,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppMessages.label.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00ACC1),
              foregroundColor: Colors.white,
            ),
            child: Text(AppMessages.circle.rulesAgree),
          ),
        ],
      ),
    );
  }

  /// ルール確認ダイアログ（メンバー用）
  void _showRulesDialog(String rules) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.description_outlined, color: Colors.grey[700]),
            const SizedBox(width: 8),
            Text(AppMessages.circle.rulesTitle),
          ],
        ),
        content: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Text(
              rules,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[800],
                height: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppMessages.label.close),
          ),
        ],
      ),
    );
  }

  /// ピン留め投稿一覧ボトムシート
  void _showPinnedPostsList(List<PostModel> pinnedPosts, bool isOwner) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ハンドル
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // タイトル
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.push_pin, color: Colors.amber[700]),
                  const SizedBox(width: 8),
                  Text(
                    AppMessages.circle.pinnedPostsTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // リスト
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: pinnedPosts.length,
                itemBuilder: (context, index) {
                  final post = pinnedPosts[index];
                  return ListTile(
                    leading: post.isPinnedTop
                        ? Icon(Icons.star, color: Colors.amber[700])
                        : Icon(
                            Icons.push_pin_outlined,
                            color: Colors.grey[400],
                          ),
                    title: Text(
                      post.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      post.isPinnedTop ? AppMessages.circle.pinnedTopLabel : '',
                      style: TextStyle(color: Colors.amber[700], fontSize: 12),
                    ),
                    trailing: isOwner
                        ? PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) async {
                              final circleService = ref.read(
                                circleServiceProvider,
                              );
                              Navigator.pop(context);
                              if (value == 'top') {
                                await circleService.setTopPinnedPost(
                                  post.circleId!,
                                  post.id,
                                );
                                _setTopPinned(post.id);
                              } else if (value == 'unpin') {
                                await circleService.togglePinPost(
                                  post.id,
                                  false,
                                );
                                _updatePinnedState(
                                  post.id,
                                  isPinned: false,
                                  clearTop: true,
                                );
                              }
                            },
                            itemBuilder: (context) => [
                              if (!post.isPinnedTop)
                                PopupMenuItem(
                                  value: 'top',
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.star,
                                        color: Colors.amber,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(AppMessages.circle.pinnedTopAction),
                                    ],
                                  ),
                                ),
                              PopupMenuItem(
                                value: 'unpin',
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.push_pin_outlined,
                                      color: Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(AppMessages.circle.pinnedRemove),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/post/${post.id}');
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final circleService = ref.watch(circleServiceProvider);

    return StreamBuilder<CircleModel?>(
      stream: circleService.streamCircle(widget.circleId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          // サークルが削除された場合、一覧画面に戻る
          if (snapshot.connectionState == ConnectionState.active &&
              snapshot.data == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                SnackBarHelper.showWarning(
                  context,
                  AppMessages.circle.circleDeleted,
                );
                context.go('/circles');
              }
            });
          }
          return Scaffold(
            backgroundColor: Colors.grey[50],
            body: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        final circle = snapshot.data!;

        // 削除済みサークルの場合、トーストを表示して一覧に戻る（自分で削除中はスキップ）
        if (circle.isDeleted && !_isDeleting && !_hasShownDeletedToast) {
          _hasShownDeletedToast = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              SnackBarHelper.showWarning(
                context,
                AppMessages.circle.circleDeleted,
              );
              context.go('/circles');
            }
          });
          return Scaffold(
            backgroundColor: Colors.grey[50],
            body: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        // CircleServiceのカテゴリアイコンを使用
        final icon = CircleService.categoryIcons[circle.category] ?? '⭐';
        final isMember =
            currentUser != null &&
            circleService.isMember(circle, currentUser.uid);
        final isOwner =
            currentUser != null &&
            circleService.isOwner(circle, currentUser.uid);
        final isSubOwner =
            currentUser != null &&
            circleService.isSubOwner(circle, currentUser.uid);
        // 管理者チェック
        final isAdminAsync = ref.watch(isAdminProvider);
        final isAdmin = isAdminAsync.valueOrNull ?? false;
        final canManagePins = isOwner || isSubOwner || isAdmin;
        final canPost = isMember || isAdmin; // 管理者は未参加でも投稿可

        // 非公開サークルで非メンバーの場合、申請中かチェック
        if (!circle.isPublic && !isMember && currentUser != null) {
          _checkPendingRequest(currentUser.uid);
        }

        return Scaffold(
          backgroundColor: Colors.grey[50],
          floatingActionButton: canPost
              ? FloatingActionButton(
                  onPressed: () async {
                    // BANユーザーチェック
                    if (currentUser?.isBanned == true) {
                      SnackBarHelper.showError(
                        context,
                        AppMessages.error.banned,
                      );
                      return;
                    }

                    final result = await context.push<bool>(
                      '/create-post',
                      extra: {'circleId': widget.circleId},
                    );
                    // 投稿作成成功後、リストをリロード
                    if (result == true) {
                      _loadPosts();
                    }
                  },
                  backgroundColor: const Color(0xFF00ACC1), // シアン
                  child: const Icon(Icons.edit, color: Colors.white),
                )
              : null,
          body: InfiniteScrollListener(
            isLoadingMore: _isLoadingMorePosts,
            hasMore: _hasMorePosts,
            onLoadMore: _loadMorePosts,
            child: RefreshIndicator(
              onRefresh: _loadPosts,
              color: AppColors.primary,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // ヘッダー
                  CircleHeader(
                    circle: circle,
                    icon: icon,
                    isOwner: isOwner,
                    isAdmin: isAdmin,
                    isSubOwner: isSubOwner,
                    onShowRules: () => _showRulesDialog(circle.rules ?? ''),
                    onShowMembers: () {
                      context.push(
                        '/circle/${circle.id}/members',
                        extra: {
                          'circleName': circle.name,
                          'ownerId': circle.ownerId,
                          'subOwnerId': circle.subOwnerId,
                          'memberIds': circle.memberIds,
                        },
                      );
                    },
                    onEdit: () => context.push(
                      '/circle/${circle.id}/edit',
                      extra: circle,
                    ),
                    onRequests: () => context.push(
                      '/circle/${circle.id}/requests',
                      extra: {'circleName': circle.name},
                    ),
                    onDelete: () => _showDeleteDialog(circle),
                  ),

                  // 参加ボタンと説明
                  SliverToBoxAdapter(
                    child: CircleActions(
                      circle: circle,
                      isMember: isMember,
                      isOwner: isOwner,
                      hasPendingRequest: _hasPendingRequest,
                      isJoining: _isJoining,
                      isLoggedIn: currentUser != null,
                      onLogin: () => context.push('/login'),
                      onLeave: isOwner || currentUser == null
                          ? null
                          : () => _handleLeave(currentUser.uid),
                      onJoin: currentUser == null
                          ? () {}
                          : () => _handleJoin(circle, currentUser.uid),
                    ),
                  ),
                  // ピン留め投稿セクション（オーナーのみ管理可能）
                  if (isMember)
                    StreamBuilder<List<PostModel>>(
                      stream: circleService.streamPinnedPosts(circle.id),
                      builder: (context, pinnedSnapshot) {
                        final pinnedPosts = pinnedSnapshot.data ?? [];
                        if (pinnedPosts.isEmpty) {
                          return const SliverToBoxAdapter(
                            child: SizedBox.shrink(),
                          );
                        }

                        // トップピン投稿を取得
                        final topPinned = pinnedPosts.firstWhere(
                          (p) => p.isPinnedTop,
                          orElse: () => pinnedPosts.first,
                        );

                        return SliverToBoxAdapter(
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.push_pin,
                                      size: 16,
                                      color: Colors.amber[700],
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      AppMessages.circle.pinnedSectionTitle,
                                      style: TextStyle(
                                        color: Colors.amber[700],
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (pinnedPosts.length > 1)
                                      GestureDetector(
                                        onTap: () => _showPinnedPostsList(
                                          pinnedPosts,
                                          canManagePins,
                                        ),
                                        child: Row(
                                          children: [
                                            Text(
                                              AppMessages.circle.pinnedCount(
                                                pinnedPosts.length,
                                              ),
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 12,
                                              ),
                                            ),
                                            Icon(
                                              Icons.chevron_right,
                                              size: 16,
                                              color: Colors.grey[600],
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () =>
                                      context.push('/post/${topPinned.id}'),
                                  child: Text(
                                    topPinned.content,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey[800],
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                  // 投稿ヘッダー
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Row(
                        children: [
                          const Text('📝', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Text(
                            AppMessages.circle.postsTitle,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // サークル内の投稿（プル更新方式）
                  CirclePostsList(
                    posts: _posts,
                    isLoading: _isLoadingPosts,
                    isLoadingMore: _isLoadingMorePosts,
                    hasMore: _hasMorePosts,
                    canManagePins: canManagePins,
                    onPinToggle: canManagePins
                        ? (index, post, isPinned) async {
                            await circleService.togglePinPost(
                              post.id,
                              isPinned,
                            );
                            _updatePinnedState(
                              post.id,
                              isPinned: isPinned,
                              clearTop: !isPinned,
                            );
                          }
                        : null,
                    onPostDeleted: (index) {
                      setState(() {
                        _posts.removeAt(index);
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _updateScrollable();
                      });
                    },
                  ),

                  // ショートリスト用「もっと読み込む」ボタン
                  SliverToBoxAdapter(
                    child: LoadMoreFooter(
                      hasMore: _hasMorePosts,
                      isLoadingMore: _isLoadingMorePosts,
                      isInitialLoadComplete: !_isLoadingPosts,
                      canLoadMore: _lastDocument != null,
                      isScrollable: _isScrollable,
                      onLoadMore: _loadMorePosts,
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


}
