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
import '../../../../shared/widgets/infinite_scroll_listener.dart';
import '../../../../shared/widgets/load_more_footer.dart';

/// サークル画面のスクロールトップを要求するProvider
final circleScrollToTopProvider = StateProvider<int>((ref) => 0);

/// サークル一覧画面
class CirclesScreen extends ConsumerStatefulWidget {
  const CirclesScreen({super.key});

  @override
  ConsumerState<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends ConsumerState<CirclesScreen> {
  int _selectedTab = 0; // 0: みんなの, 1: 参加中
  String _selectedCategory = CircleService.categories.first;
  final TextEditingController _searchController = TextEditingController();
  List<CircleModel> _searchResults = [];
  bool _isSearching = false;

  // プル更新・無限スクロール用の状態
  List<CircleModel> _circles = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  DocumentSnapshot? _lastDocument;
  final ScrollController _scrollController = ScrollController();
  bool _isScrollable = false;

  // 並び順・フィルター用の状態
  _SortOption _selectedSort = _SortOption.newest;
  final Set<_FilterOption> _selectedFilters = {};

  @override
  void initState() {
    super.initState();
    // ScrollControllerはスクロールトップ制御用のみ
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 画面が再表示されるたびにリロード（他の画面から戻ってきた時など）
    _loadCircles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
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
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) {
      // ログインしていない場合は何もしない（通常ありえない）
      return;
    }

    setState(() {
      _isLoading = _circles.isEmpty;
      _error = null;
      _hasMore = true;
      _lastDocument = null;
    });

    try {
      final circleService = ref.read(circleServiceProvider);
      final isAdmin = ref.read(isAdminProvider).valueOrNull ?? false;
      final result = await circleService.getPublicCirclesPaginated(
        category: _selectedCategory,
        userId: currentUser.uid,
        isAdmin: isAdmin,
        limit: 15,
      );
      setState(() {
        _circles = result.circles;
        _lastDocument = result.lastDoc;
        _hasMore = result.hasMore;
        _isLoading = false;
      });
      // レイアウト後にスクロール可能か再評価
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateScrollable();
      });
    } catch (e, stackTrace) {
      // デバッグ用：エラーの詳細をコンソールに出力
      debugPrint('CirclesScreen._loadCircles エラー: $e');
      debugPrint('スタックトレース: $stackTrace');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreCircles() async {
    if (_isLoadingMore || !_hasMore || _lastDocument == null) return;

    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) return;

    setState(() => _isLoadingMore = true);

    try {
      final circleService = ref.read(circleServiceProvider);
      final isAdmin = ref.read(isAdminProvider).valueOrNull ?? false;
      final result = await circleService.getPublicCirclesPaginated(
        category: _selectedCategory,
        userId: currentUser.uid,
        isAdmin: isAdmin,
        lastDocument: _lastDocument,
        limit: 15,
      );
      setState(() {
        _circles.addAll(result.circles);
        _lastDocument = result.lastDoc;
        _hasMore = result.hasMore;
        _isLoadingMore = false;
      });
      // レイアウト後にスクロール可能か再評価
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateScrollable();
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    setState(() => _isSearching = true);
    try {
      final circleService = ref.read(circleServiceProvider);
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      final results = await circleService.searchCircles(
        query,
        userId: currentUser?.uid ?? '',
      );
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      debugPrint('_performSearch エラー: $e');
      setState(() {
        _searchResults = [];
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

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final isAdminAsync = ref.watch(isAdminProvider);
    final isAdmin = isAdminAsync.valueOrNull ?? false;
    final isSearchMode =
        _searchController.text.isNotEmpty || _isSearching;

    // サークルボタンタップでスクロールトップを監視
    ref.listen<int>(circleScrollToTopProvider, (previous, next) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
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
          child: InfiniteScrollListener(
            isLoadingMore: !isSearchMode && _isLoadingMore,
            hasMore: !isSearchMode && _hasMore,
            onLoadMore: _loadMoreCircles,
            child: RefreshIndicator(
              onRefresh: _loadCircles,
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
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => _performSearch(value),
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
                                    _performSearch('');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                // タブセレクター（みんなの / 参加中）
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
                              _loadCircles();
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
                    ? _buildSearchResults()
                    : _buildCircleList(currentUser?.uid),

                // LoadMoreFooter（ショートリスト用手動フォールバック）
                SliverToBoxAdapter(
                  child: LoadMoreFooter(
                    hasMore: !isSearchMode && _hasMore,
                    isLoadingMore: !isSearchMode && _isLoadingMore,
                    isInitialLoadComplete: !_isLoading,
                    canLoadMore: _lastDocument != null,
                    isScrollable: _isScrollable,
                    onLoadMore: _loadMoreCircles,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
      // FABは中央ボタンで対応するため削除
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_searchResults.isEmpty) {
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
          (context, index) => _CircleCard(
            circle: _searchResults[index],
            onDeleted: _loadCircles,
          ),
          childCount: _searchResults.length,
        ),
      ),
    );
  }

  Widget _buildCircleList(String? userId) {
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
                onPressed: () => context.push('/create-circle'),
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

    // タブに応じてフィルタリング
    List<CircleModel> filteredCircles = _circles;
    if (_selectedTab == 1 && userId != null) {
      // 参加中タブ: 自分がメンバーのサークルのみ
      filteredCircles = _circles
          .where((c) => c.memberIds.contains(userId))
          .toList();
    }

    // フィルター適用
    if (_selectedFilters.contains(_FilterOption.hasSpace)) {
      filteredCircles = filteredCircles
          .where((c) => c.memberCount < c.maxMembers)
          .toList();
    }
    if (_selectedFilters.contains(_FilterOption.hasPosts)) {
      filteredCircles = filteredCircles.where((c) => c.postCount > 0).toList();
    }

    // 並び順適用
    switch (_selectedSort) {
      case _SortOption.newest:
        filteredCircles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _SortOption.active:
        filteredCircles.sort((a, b) {
          final aActivity = a.recentActivity ?? DateTime(1970);
          final bActivity = b.recentActivity ?? DateTime(1970);
          return bActivity.compareTo(aActivity);
        });
        break;
      case _SortOption.popular:
        filteredCircles.sort((a, b) => b.memberCount.compareTo(a.memberCount));
        break;
      case _SortOption.postCount:
        filteredCircles.sort((a, b) => b.postCount.compareTo(a.postCount));
        break;
      case _SortOption.humanPostOldest:
        // 人間投稿が古い順（ゴーストサークル発見用）
        filteredCircles.sort((a, b) {
          final aDate = a.lastHumanPostAt ?? DateTime(1970);
          final bDate = b.lastHumanPostAt ?? DateTime(1970);
          return aDate.compareTo(bDate); // 古い方が先
        });
        break;
    }

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
            return _hasMore
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                : const SizedBox.shrink();
          }
          return _CircleCard(
            circle: filteredCircles[index],
            currentUserId: userId,
            onDeleted: _loadCircles,
          );
        }, childCount: filteredCircles.length + (_hasMore ? 1 : 0)),
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
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

  String _filterLabel(_FilterOption option) {
    switch (option) {
      case _FilterOption.hasSpace:
        return AppMessages.circle.filterHasSpace;
      case _FilterOption.hasPosts:
        return AppMessages.circle.filterHasPosts;
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
        _loadCircles();
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

  /// フィルタードロップダウン
  Widget _buildFilterDropdown() {
    final hasActiveFilter = _selectedFilters.isNotEmpty;

    return PopupMenuButton<_FilterOption>(
      onSelected: (value) {
        setState(() {
          if (_selectedFilters.contains(value)) {
            _selectedFilters.remove(value);
          } else {
            _selectedFilters.add(value);
          }
        });
        _loadCircles();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: hasActiveFilter
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasActiveFilter ? AppColors.primary : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list,
              size: 14,
              color: hasActiveFilter ? AppColors.primary : Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              hasActiveFilter
                  ? AppMessages.circle.filterWithCount(_selectedFilters.length)
                  : AppMessages.circle.filterLabel,
              style: TextStyle(
                fontSize: 12,
                color: hasActiveFilter ? AppColors.primary : Colors.grey[700],
                fontWeight: hasActiveFilter ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: hasActiveFilter ? AppColors.primary : Colors.grey[600],
            ),
          ],
        ),
      ),
      itemBuilder: (context) => _FilterOption.values.map((option) {
        final isSelected = _selectedFilters.contains(option);
        return PopupMenuItem<_FilterOption>(
          value: option,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: isSelected ? AppColors.primary : Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Text(
                _filterLabel(option),
                style: TextStyle(
                  color: isSelected ? AppColors.primary : Colors.grey[800],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
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
    // timeagoの日本語設定
    timeago.setLocaleMessages('ja', timeago.JaMessages());

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
    // timeagoの日本語設定
    timeago.setLocaleMessages('ja', timeago.JaMessages());

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

/// フィルターオプション
enum _FilterOption {
  hasSpace(Icons.person_add),
  hasPosts(Icons.article);

  final IconData icon;
  const _FilterOption(this.icon);
}
