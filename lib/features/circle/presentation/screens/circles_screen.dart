import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/models/circle_model.dart';
import '../../../../shared/services/circle_service.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/circle_trial_provider.dart';
import '../../../../shared/providers/tutorial_phase5_provider.dart';
import '../../../../shared/widgets/infinite_scroll_listener.dart';
import '../../../../shared/widgets/tutorial_overlay.dart';

/// サークル画面のスクロールトップを要求するProvider
final circleScrollToTopProvider = StateProvider<int>((ref) => 0);

/// サークル一覧画面
class CirclesScreen extends ConsumerStatefulWidget {
  const CirclesScreen({super.key});

  @override
  ConsumerState<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends ConsumerState<CirclesScreen> {
  static const double _scrollToTopFabMinOffset = 120;
  static const double _fabShowThreshold = 24;
  static const double _fabHideThreshold = 72;
  int _selectedTab = 0; // 0: みんなの, 1: 参加中
  String _selectedCategory = CircleService.categories.first;
  final TextEditingController _searchController = TextEditingController();
  List<CircleModel> _searchResults = [];
  List<CircleModel> _privateOwnerResults = [];
  bool _isSearching = false;
  bool _searchHasMore = false;
  bool _isLoadingMoreSearch = false;
  Map<String, dynamic>? _searchCursor;
  Timer? _debounceTimer;
  int _searchGeneration = 0;

  // プル更新・無限スクロール用の状態
  int _loadGeneration = 0;
  List<CircleModel> _circles = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  DocumentSnapshot? _lastDocument;
  final ScrollController _scrollController = ScrollController();
  bool _isScrollable = false;
  bool _showScrollToTopFab = false;
  double _fabScrollAccumulator = 0;
  int _fabScrollDirection = 0; // 1: down, -1: up

  // callable browse用の状態
  Map<String, dynamic>? _browseCursor;

  // 並び順・フィルター用の状態
  _SortOption _selectedSort = _SortOption.newest;
  bool _filterHasSpace = false;
  bool _phase5Initialized = false;
  Timer? _filterDebounceTimer;
  bool _trialBannerDismissed = false;
  static const int _filterDebounceMs = 150;

  @override
  void initState() {
    super.initState();
    debugPrint('[CirclesScreen] initState called');
    _scrollController.addListener(_onScroll);
  }

  bool _initialLoadDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    debugPrint('[CirclesScreen] didChangeDependencies called (initialLoadDone=$_initialLoadDone)');
    // 初回のみロード（didChangeDependencies は MediaQuery 等の変更でも呼ばれるため）
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _loadCircles();
    } else {
      debugPrint('[CirclesScreen] didChangeDependencies SKIPPED (not first call)');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _filterDebounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // 検索モード中の無限スクロール
    if (_searchController.text.isNotEmpty &&
        _searchHasMore &&
        !_isLoadingMoreSearch &&
        _scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _loadMoreSearchResults();
    }
  }

  /// フィルターまたはソートがアクティブか
  bool get _isFilterOrSortActive =>
      _selectedSort != _SortOption.newest || _filterHasSpace;

  /// Callable browse経路を使うか（検索・フィルタ・ソートのいずれかがアクティブ）
  bool get _isBrowseMode =>
      _isFilterOrSortActive || _searchController.text.isNotEmpty;

  /// 現在の経路で次ページを取得可能か
  bool get _useCallable => _isBrowseMode || _selectedTab == 1;
  bool get _canLoadMore =>
      _hasMore &&
      (_useCallable ? _browseCursor != null : _lastDocument != null);

  String _sortOptionToString(_SortOption option) => switch (option) {
    _SortOption.newest => 'newest',
    _SortOption.active => 'active',
    _SortOption.popular => 'popular',
    _SortOption.postCount => 'postCount',
    _SortOption.humanPostOldest => 'humanPostOldest',
  };

  /// マージされたサークルリストを現在のソート順で再ソート
  /// タイブレーカーとしてdocumentId（circle.id）を使用
  void _sortMergedCircles(List<CircleModel> circles) {
    int Function(CircleModel, CircleModel) primaryCompare;
    switch (_selectedSort) {
      case _SortOption.newest:
        primaryCompare = (a, b) => b.createdAt.compareTo(a.createdAt);
      case _SortOption.active:
        primaryCompare = (a, b) => (b.recentActivity ?? DateTime(2000))
            .compareTo(a.recentActivity ?? DateTime(2000));
      case _SortOption.popular:
        primaryCompare = (a, b) => b.memberCount.compareTo(a.memberCount);
      case _SortOption.postCount:
        primaryCompare = (a, b) => b.postCount.compareTo(a.postCount);
      case _SortOption.humanPostOldest:
        primaryCompare = (a, b) => (a.lastHumanPostAt ?? DateTime(2099))
            .compareTo(b.lastHumanPostAt ?? DateTime(2099));
    }
    circles.sort((a, b) {
      final cmp = primaryCompare(a, b);
      return cmp != 0 ? cmp : a.id.compareTo(b.id);
    });
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

  Future<void> _loadCircles() async {
    debugPrint('[CirclesScreen] _loadCircles called (stack: ${StackTrace.current.toString().split('\n').take(5).join(' | ')})');
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) return;

    final generation = ++_loadGeneration;

    setState(() {
      _isLoading = _circles.isEmpty;
      _isLoadingMore = false;
      _error = null;
      _hasMore = true;
      _lastDocument = null;
      _browseCursor = null;
      _privateOwnerResults = [];
    });

    try {
      final circleService = ref.read(circleServiceProvider);

      if (_isBrowseMode || _selectedTab == 1) {
        // フィルター/ソート/検索がアクティブ、または参加中タブ → callable経由
        final result = await circleService.searchCircles(
          _searchController.text.isNotEmpty ? _searchController.text : null,
          userId: currentUser.uid,
          category: _selectedCategory,
          sortBy: _sortOptionToString(_selectedSort),
          hasSpace: _filterHasSpace ? true : null,
          joinedOnly: _selectedTab == 1,
        );
        if (generation != _loadGeneration) return; // 古いリクエストを破棄
        setState(() {
          // privateOwnerCircles（非公開サークル）をマージしてデデュプ・ソート順維持
          final publicIds = result.circles.map((c) => c.id).toSet();
          final merged = [
            ...result.circles,
            ...result.privateOwnerCircles.where((c) => !publicIds.contains(c.id)),
          ];
          // サーバーのソート順を再現（privateOwnerは分離されるため末尾に来る）
          _sortMergedCircles(merged);
          _circles = merged;
          _privateOwnerResults = result.privateOwnerCircles;
          _browseCursor = result.nextCursor;
          _hasMore = result.hasMore;
          _isLoading = false;
        });
        // 参加中200件上限で切り詰められた場合に通知
        if (result.joinedTruncated && mounted) {
          SnackBarHelper.showInfo(
            context,
            AppMessages.circle.searchJoinedTruncated,
          );
        }
      } else {
        // デフォルト表示 → Firestore直接クエリ（高速）
        final isAdmin = ref.read(isAdminProvider).valueOrNull ?? false;
        final result = await circleService.getPublicCirclesPaginated(
          category: _selectedCategory,
          userId: currentUser.uid,
          isAdmin: isAdmin,
          limit: 15,
        );
        if (generation != _loadGeneration) return; // 古いリクエストを破棄
        setState(() {
          _circles = result.circles;
          _lastDocument = result.lastDoc;
          _hasMore = result.hasMore;
          _isLoading = false;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateScrollable();
      });
    } catch (e, stackTrace) {
      debugPrint('CirclesScreen._loadCircles エラー: $e');
      debugPrint('スタックトレース: $stackTrace');
      if (generation != _loadGeneration) return; // 古いリクエストの失敗を無視
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreCircles() async {
    if (_isLoadingMore || !_hasMore) {
      debugPrint('[CirclesScreen] _loadMoreCircles SKIPPED (isLoadingMore=$_isLoadingMore, hasMore=$_hasMore)');
      return;
    }

    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) return;

    if (_useCallable) {
      // callable mode（browse + 参加中タブ）
      if (_browseCursor == null) {
        debugPrint('[CirclesScreen] _loadMoreCircles SKIPPED (browseCursor is null)');
        return;
      }
    } else {
      // Firestore直接
      if (_lastDocument == null) {
        debugPrint('[CirclesScreen] _loadMoreCircles SKIPPED (lastDocument is null)');
        return;
      }
    }
    debugPrint('[CirclesScreen] _loadMoreCircles EXECUTING (circles=${_circles.length})');

    final generation = _loadGeneration;
    setState(() => _isLoadingMore = true);

    try {
      final circleService = ref.read(circleServiceProvider);

      if (_isBrowseMode || _selectedTab == 1) {
        final result = await circleService.searchCircles(
          _searchController.text.isNotEmpty ? _searchController.text : null,
          userId: currentUser.uid,
          category: _selectedCategory,
          cursor: _browseCursor,
          sortBy: _sortOptionToString(_selectedSort),
          hasSpace: _filterHasSpace ? true : null,
          joinedOnly: _selectedTab == 1,
        );
        if (generation != _loadGeneration) return; // 古いリクエストを破棄
        setState(() {
          final existingIds = _circles.map((c) => c.id).toSet();
          final newCircles = [...result.circles, ...result.privateOwnerCircles]
              .where((c) => !existingIds.contains(c.id));
          _circles.addAll(newCircles);
          _sortMergedCircles(_circles);
          _browseCursor = result.nextCursor;
          _hasMore = result.hasMore;
          _isLoadingMore = false;
        });
      } else {
        final isAdmin = ref.read(isAdminProvider).valueOrNull ?? false;
        final result = await circleService.getPublicCirclesPaginated(
          category: _selectedCategory,
          userId: currentUser.uid,
          isAdmin: isAdmin,
          lastDocument: _lastDocument,
          limit: 15,
        );
        if (generation != _loadGeneration) return; // 古いリクエストを破棄
        setState(() {
          _circles.addAll(result.circles);
          _lastDocument = result.lastDoc;
          _hasMore = result.hasMore;
          _isLoadingMore = false;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateScrollable();
      });
    } catch (e) {
      if (generation != _loadGeneration) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _searchGeneration++; // 進行中リクエストを失効させる
    if (value.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
        _privateOwnerResults = [];
        _searchHasMore = false;
        _searchCursor = null;
        _isLoadingMoreSearch = false;
      });
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(value);
    });
  }

  Future<void> _performSearch(String query) async {
    _searchGeneration++;
    final generation = _searchGeneration;

    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
        _privateOwnerResults = [];
        _searchHasMore = false;
        _searchCursor = null;
      });
      return;
    }

    setState(() => _isSearching = true);
    try {
      final circleService = ref.read(circleServiceProvider);
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      final result = await circleService.searchCircles(
        query,
        userId: currentUser?.uid ?? '',
        category: _selectedCategory,
        joinedOnly: _selectedTab == 1,
        sortBy: _sortOptionToString(_selectedSort),
        hasSpace: _filterHasSpace ? true : null,
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = result.circles;
        _privateOwnerResults = result.privateOwnerCircles;
        _searchHasMore = result.hasMore;
        _searchCursor = result.nextCursor;
        _isSearching = false;
      });
      if (result.joinedTruncated && mounted) {
        SnackBarHelper.showInfo(
          context,
          AppMessages.circle.searchJoinedTruncated,
        );
      }
    } catch (e) {
      debugPrint('_performSearch エラー: $e');
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchResults = [];
        _privateOwnerResults = [];
        _searchHasMore = false;
        _searchCursor = null;
        _isSearching = false;
      });
      if (mounted) {
        SnackBarHelper.showError(
          context,
          AppMessages.circle.searchError,
        );
      }
    }
  }

  Future<void> _loadMoreSearchResults() async {
    if (_isLoadingMoreSearch || !_searchHasMore || _searchCursor == null) return;

    final generation = _searchGeneration;
    setState(() => _isLoadingMoreSearch = true);
    try {
      final circleService = ref.read(circleServiceProvider);
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      final result = await circleService.searchCircles(
        _searchController.text,
        userId: currentUser?.uid ?? '',
        category: _selectedCategory,
        joinedOnly: _selectedTab == 1,
        cursor: _searchCursor,
        sortBy: _sortOptionToString(_selectedSort),
        hasSpace: _filterHasSpace ? true : null,
      );
      if (!mounted) return;
      if (generation != _searchGeneration) {
        setState(() => _isLoadingMoreSearch = false);
        return;
      }
      setState(() {
        _searchResults.addAll(result.circles);
        _searchHasMore = result.hasMore;
        _searchCursor = result.nextCursor;
        _isLoadingMoreSearch = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMoreSearch = false);
    }
  }

  void _scrollToTop() {
    debugPrint('[CirclesScreen] _scrollToTop called (stack: ${StackTrace.current.toString().split('\n').take(3).join(' | ')})');
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
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

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final isAdminAsync = ref.watch(isAdminProvider);
    final isAdmin = isAdminAsync.valueOrNull ?? false;
    final isCircleTrialSession = ref.watch(circleTrialSessionProvider);
    // サブスク/トライアルが無効になったら参加中タブをリセット
    final canShowJoinedTab = (currentUser?.isSubscriber ?? false) || isCircleTrialSession;
    if (!canShowJoinedTab && _selectedTab == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedTab == 1) {
          setState(() => _selectedTab = 0);
          _loadCircles();
        }
      });
    }
    final isSearchMode =
        _searchController.text.isNotEmpty || _isSearching;
    final tutorialPhase5Step = ref.watch(tutorialPhase5Provider);

    if (currentUser != null && !_phase5Initialized) {
      _phase5Initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(tutorialPhase5Provider.notifier).restoreOrStart(currentUser);
      });
    }

    // サークルボタンタップでスクロールトップを監視
    ref.listen<int>(circleScrollToTopProvider, (previous, next) {
      _scrollToTop();
    });

    // ユーザーのヘッダー色を取得（設定されていればその色、なければデフォルト）
    final primaryColor = currentUser?.headerPrimaryColor != null
        ? Color(currentUser!.headerPrimaryColor!)
        : AppColors.primary;
    final secondaryColor = currentUser?.headerSecondaryColor != null
        ? Color(currentUser!.headerSecondaryColor!)
        : AppColors.secondary;

    // ユーザーの色でグラデーションを作成（パステルカラー）
    final userGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        primaryColor.withValues(alpha: 0.25),
        secondaryColor.withValues(alpha: 0.15),
        const Color(0xFFFDF8F3), // warmGradientの上部色
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: userGradient),
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              InfiniteScrollListener(
                isLoadingMore: !isSearchMode && _isLoadingMore,
                hasMore: !isSearchMode && _hasMore,
                onLoadMore: _loadMoreCircles,
                child: RefreshIndicator(
                  onRefresh: _loadCircles,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        // ヘッダー（シンプルに「サークル」のみ中央表示）
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                            child: Center(
                              child: Text(
                                AppMessages.circle.listTitle,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),

                        // 検索バー
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: TextField(
                                controller: _searchController,
                                onChanged: _onSearchChanged,
                                decoration: InputDecoration(
                                  hintText: AppMessages.circle.searchHint,
                                  hintStyle: TextStyle(color: Colors.grey[400]),
                                  prefixIcon: Icon(
                                    Icons.search,
                                    color: Colors.grey[400],
                                  ),
                                  suffixIcon: _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close, size: 20),
                                          onPressed: () {
                                            _searchController.clear();
                                            _onSearchChanged('');
                                          },
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                            ),
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 16)),

                        // タブセレクター（みんなの / 参加中）
                        // サブスクまたはトライアル中のみ表示（非サブスクには参加サークルが無い）
                        if (canShowJoinedTab)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                _buildTabButton(AppMessages.circle.tabAll, 0),
                                const SizedBox(width: 12),
                                _buildTabButton(AppMessages.circle.tabJoined, 1),
                              ],
                            ),
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 12)),

                        // 並び順・フィルター選択
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                // 並び順ドロップダウン
                                _buildSortDropdown(isAdmin),
                                const SizedBox(width: 8),
                                // フィルタードロップダウン
                                _buildFilterDropdown(),
                              ],
                            ),
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 8)),

                        // カテゴリチップ
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 40,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: CircleService.categories.length,
                              itemBuilder: (context, index) {
                                final category = CircleService.categories[index];
                                final isSelected = category == _selectedCategory;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: Text(category),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setState(() => _selectedCategory = category);
                                      _debounceTimer?.cancel();
                                      _filterDebounceTimer?.cancel();
                                      _filterDebounceTimer = Timer(
                                        const Duration(milliseconds: _filterDebounceMs),
                                        () {
                                          if (_searchController.text.isNotEmpty) {
                                            _performSearch(_searchController.text);
                                          } else {
                                            _loadCircles();
                                          }
                                        },
                                      );
                                    },
                                    selectedColor: AppColors.primary.withValues(
                                      alpha: 0.2,
                                    ),
                                    checkmarkColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? AppColors.primary
                                          : Colors.grey[700],
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    backgroundColor: Colors.white,
                                    side: BorderSide(
                                      color: isSelected
                                          ? AppColors.primary
                                          : Colors.grey[300]!,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 16)),

                        // サークルリスト
                        _searchController.text.isNotEmpty
                            ? _buildSearchResults(currentUser?.uid)
                            : _buildCircleList(
                                currentUser?.uid,
                                currentUser?.isSubscriber ?? false,
                              ),

                      ],
                    ),
                  ),
                ),
              ),
              if (isCircleTrialSession && !(currentUser?.isSubscriber ?? false) && !_trialBannerDismissed)
                Positioned(
                  top: 8,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.only(
                      left: 12,
                      top: 10,
                      bottom: 10,
                      right: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.visibility_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${AppMessages.circle.trialBannerTitle}  ${AppMessages.circle.trialBannerDescription}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _trialBannerDismissed = true),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                right: 24,
                bottom: MediaQuery.paddingOf(context).bottom + 28,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  offset: _showScrollToTopFab
                      ? Offset.zero
                      : const Offset(0, 1.2),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _showScrollToTopFab ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !_showScrollToTopFab,
                      child: FloatingActionButton.small(
                        heroTag: 'circles_scroll_top_fab',
                        onPressed: _scrollToTop,
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        child: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                    ),
                  ),
                ),
              ),
              if (tutorialPhase5Step == TutorialPhase5Step.circleOverview)
                Positioned.fill(
                  child: TutorialOverlay(
                    message: AppMessages.tutorial.circleOverviewGuide,
                    onMaskTap: () =>
                        ref.read(tutorialPhase5Provider.notifier).advance(),
                    characterAssetPath: 'assets/onbord/onbord_01.png',
                    bubbleBottomOffset:
                        MediaQuery.of(context).padding.bottom + 96,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<CircleModel> get _allSearchResults => [
        ..._privateOwnerResults,
        ..._searchResults,
      ];

  Widget _buildSearchResults(String? userId) {
    if (_isSearching && _searchResults.isEmpty) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final allResults = _allSearchResults;

    if (allResults.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                AppMessages.circle.searchNotFound,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    // キーボード表示時はボトムパディングを減らす
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final bottomPadding = keyboardVisible ? 16.0 : 100.0;

    return SliverPadding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index < allResults.length) {
              return _CircleCard(
                circle: allResults[index],
                currentUserId: userId,
                onDeleted: _loadCircles,
              );
            }
            // 追加読み込みインジケーター（ロード中のみ表示）
            if (_isLoadingMoreSearch) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return const SizedBox.shrink();
          },
          childCount: allResults.length + (_searchHasMore ? 1 : 0),
        ),
      ),
    );
  }

  Widget _buildCircleList(String? userId, bool isSubscriber) {
    // ローディング中
    if (_isLoading) {
      return const SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    // エラー発生時
    if (_error != null) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                AppMessages.circle.listError,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    // データなし
    if (_circles.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: const Text('??', style: TextStyle(fontSize: 48)),
              ),
              const SizedBox(height: 24),
              Text(
                AppMessages.circle.emptyTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                AppMessages.circle.emptyDescription,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: isSubscriber
                    ? () => context.push('/create-circle')
                    : () {
                        SnackBarHelper.showError(
                          context,
                          AppMessages.profile.circleSubscriptionMessage,
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: Text(AppMessages.circle.createCircle),
              ),
            ],
          ),
        ),
      );
    }

    // キーボード表示時はボトムパディングを減らす
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final bottomPadding = keyboardVisible ? 16.0 : 100.0;

    // callable使用時はサーバー側でフィルター/ソート済み
    List<CircleModel> filteredCircles;
    filteredCircles = _circles;

    if (filteredCircles.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group_off, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                _selectedTab == 1
                    ? AppMessages.circle.emptyJoined
                    : AppMessages.circle.emptyGeneric,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          // 最後の項目の場合、ローディングインジケーターを表示
          if (index == filteredCircles.length) {
            if (_isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              );
            }
            if (_canLoadMore && !_isScrollable) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: TextButton(
                    onPressed: _loadMoreCircles,
                    child: Text(AppMessages.circle.loadMoreButton),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }
          return _CircleCard(
            circle: filteredCircles[index],
            currentUserId: userId,
            onDeleted: _loadCircles,
          );
        }, childCount: filteredCircles.length + ((_isLoadingMore || (_canLoadMore && !_isScrollable)) ? 1 : 0)),
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        if (_selectedTab == index) return;
        setState(() {
          _selectedTab = index;
          _circles = [];
        });
        _debounceTimer?.cancel();
        if (_searchController.text.isNotEmpty) {
          _performSearch(_searchController.text);
        } else {
          _loadCircles();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey[300]!,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              index == 0 ? Icons.public : Icons.group,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey[600],
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(_SortOption option) {
    switch (option) {
      case _SortOption.newest:
        return AppMessages.circle.sortNewest;
      case _SortOption.active:
        return AppMessages.circle.sortActive;
      case _SortOption.popular:
        return AppMessages.circle.sortPopular;
      case _SortOption.postCount:
        return AppMessages.circle.sortPostCount;
      case _SortOption.humanPostOldest:
        return AppMessages.circle.sortHumanPostOldest;
    }
  }

  /// 並び順ドロップダウン
  Widget _buildSortDropdown(bool isAdmin) {
    // 管理者のみhumanPostOldestを表示
    final options = isAdmin
        ? _SortOption.values
        : _SortOption.values
              .where((o) => o != _SortOption.humanPostOldest)
              .toList();

    return PopupMenuButton<_SortOption>(
      initialValue: _selectedSort,
      onSelected: (value) {
        setState(() => _selectedSort = value);
        _filterDebounceTimer?.cancel();
        _filterDebounceTimer = Timer(
          const Duration(milliseconds: _filterDebounceMs),
          () {
            if (_searchController.text.isNotEmpty) {
              _performSearch(_searchController.text);
            } else {
              _loadCircles();
            }
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_selectedSort.icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              _sortLabel(_selectedSort),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey[600]),
          ],
        ),
      ),
      itemBuilder: (context) => options.map((option) {
        return PopupMenuItem<_SortOption>(
          value: option,
          child: Row(
            children: [
              Icon(
                option.icon,
                size: 18,
                color: _selectedSort == option
                    ? AppColors.primary
                    : Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Text(
                _sortLabel(option),
                style: TextStyle(
                  color: _selectedSort == option
                      ? AppColors.primary
                      : Colors.grey[800],
                  fontWeight: _selectedSort == option
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              if (_selectedSort == option) ...[
                const Spacer(),
                Icon(Icons.check, size: 18, color: AppColors.primary),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 「空きあり」トグルボタン
  Widget _buildFilterDropdown() {
    return InkWell(
      onTap: () {
        setState(() {
          _filterHasSpace = !_filterHasSpace;
        });
        _filterDebounceTimer?.cancel();
        _filterDebounceTimer = Timer(
          const Duration(milliseconds: _filterDebounceMs),
          () {
            if (_searchController.text.isNotEmpty) {
              _performSearch(_searchController.text);
            } else {
              _loadCircles();
            }
          },
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _filterHasSpace
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _filterHasSpace ? AppColors.primary : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_add,
              size: 14,
              color: _filterHasSpace ? AppColors.primary : Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              AppMessages.circle.filterHasSpace,
              style: TextStyle(
                fontSize: 12,
                color: _filterHasSpace ? AppColors.primary : Colors.grey[700],
                fontWeight: _filterHasSpace ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// サークルカード
class _CircleCard extends ConsumerWidget {
  final CircleModel circle;
  final String? currentUserId;
  final VoidCallback? onDeleted;

  const _CircleCard({required this.circle, this.currentUserId, this.onDeleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // CircleServiceのカテゴリアイコンを使用
    final icon = CircleService.categoryIcons[circle.category] ?? '?';
    final isOwner = currentUserId != null && circle.ownerId == currentUserId;
    final isSubOwner =
        currentUserId != null && circle.subOwnerId == currentUserId;
    // 管理者チェック
    final isAdminAsync = ref.watch(isAdminProvider);
    final isAdmin = isAdminAsync.valueOrNull ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final result = await context.push<bool>('/circle/${circle.id}');
            // サークル削除後にリロードが必要な場合
            if (result == true && context.mounted) {
              // 親Stateに通知するためにコールバックを呼ぶ
              onDeleted?.call();
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // アイコン（オーナーの場合は申請バッジ付き）
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary.withValues(alpha: 0.1),
                            AppColors.primaryLight.withValues(alpha: 0.3),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: circle.iconImageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                circle.iconImageUrl!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Center(
                              child: Text(
                                icon,
                                style: const TextStyle(fontSize: 28),
                              ),
                            ),
                    ),
                    // オーナー、副オーナー、または管理者の場合は申請バッジを表示
                    if (isOwner || isSubOwner || isAdmin)
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: ref
                            .watch(circleServiceProvider)
                            .streamJoinRequests(circle.id),
                        builder: (context, snapshot) {
                          final count = snapshot.data?.length ?? 0;
                          if (count == 0) return const SizedBox.shrink();
                          return Positioned(
                            top: -4,
                            right: -4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 20,
                                minHeight: 20,
                              ),
                              child: Text(
                                count > 9 ? '9+' : count.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(width: 16),

                // 情報
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // オーナーバッジ
                          if (currentUserId != null &&
                              circle.ownerId == currentUserId)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.workspace_premium,
                                size: 14,
                                color: Colors.amber,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              circle.name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        circle.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _buildInfoChip(
                            Icons.people_outline,
                            AppMessages.circle.memberCountLabel(
                              circle.memberCount,
                            ),
                          ),
                          _buildInfoChip(
                            Icons.article_outlined,
                            AppMessages.circle.postCountLabel(
                              circle.postCount,
                            ),
                          ),
                          // 最終アクティビティ表示
                          _buildActivityChip(circle.recentActivity),
                          // 管理者向け：人間の最終投稿日時（フィールドから直接取得）
                          if (isAdmin)
                            _buildHumanActivityChip(circle.lastHumanPostAt),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              circle.category,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          // AIモードバッジ
                          if (circle.aiMode == CircleAIMode.aiOnly)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.smart_toy_outlined,
                                    size: 10,
                                    color: Colors.purple[700],
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    AppMessages.circle.aiModeLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.purple[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // 招待制バッジ（非公開かつAIモードではない場合）
                          if (!circle.isPublic &&
                              circle.aiMode != CircleAIMode.aiOnly)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_outline,
                                    size: 10,
                                    color: Colors.orange[700],
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    AppMessages.circle.inviteOnlyLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildActivityChip(DateTime? recentActivity) {
    if (recentActivity == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 14, color: Colors.grey[400]),
          const SizedBox(width: 4),
          Text(
            AppMessages.circle.noPostsYet,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      );
    }

    final now = DateTime.now();
    final difference = now.difference(recentActivity);

    // 7日以内ならアクティブ表示（緑）、それ以外はグレー
    final isActive = difference.inDays <= 7;
    final color = isActive ? Colors.green : Colors.grey[500];
    final icon = isActive ? Icons.local_fire_department : Icons.schedule;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          AppMessages.circle.postedAt(
            timeago.format(recentActivity, locale: 'ja'),
          ),
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  /// 管理者向け：人間ユーザーの最終投稿日時チップ
  Widget _buildHumanActivityChip(DateTime? lastHumanPostDate) {
    if (lastHumanPostDate == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off, size: 12, color: Colors.blue[400]),
            const SizedBox(width: 3),
            Text(
              AppMessages.circle.humanPostsNone,
              style: TextStyle(
                fontSize: 10,
                color: Colors.blue[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final difference = now.difference(lastHumanPostDate);

    // 7日以内なら緑背景、それ以外は青背景（警告として）
    final isActive = difference.inDays <= 7;
    final bgColor = isActive
        ? Colors.green.withValues(alpha: 0.1)
        : Colors.blue.withValues(alpha: 0.15);
    final borderColor = isActive
        ? Colors.green.withValues(alpha: 0.3)
        : Colors.blue.withValues(alpha: 0.4);
    final textColor = isActive ? Colors.green[700] : Colors.blue[700];
    final iconColor = isActive ? Colors.green[600] : Colors.blue[600];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person, size: 12, color: iconColor),
          const SizedBox(width: 3),
          Text(
            AppMessages.circle.humanPostAt(
              timeago.format(lastHumanPostDate, locale: 'ja'),
            ),
            style: TextStyle(
              fontSize: 10,
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 並び順オプション
enum _SortOption {
  newest(Icons.schedule),
  active(Icons.local_fire_department),
  popular(Icons.people),
  postCount(Icons.article),
  humanPostOldest(Icons.person_off); // 管理者のみ

  final IconData icon;
  const _SortOption(this.icon);
}

