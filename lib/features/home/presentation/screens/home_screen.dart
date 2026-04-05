import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../shared/models/post_model.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/repositories/notification_repository.dart';
import '../../../../shared/providers/public_user_provider.dart';
import '../../../../shared/widgets/ad_banner.dart';
import '../../../../shared/widgets/native_feed_ad_card.dart';
import '../../../../shared/providers/tutorial_phase1_provider.dart';
import '../../../../shared/widgets/tutorial_overlay.dart';
import '../widgets/post_card.dart';
import 'package:go_router/go_router.dart';
import '../../../../shared/widgets/infinite_scroll_listener.dart';

final timelineRefreshProvider = StateProvider<int>((ref) => 0);

final homeScrollToTopProvider = StateProvider<int>((ref) => 0);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _tutorialOverlayStackKey = GlobalKey();
  Rect? _firstPostCardRect;

  void _onFirstPostCardRectChanged(Rect? rect) {
    if (!mounted) return;
    if (_firstPostCardRect == rect) return;
    setState(() => _firstPostCardRect = rect);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final tutorialStep = ref.watch(tutorialPhase1Provider);
    final isTutorialHomeOverview =
        tutorialStep == TutorialPhase1Step.homeOverview;
    final isTutorialHomeLongPress =
        tutorialStep == TutorialPhase1Step.homeLongPress;
    final isHomeTutorialActive =
        isTutorialHomeOverview || isTutorialHomeLongPress;
    final refreshKey = ref.watch(timelineRefreshProvider);
    ref.listen<int>(homeScrollToTopProvider, (previous, next) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
    final user = currentUser.valueOrNull;
    final isSubscriber = user?.isSubscriber ?? false;
    final primaryColor = user?.headerPrimaryColor != null
        ? Color(user!.headerPrimaryColor!)
        : AppColors.primary;
    final secondaryColor = user?.headerSecondaryColor != null
        ? Color(user!.headerSecondaryColor!)
        : AppColors.secondary;
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
        decoration: BoxDecoration(

          gradient: userGradient,
        ),
        child: Stack(
          key: _tutorialOverlayStackKey,
          children: [
            SafeArea(
              child: NestedScrollView(
                physics: isTutorialHomeLongPress
                    ? const NeverScrollableScrollPhysics()
                    : null,
                controller: _scrollController,
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _TimelineHeaderDelegate(
                        isSubscriber: isSubscriber,
                        currentUserAsync: currentUser,
                        tabController: _tabController,
                      ),
                    ),
                  ];
                },
                body: TabBarView(
                  controller: _tabController,
                  physics: isHomeTutorialActive
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  children: [
                    _TimelineTab(
                      isFollowingOnly: false,
                      currentUser: currentUser.valueOrNull,
                      refreshKey: refreshKey,
                      onFirstPostCardRectChanged: _onFirstPostCardRectChanged,
                      tutorialOverlayAncestorKey: _tutorialOverlayStackKey,
                    ),
                    _TimelineTab(
                      isFollowingOnly: true,
                      currentUser: currentUser.valueOrNull,
                      refreshKey: refreshKey,
                      onFirstPostCardRectChanged: _onFirstPostCardRectChanged,
                      tutorialOverlayAncestorKey: _tutorialOverlayStackKey,
                    ),
                  ],
                ),
              ),
            ),
            if (isTutorialHomeOverview)
              TutorialOverlay(
                message: AppMessages.tutorial.homeOverview,
                onMaskTap: () =>
                    ref.read(tutorialPhase1Provider.notifier).advance(),
                characterAssetPath: 'assets/onbord/onbord_01.webp',
                bubbleBottomOffset: MediaQuery.of(context).padding.bottom + 64,
              ),
            if (isTutorialHomeLongPress)
              TutorialOverlay(
                message: AppMessages.tutorial.homeLongPress,
                spotlightRect: _firstPostCardRect,
                passThroughSpotlight: true,
                characterAssetPath: 'assets/onbord/onbord_01.webp',
                bubbleBottomOffset: MediaQuery.of(context).padding.bottom + 64,
              ),
          ],
        ),
      ),
    );
  }
}

class _TimelineHeaderDelegate extends SliverPersistentHeaderDelegate {
  static const double _logoSectionHeight = 88;
  static const double _adSectionHeight = 58;
  static const double _tabSectionHeight = 48;

  final bool isSubscriber;
  final AsyncValue<UserModel?> currentUserAsync;
  final TabController tabController;

  _TimelineHeaderDelegate({
    required this.isSubscriber,
    required this.currentUserAsync,
    required this.tabController,
  });

  @override
  double get maxExtent =>
      _logoSectionHeight +
      (isSubscriber ? 0 : _adSectionHeight) +
      _tabSectionHeight;

  @override
  double get minExtent => isSubscriber ? 0 : _adSectionHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = (maxExtent - minExtent).clamp(0.0, double.infinity);
    final t = range == 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final logoFactor = 1.0 - t;
    final tabFactor = 1.0 - t;

    return ClipRect(
      child: SizedBox.expand(
        child: Align(
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeaderSection(
                height: _logoSectionHeight,
                factor: logoFactor,
                child: _LogoAndNotificationRow(
                  currentUserAsync: currentUserAsync,
                ),
              ),
              if (!isSubscriber)
                const _HeaderSection(
                  height: _adSectionHeight,
                  factor: 1,
                  child: AdBanner(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                    reserveSpace: true,
                  ),
                ),
              _HeaderSection(
                height: _tabSectionHeight,
                factor: tabFactor,
                child: TabBar(
                  controller: tabController,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textHint,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 15,
                  ),
                  tabs: [
                    Tab(text: AppMessages.home.tabRecommended),
                    Tab(text: AppMessages.home.tabFollowing),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_TimelineHeaderDelegate oldDelegate) {
    return isSubscriber != oldDelegate.isSubscriber ||
        currentUserAsync != oldDelegate.currentUserAsync ||
        tabController != oldDelegate.tabController;
  }
}

class _HeaderSection extends StatelessWidget {
  final double height;
  final double factor;
  final Widget child;

  const _HeaderSection({
    required this.height,
    required this.factor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height * factor,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: factor,
          child: Opacity(
            opacity: factor.clamp(0, 1),
            child: IgnorePointer(ignoring: factor < 0.02, child: child),
          ),
        ),
      ),
    );
  }
}

class _LogoAndNotificationRow extends StatelessWidget {
  final AsyncValue<UserModel?> currentUserAsync;

  const _LogoAndNotificationRow({required this.currentUserAsync});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.asset('assets/icons/logo.webp', width: 72, height: 72)
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(
                  duration: 3000.ms,
                  color: AppColors.primary.withValues(alpha: 0.1),
                ),
            Positioned(
              right: 0,
              child: currentUserAsync.when(
                data: (user) {
                  if (user == null) return const SizedBox.shrink();
                  return Consumer(
                    builder: (context, ref, _) {
                      final repo = ref.watch(notificationRepositoryProvider);
                      return StreamBuilder<int>(
                        stream: repo.getUnreadCountStream(user.uid),
                        builder: (context, snapshot) {
                          final count = snapshot.data ?? 0;
                          return Stack(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.notifications_outlined,
                                  size: 28,
                                ),
                                onPressed: () => context.push('/notifications'),
                              ),
                              if (count > 0)
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: AppColors.error,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Text(
                                      count > 99 ? '99+' : '$count',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (e, _) => const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineTab extends StatelessWidget {
  final bool isFollowingOnly;
  final UserModel? currentUser;
  final int refreshKey;
  final ValueChanged<Rect?>? onFirstPostCardRectChanged;
  final GlobalKey? tutorialOverlayAncestorKey;

  const _TimelineTab({
    required this.isFollowingOnly,
    required this.currentUser,
    this.refreshKey = 0,
    this.onFirstPostCardRectChanged,
    this.tutorialOverlayAncestorKey,
  });

  String? get currentUserId => currentUser?.uid;

  @override
  Widget build(BuildContext context) {

    if (isFollowingOnly && currentUser != null) {
      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .snapshots(),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
          final followingIds = List<String>.from(userData?['following'] ?? []);

          if (followingIds.isEmpty) {
            return _EmptyFollowingState();
          }

          return _ChunkedPostsList(
            followingIds: followingIds,
            isAIViewer: currentUser!.isAI,
            currentUserId: currentUserId,
            refreshKey: refreshKey,
            onFirstPostCardRectChanged: onFirstPostCardRectChanged,
            tutorialOverlayAncestorKey: tutorialOverlayAncestorKey,
          );
        },
      );
    }
    return _PostsList(
      query: FirebaseFirestore.instance
          .collection('posts')
          .where('isVisible', isEqualTo: true)
          .where('circleId', isNull: true)
          .orderBy('createdAt', descending: true)
          .limit(AppConstants.postsPerPage),
      isAIViewer: currentUser?.isAI ?? false,
      currentUserId: currentUserId,
      refreshKey: refreshKey,
      onFirstPostCardRectChanged: onFirstPostCardRectChanged,
      tutorialOverlayAncestorKey: tutorialOverlayAncestorKey,
    );
  }
}

// =============================================================================
// _ChunkedPostsList — Following タブ専用（_PostsList と同一 UI ロジック）
// followingIds を10件チャンクに分割し、並列クエリ→マージソートで全件表示
// Phase 2 で _PostsList と共通化予定
// =============================================================================
class _ChunkedPostsList extends ConsumerStatefulWidget {
  final List<String> followingIds;
  final bool isAIViewer;
  final String? currentUserId;
  final int refreshKey;
  final ValueChanged<Rect?>? onFirstPostCardRectChanged;
  final GlobalKey? tutorialOverlayAncestorKey;

  const _ChunkedPostsList({
    required this.followingIds,
    this.isAIViewer = false,
    this.currentUserId,
    this.refreshKey = 0,
    this.onFirstPostCardRectChanged,
    this.tutorialOverlayAncestorKey,
  });

  @override
  ConsumerState<_ChunkedPostsList> createState() => _ChunkedPostsListState();
}

class _ChunkedPostsListState extends ConsumerState<_ChunkedPostsList>
    with WidgetsBindingObserver {
  static const int _chunkSize = 10;
  static const int _nativeAdInterval = 10;
  static const double _scrollToTopFabMinOffset = 120;
  static const double _fabShowThreshold = 24;
  static const double _fabHideThreshold = 72;

  List<PostModel> _posts = [];
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasError = false;
  bool _showScrollToTopFab = false;
  double _fabScrollAccumulator = 0;
  int _fabScrollDirection = 0;
  final GlobalKey _firstPostCardKey = GlobalKey();
  Rect? _lastReportedFirstPostRect;
  ProviderSubscription<TutorialPhase1Step>? _tutorialStepSubscription;
  ProviderSubscription<int>? _homeScrollTopSubscription;
  bool _isResolvingFirstPostRect = false;
  bool _pendingFirstPostRectRefresh = false;

  // チャンク管理
  int _loadGeneration = 0;
  List<List<String>> _chunks = [];
  List<DocumentSnapshot?> _lastDocuments = [];
  List<bool> _chunkHasMore = [];

  // --- チャンク分割ユーティリティ ---
  List<List<String>> _buildChunks(List<String> ids) {
    final chunks = <List<String>>[];
    for (var i = 0; i < ids.length; i += _chunkSize) {
      chunks.add(ids.sublist(i, (i + _chunkSize).clamp(0, ids.length)));
    }
    return chunks;
  }

  // --- 広告ヘルパー（_PostsList と同一ロジック） ---
  int _nativeAdCountForPosts(int postsCount) =>
      postsCount ~/ _nativeAdInterval;

  bool _isNativeAdIndex(int displayIndex) {
    final slot = _nativeAdInterval + 1;
    return (displayIndex + 1) % slot == 0;
  }

  int _postIndexFromDisplayIndex(int displayIndex) {
    final adsBefore = (displayIndex + 1) ~/ (_nativeAdInterval + 1);
    return displayIndex - adsBefore;
  }

  // --- ライフサイクル ---
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPosts();
    _tutorialStepSubscription = ref.listenManual<TutorialPhase1Step>(
      tutorialPhase1Provider,
      (prev, next) => _onTutorialStepChanged(next),
      fireImmediately: true,
    );
    _homeScrollTopSubscription = ref.listenManual<int>(
      homeScrollToTopProvider,
      (_, unusedNext) => _scrollToTop(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tutorialStepSubscription?.close();
    _homeScrollTopSubscription?.close();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshFirstPostCardRectIfNeeded();
      }
    });
  }

  @override
  void didUpdateWidget(_ChunkedPostsList oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!listEquals(widget.followingIds, oldWidget.followingIds) ||
        widget.refreshKey != oldWidget.refreshKey) {
      _loadPosts();
    }
    if (widget.onFirstPostCardRectChanged == null &&
        oldWidget.onFirstPostCardRectChanged != null) {
      _lastReportedFirstPostRect = null;
    }
  }

  // --- チュートリアル rect 管理（_PostsList と同一ロジック） ---
  void _onTutorialStepChanged(TutorialPhase1Step step) {
    if (widget.onFirstPostCardRectChanged == null) return;
    final shouldReport = step == TutorialPhase1Step.homeLongPress;
    if (!shouldReport || _posts.isEmpty) {
      _clearFirstPostCardRect();
      return;
    }
    _resolveFirstPostCardRect();
  }

  void _resolveFirstPostCardRect() {
    if (_isResolvingFirstPostRect) {
      _pendingFirstPostRectRefresh = true;
      return;
    }
    _isResolvingFirstPostRect = true;
    _pendingFirstPostRectRefresh = false;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _isResolvingFirstPostRect = false;
        return;
      }
      final rect = await resolveRectWithRetry(
        _firstPostCardKey,
        ancestorKey: widget.tutorialOverlayAncestorKey,
      );
      _isResolvingFirstPostRect = false;
      if (!mounted) return;
      if (_lastReportedFirstPostRect != rect) {
        _lastReportedFirstPostRect = rect;
        widget.onFirstPostCardRectChanged!(rect);
      }
      if (_pendingFirstPostRectRefresh && mounted) {
        _pendingFirstPostRectRefresh = false;
        _resolveFirstPostCardRect();
      }
    });
  }

  void _clearFirstPostCardRect() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_lastReportedFirstPostRect != null) {
        _lastReportedFirstPostRect = null;
        widget.onFirstPostCardRectChanged!(null);
      }
    });
  }

  void _refreshFirstPostCardRectIfNeeded() {
    final currentStep = ref.read(tutorialPhase1Provider);
    if (currentStep != TutorialPhase1Step.homeLongPress) return;
    if (_posts.isNotEmpty) {
      _resolveFirstPostCardRect();
    } else {
      _clearFirstPostCardRect();
    }
  }

  // --- データ読み込み（チャンク並列クエリ） ---
  Future<void> _loadPosts({bool invalidateAvatarCache = false}) async {
    final generation = ++_loadGeneration;

    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _hasError = false;
    });

    try {
      _chunks = _buildChunks(widget.followingIds);
      _lastDocuments = List.filled(_chunks.length, null);
      _chunkHasMore = List.filled(_chunks.length, true);

      // フォロー100超の監視ログ（Phase 2 Fan-out on Write で根本解決予定）
      if (_chunks.length > 10) {
        debugPrint(
            '[ChunkedPostsList] Large follow graph: ${widget.followingIds.length} users, ${_chunks.length} chunks');
      }

      final limit = AppConstants.postsPerPage;
      final futures = _chunks
          .map((chunk) => FirebaseFirestore.instance
              .collection('posts')
              .where('isVisible', isEqualTo: true)
              .where('userId', whereIn: chunk)
              .orderBy('createdAt', descending: true)
              .limit(limit)
              .get())
          .toList();

      final snapshots = await Future.wait(futures);

      // 古いリクエストの結果を破棄
      if (generation != _loadGeneration || !mounted) return;

      final allPosts = <PostModel>[];
      final seenIds = <String>{};

      for (var i = 0; i < snapshots.length; i++) {
        final snapshot = snapshots[i];
        _lastDocuments[i] =
            snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _chunkHasMore[i] = snapshot.docs.length == limit;

        for (final doc in snapshot.docs) {
          final post = PostModel.fromFirestore(doc);
          if (seenIds.add(post.id)) {
            allPosts.add(post);
          }
        }
      }

      var posts = allPosts
          .where((post) => post.circleId == null || post.circleId!.isEmpty)
          .toList();

      if (!widget.isAIViewer) {
        posts = posts
            .where((post) =>
                post.postMode != 'ai' || post.userId == widget.currentUserId)
            .toList();
      }

      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (invalidateAvatarCache) {
        final userIds = posts.map((post) => post.userId).toSet();
        for (final userId in userIds) {
          ref.invalidate(publicUserDocProvider(userId));
        }
      }

      setState(() {
        _posts = posts;
        _hasMore = _chunkHasMore.any((h) => h);
        _isLoading = false;
      });

      _refreshFirstPostCardRectIfNeeded();
    } catch (e) {
      if (generation != _loadGeneration || !mounted) return;
      debugPrint('Error loading chunked posts: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _refreshPosts() => _loadPosts(invalidateAvatarCache: true);

  Future<void> _loadMorePosts() async {
    if (!_hasMore || _isLoadingMore) return;

    final generation = _loadGeneration;
    setState(() => _isLoadingMore = true);

    try {
      final limit = AppConstants.postsPerPage;
      final futures = <Future<QuerySnapshot>>[];
      final chunkIndices = <int>[];

      for (var i = 0; i < _chunks.length; i++) {
        if (_chunkHasMore[i] && _lastDocuments[i] != null) {
          chunkIndices.add(i);
          futures.add(
            FirebaseFirestore.instance
                .collection('posts')
                .where('isVisible', isEqualTo: true)
                .where('userId', whereIn: _chunks[i])
                .orderBy('createdAt', descending: true)
                .limit(limit)
                .startAfterDocument(_lastDocuments[i]!)
                .get(),
          );
        }
      }

      if (futures.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoadingMore = false;
        });
        return;
      }

      final snapshots = await Future.wait(futures);

      // 古いリクエストの結果を破棄
      if (generation != _loadGeneration || !mounted) return;

      final existingIds = _posts.map((p) => p.id).toSet();
      final newPosts = <PostModel>[];

      for (var j = 0; j < snapshots.length; j++) {
        final i = chunkIndices[j];
        final snapshot = snapshots[j];
        _lastDocuments[i] =
            snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _chunkHasMore[i] = snapshot.docs.length == limit;

        for (final doc in snapshot.docs) {
          final post = PostModel.fromFirestore(doc);
          if (!existingIds.contains(post.id) &&
              (post.circleId == null || post.circleId!.isEmpty)) {
            if (widget.isAIViewer ||
                post.postMode != 'ai' ||
                post.userId == widget.currentUserId) {
              newPosts.add(post);
            }
          }
        }
      }

      setState(() {
        _posts.addAll(newPosts);
        _posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _hasMore = _chunkHasMore.any((h) => h);
        _isLoadingMore = false;
      });
    } catch (e) {
      if (generation != _loadGeneration || !mounted) return;
      debugPrint('Error loading more chunked posts: $e');
      setState(() => _isLoadingMore = false);
    }
  }

  // --- スクロール制御（_PostsList と同一ロジック） ---
  void _scrollToTop() {
    final controller = PrimaryScrollController.maybeOf(context);
    if (controller != null && controller.hasClients) {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    if (_showScrollToTopFab) {
      setState(() => _showScrollToTopFab = false);
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _fabScrollAccumulator = 0;
      _fabScrollDirection = 0;
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      final pixels = notification.metrics.pixels;

      if (pixels <= _scrollToTopFabMinOffset) {
        if (_showScrollToTopFab) {
          setState(() => _showScrollToTopFab = false);
        }
        _fabScrollAccumulator = 0;
        _fabScrollDirection = 0;
        return false;
      }

      if (delta > 0) {
        if (_fabScrollDirection != 1) {
          _fabScrollDirection = 1;
          _fabScrollAccumulator = 0;
        }
        _fabScrollAccumulator += delta.abs();
        if (!_showScrollToTopFab &&
            _fabScrollAccumulator >= _fabShowThreshold) {
          _fabScrollAccumulator = 0;
          setState(() => _showScrollToTopFab = true);
        }
      } else if (delta < 0) {
        if (_fabScrollDirection != -1) {
          _fabScrollDirection = -1;
          _fabScrollAccumulator = 0;
        }
        _fabScrollAccumulator += delta.abs();
        if (_showScrollToTopFab &&
            _fabScrollAccumulator >= _fabHideThreshold) {
          _fabScrollAccumulator = 0;
          setState(() => _showScrollToTopFab = false);
        }
      }

      return false;
    }

    if (notification is ScrollEndNotification) {
      _fabScrollAccumulator = 0;
      _fabScrollDirection = 0;
      return false;
    }

    return false;
  }

  // --- UI 構築（_PostsList と同一ロジック、heroTag のみ変更） ---
  @override
  Widget build(BuildContext context) {
    final tutorialStep = ref.watch(tutorialPhase1Provider);
    final isTutorialHomeLongPress =
        tutorialStep == TutorialPhase1Step.homeLongPress;

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(AppMessages.home.timelineLoading),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('??', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(AppMessages.error.general, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadPosts,
              child: Text(AppMessages.label.retry),
            ),
          ],
        ),
      );
    }

    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshPosts,
        color: AppColors.primary,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('??', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 16),
                  Text(
                    AppMessages.home.emptyPostsTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppMessages.home.emptyPostsDescription,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        InfiniteScrollListener(
          isLoadingMore: _isLoadingMore,
          hasMore: _hasMore,
          onLoadMore: _loadMorePosts,
          child: Builder(
            builder: (context) {
              final contentCount =
                  _posts.length + _nativeAdCountForPosts(_posts.length);
              final totalCount = contentCount + (_isLoadingMore ? 1 : 0);
              final list = NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: ListView.builder(
                  physics: isTutorialHomeLongPress
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  padding: const EdgeInsets.only(bottom: 120),
                  itemCount: totalCount,
                  itemBuilder: (context, index) {
                    if (_isLoadingMore && index == contentCount) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                      );
                    }

                    if (_isNativeAdIndex(index)) {
                      return NativeFeedAdCard(
                        key: ValueKey('native_ad_slot_$index'),
                      );
                    }

                    final postIndex = _postIndexFromDisplayIndex(index);
                    final post = _posts[postIndex];
                    final isTutorialTargetCard =
                        postIndex == 0 && isTutorialHomeLongPress;
                    final postCard = PostCard(
                      key: postIndex == 0
                          ? _firstPostCardKey
                          : ValueKey(post.id),
                      post: post,
                      longPressOnlyMode: isTutorialTargetCard,
                      onReactionOverlayClosed: isTutorialTargetCard
                          ? () {
                              final step = ref.read(tutorialPhase1Provider);
                              if (step == TutorialPhase1Step.homeLongPress) {
                                ref
                                    .read(tutorialPhase1Provider.notifier)
                                    .markHomeLongPressCompleted();
                              }
                            }
                          : null,
                      onDeleted: () {
                        setState(() {
                          _posts.removeAt(postIndex);
                        });
                        _refreshFirstPostCardRectIfNeeded();
                      },
                    );
                    if (isTutorialTargetCard) {
                      return NotificationListener<
                          SizeChangedLayoutNotification>(
                        onNotification: (notification) {
                          _refreshFirstPostCardRectIfNeeded();
                          return true;
                        },
                        child: SizeChangedLayoutNotifier(
                          child: _LongPressProbe(
                            onLongPress: () {},
                            child: postCard,
                          ),
                        ),
                      );
                    }
                    return postCard;
                  },
                ),
              );

              if (isTutorialHomeLongPress) return list;

              return RefreshIndicator(
                onRefresh: _refreshPosts,
                color: AppColors.primary,
                child: list,
              );
            },
          ),
        ),
        Positioned(
          right: 24,
          bottom: MediaQuery.paddingOf(context).bottom + 28,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset:
                _showScrollToTopFab ? Offset.zero : const Offset(0, 1.2),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _showScrollToTopFab ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_showScrollToTopFab,
                child: FloatingActionButton.small(
                  heroTag:
                      'home_scroll_top_fab_chunked_${widget.currentUserId ?? 'guest'}',
                  onPressed: _scrollToTop,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PostsList extends ConsumerStatefulWidget {
  final Query query;
  final bool isAIViewer;
  final String? currentUserId;
  final int refreshKey;
  final ValueChanged<Rect?>? onFirstPostCardRectChanged;
  final GlobalKey? tutorialOverlayAncestorKey;

  const _PostsList({
    required this.query,
    this.isAIViewer = false,
    this.currentUserId,
    this.refreshKey = 0,
    this.onFirstPostCardRectChanged,
    this.tutorialOverlayAncestorKey,
  });

  @override
  ConsumerState<_PostsList> createState() => _PostsListState();
}

class _PostsListState extends ConsumerState<_PostsList>
    with WidgetsBindingObserver {
  static const int _nativeAdInterval = 10;
  static const double _scrollToTopFabMinOffset = 120;
  static const double _fabShowThreshold = 24;
  static const double _fabHideThreshold = 72;

  List<PostModel> _posts = [];
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasError = false;
  bool _showScrollToTopFab = false;
  double _fabScrollAccumulator = 0;
  int _fabScrollDirection = 0;
  final GlobalKey _firstPostCardKey = GlobalKey();
  Rect? _lastReportedFirstPostRect;
  ProviderSubscription<TutorialPhase1Step>? _tutorialStepSubscription;
  ProviderSubscription<int>? _homeScrollTopSubscription;
  bool _isResolvingFirstPostRect = false;
  bool _pendingFirstPostRectRefresh = false;

  int _nativeAdCountForPosts(int postsCount) => postsCount ~/ _nativeAdInterval;

  bool _isNativeAdIndex(int displayIndex) {
    final slot = _nativeAdInterval + 1;
    return (displayIndex + 1) % slot == 0;
  }

  int _postIndexFromDisplayIndex(int displayIndex) {
    final adsBefore = (displayIndex + 1) ~/ (_nativeAdInterval + 1);
    return displayIndex - adsBefore;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPosts();
    _tutorialStepSubscription = ref.listenManual<TutorialPhase1Step>(
      tutorialPhase1Provider,
      (prev, next) => _onTutorialStepChanged(next),
      fireImmediately: true,
    );
    _homeScrollTopSubscription = ref.listenManual<int>(
      homeScrollToTopProvider,
      (_, unusedNext) => _scrollToTop(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tutorialStepSubscription?.close();
    _homeScrollTopSubscription?.close();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshFirstPostCardRectIfNeeded();
      }
    });
  }

  @override
  void didUpdateWidget(_PostsList oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.query != oldWidget.query ||
        widget.refreshKey != oldWidget.refreshKey) {
      _loadPosts();
    }
    if (widget.onFirstPostCardRectChanged == null &&
        oldWidget.onFirstPostCardRectChanged != null) {
      _lastReportedFirstPostRect = null;
    }
  }

  void _onTutorialStepChanged(TutorialPhase1Step step) {
    if (widget.onFirstPostCardRectChanged == null) return;
    final shouldReport = step == TutorialPhase1Step.homeLongPress;
    if (!shouldReport || _posts.isEmpty) {
      _clearFirstPostCardRect();
      return;
    }
    _resolveFirstPostCardRect();
  }

  void _resolveFirstPostCardRect() {
    if (_isResolvingFirstPostRect) {
      _pendingFirstPostRectRefresh = true;
      return;
    }
    _isResolvingFirstPostRect = true;
    _pendingFirstPostRectRefresh = false;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _isResolvingFirstPostRect = false;
        return;
      }
      final rect = await resolveRectWithRetry(
        _firstPostCardKey,
        ancestorKey: widget.tutorialOverlayAncestorKey,
      );
      _isResolvingFirstPostRect = false;
      if (!mounted) return;
      if (_lastReportedFirstPostRect != rect) {
        _lastReportedFirstPostRect = rect;
        widget.onFirstPostCardRectChanged!(rect);
      }
      // ペンディングがあれば再実行
      if (_pendingFirstPostRectRefresh && mounted) {
        _pendingFirstPostRectRefresh = false;
        _resolveFirstPostCardRect();
      }
    });
  }

  void _clearFirstPostCardRect() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_lastReportedFirstPostRect != null) {
        _lastReportedFirstPostRect = null;
        widget.onFirstPostCardRectChanged!(null);
      }
    });
  }

  void _refreshFirstPostCardRectIfNeeded() {
    final currentStep = ref.read(tutorialPhase1Provider);
    if (currentStep != TutorialPhase1Step.homeLongPress) return;
    if (_posts.isNotEmpty) {
      _resolveFirstPostCardRect();
    } else {
      _clearFirstPostCardRect();
    }
  }

  Future<void> _loadPosts({bool invalidateAvatarCache = false}) async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final snapshot = await widget.query
          .limit(AppConstants.postsPerPage)
          .get();
      var posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .where((post) => post.circleId == null || post.circleId!.isEmpty)
          .toList();


      if (!widget.isAIViewer) {
        posts = posts
            .where(
              (post) =>
                  post.postMode != 'ai' || post.userId == widget.currentUserId,
            )
            .toList();
      }

      if (invalidateAvatarCache) {
        final userIds = posts.map((post) => post.userId).toSet();
        for (final userId in userIds) {
          ref.invalidate(publicUserDocProvider(userId));
        }
      }

      setState(() {
        _posts = posts;
        _lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length == AppConstants.postsPerPage;
        _isLoading = false;
      });

      // 投稿読み込み完了後、チュートリアルが homeLongPress なら rect を再解決（空ならクリア）
      _refreshFirstPostCardRectIfNeeded();
    } catch (e) {
      debugPrint('Error loading posts: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }
  Future<void> _refreshPosts() => _loadPosts(invalidateAvatarCache: true);
  Future<void> _loadMorePosts() async {
    if (!_hasMore || _isLoadingMore || _lastDocument == null) return;

    setState(() => _isLoadingMore = true);

    try {
      final snapshot = await widget.query
          .limit(AppConstants.postsPerPage)
          .startAfterDocument(_lastDocument!)
          .get();

      var newPosts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .where((post) => post.circleId == null || post.circleId!.isEmpty)
          .toList();


      if (!widget.isAIViewer) {
        newPosts = newPosts
            .where(
              (post) =>
                  post.postMode != 'ai' || post.userId == widget.currentUserId,
            )
            .toList();
      }

      setState(() {
        _posts.addAll(newPosts);
        _lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length == AppConstants.postsPerPage;
        _isLoadingMore = false;
      });
    } catch (e) {
      debugPrint('Error loading more posts: $e');
      setState(() => _isLoadingMore = false);
    }
  }

  void _scrollToTop() {
    final controller = PrimaryScrollController.maybeOf(context);
    if (controller != null && controller.hasClients) {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    if (_showScrollToTopFab) {
      setState(() => _showScrollToTopFab = false);
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _fabScrollAccumulator = 0;
      _fabScrollDirection = 0;
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      final pixels = notification.metrics.pixels;

      if (pixels <= _scrollToTopFabMinOffset) {
        if (_showScrollToTopFab) {
          setState(() => _showScrollToTopFab = false);
        }
        _fabScrollAccumulator = 0;
        _fabScrollDirection = 0;
        return false;
      }

      if (delta > 0) {
        if (_fabScrollDirection != 1) {
          _fabScrollDirection = 1;
          _fabScrollAccumulator = 0;
        }
        _fabScrollAccumulator += delta.abs();
        if (!_showScrollToTopFab &&
            _fabScrollAccumulator >= _fabShowThreshold) {
          _fabScrollAccumulator = 0;
          setState(() => _showScrollToTopFab = true);
        }
      } else if (delta < 0) {
        if (_fabScrollDirection != -1) {
          _fabScrollDirection = -1;
          _fabScrollAccumulator = 0;
        }
        _fabScrollAccumulator += delta.abs();
        if (_showScrollToTopFab && _fabScrollAccumulator >= _fabHideThreshold) {
          _fabScrollAccumulator = 0;
          setState(() => _showScrollToTopFab = false);
        }
      }

      return false;
    }

    if (notification is ScrollEndNotification) {
      _fabScrollAccumulator = 0;
      _fabScrollDirection = 0;
      return false;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tutorialStep = ref.watch(tutorialPhase1Provider);
    final isTutorialHomeLongPress =
        tutorialStep == TutorialPhase1Step.homeLongPress;

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(AppMessages.home.timelineLoading),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('??', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(AppMessages.error.general, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadPosts,
              child: Text(AppMessages.label.retry),
            ),
          ],
        ),
      );
    }

    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshPosts,
        color: AppColors.primary,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
            const Text('??', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 16),
                  Text(
                    AppMessages.home.emptyPostsTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppMessages.home.emptyPostsDescription,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        InfiniteScrollListener(
          isLoadingMore: _isLoadingMore,
          hasMore: _hasMore,
          onLoadMore: _loadMorePosts,
          child: Builder(
            builder: (context) {
              final contentCount =
                  _posts.length + _nativeAdCountForPosts(_posts.length);
              final totalCount = contentCount + (_isLoadingMore ? 1 : 0);
              final list = NotificationListener<ScrollNotification>(
                onNotification: _handleScrollNotification,
                child: ListView.builder(
                  physics: isTutorialHomeLongPress
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  padding: const EdgeInsets.only(bottom: 120),
                  itemCount: totalCount,
                  itemBuilder: (context, index) {
                    if (_isLoadingMore && index == contentCount) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                      );
                    }

                    if (_isNativeAdIndex(index)) {
                      return NativeFeedAdCard(
                        key: ValueKey('native_ad_slot_$index'),
                      );
                    }

                    final postIndex = _postIndexFromDisplayIndex(index);
                    final post = _posts[postIndex];
                    final isTutorialTargetCard =
                        postIndex == 0 && isTutorialHomeLongPress;
                    final postCard = PostCard(
                      key: postIndex == 0
                          ? _firstPostCardKey
                          : ValueKey(post.id),
                      post: post,
                      longPressOnlyMode: isTutorialTargetCard,
                      onReactionOverlayClosed: isTutorialTargetCard
                          ? () {
                              final step = ref.read(tutorialPhase1Provider);
                              if (step == TutorialPhase1Step.homeLongPress) {
                                ref
                                    .read(tutorialPhase1Provider.notifier)
                                    .markHomeLongPressCompleted();
                              }
                            }
                          : null,
                      onDeleted: () {
                        setState(() {
                          _posts.removeAt(postIndex);
                        });
                        _refreshFirstPostCardRectIfNeeded();
                      },
                    );
                    if (isTutorialTargetCard) {
                      return NotificationListener<SizeChangedLayoutNotification>(
                        onNotification: (notification) {
                          _refreshFirstPostCardRectIfNeeded();
                          return true;
                        },
                        child: SizeChangedLayoutNotifier(
                          child: _LongPressProbe(
                            onLongPress: () {},
                            child: postCard,
                          ),
                        ),
                      );
                    }
                    return postCard;
                  },
                ),
              );

              if (isTutorialHomeLongPress) return list;

              return RefreshIndicator(
                onRefresh: _refreshPosts,
                color: AppColors.primary,
                child: list,
              );
            },
          ),
        ),
        Positioned(
          right: 24,
          bottom: MediaQuery.paddingOf(context).bottom + 28,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: _showScrollToTopFab ? Offset.zero : const Offset(0, 1.2),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _showScrollToTopFab ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_showScrollToTopFab,
                child: FloatingActionButton.small(
                  heroTag:
                      'home_scroll_top_fab_${widget.query.hashCode}_${widget.currentUserId ?? 'guest'}',
                  onPressed: _scrollToTop,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyFollowingState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('??', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              AppMessages.home.emptyFollowingTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppMessages.home.emptyFollowingDescription,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _LongPressProbe extends StatefulWidget {
  const _LongPressProbe({required this.child, required this.onLongPress});

  final Widget child;
  final VoidCallback onLongPress;

  @override
  State<_LongPressProbe> createState() => _LongPressProbeState();
}

class _LongPressProbeState extends State<_LongPressProbe> {
  static const _longPressDuration = Duration(milliseconds: 500);
  static const double _cancelDistance = 12;
  Timer? _timer;
  bool _fired = false;
  Offset? _startGlobalPosition;
  int? _activePointer;

  void _onPointerDown(PointerDownEvent event) {
    _fired = false;
    _activePointer = event.pointer;
    _startGlobalPosition = event.position;
    _timer?.cancel();
    _timer = Timer(_longPressDuration, () {
      if (!mounted || _fired) return;
      _fired = true;
      widget.onLongPress();
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_activePointer != event.pointer) return;
    final start = _startGlobalPosition;
    if (start == null) return;
    final movedDistance = (event.position - start).distance;
    if (movedDistance > _cancelDistance) {
      _onPointerEnd(event);
    }
  }

  void _onPointerEnd([PointerEvent? event]) {
    if (event != null && _activePointer != null && event.pointer != _activePointer) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _activePointer = null;
    _startGlobalPosition = null;
  }

  @override
  void dispose() {
    _onPointerEnd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: widget.child,
    );
  }
}

