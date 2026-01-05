import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/circle_model.dart';
import '../../../../shared/services/circle_service.dart';
import '../../../../shared/providers/auth_provider.dart';

/// サークル一覧画面
class CirclesScreen extends ConsumerStatefulWidget {
  const CirclesScreen({super.key});

  @override
  ConsumerState<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends ConsumerState<CirclesScreen> {
  int _selectedTab = 0; // 0: みんなの, 1: 参加中
  String _selectedCategory = '全て';
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

  @override
  void initState() {
    super.initState();
    // 無限スクロール用のリスナー
    _scrollController.addListener(_onScroll);
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

  void _onScroll() {
    // 下端から200px手前でロードを開始
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreCircles();
    }
  }

  Future<void> _loadCircles() async {
    setState(() {
      _isLoading = _circles.isEmpty;
      _error = null;
      _hasMore = true;
      _lastDocument = null;
    });

    try {
      final circleService = ref.read(circleServiceProvider);
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      final result = await circleService.getPublicCirclesPaginated(
        category: _selectedCategory,
        userId: currentUser?.uid,
        limit: 15,
      );
      setState(() {
        _circles = result.circles;
        _lastDocument = result.lastDoc;
        _hasMore = result.hasMore;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreCircles() async {
    if (_isLoadingMore || !_hasMore || _lastDocument == null) return;

    setState(() => _isLoadingMore = true);

    try {
      final circleService = ref.read(circleServiceProvider);
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      final result = await circleService.getPublicCirclesPaginated(
        category: _selectedCategory,
        userId: currentUser?.uid,
        lastDocument: _lastDocument,
        limit: 15,
      );
      setState(() {
        _circles.addAll(result.circles);
        _lastDocument = result.lastDoc;
        _hasMore = result.hasMore;
        _isLoadingMore = false;
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
    final circleService = ref.read(circleServiceProvider);
    final results = await circleService.searchCircles(query);
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadCircles,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              // ヘッダー（シアングラデーション）
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFE0F7FA), // シアン極淡
                        Color(0xFFB2EBF2), // シアン淡
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'サークル',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF00838F), // シアン濃
                                ),
                          ),
                          const SizedBox(width: 8),
                          const Text('👥', style: TextStyle(fontSize: 28)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '同じ目標を持つ仲間と繋がろう！',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF00838F).withValues(alpha: 0.7),
                        ),
                      ),
                    ],
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
                        hintText: 'サークルを検索',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
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
                      _buildTabButton('みんなの', 0),
                      const SizedBox(width: 12),
                      _buildTabButton('参加中', 1),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

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
            ],
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
              Text('見つかりませんでした', style: TextStyle(color: Colors.grey[600])),
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
              Text('エラーが発生しました', style: TextStyle(color: Colors.grey[600])),
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
                child: const Text('🌱', style: TextStyle(fontSize: 48)),
              ),
              const SizedBox(height: 24),
              Text(
                'まだサークルがないよ',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '最初のサークルを作ってみよう！',
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
                label: const Text('サークルを作る'),
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
                _selectedTab == 1 ? '参加中のサークルがありません' : 'サークルがありません',
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
    final icon = CircleService.categoryIcons[circle.category] ?? '⭐';
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
                            '${circle.memberCount}人',
                          ),
                          _buildInfoChip(
                            Icons.article_outlined,
                            '${circle.postCount}件',
                          ),
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
                          // 招待制バッジ
                          if (!circle.isPublic)
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
                                    '招待制',
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
}
