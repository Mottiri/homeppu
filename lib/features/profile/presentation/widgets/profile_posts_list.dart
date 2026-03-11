import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/post_model.dart';
import 'profile_post_card.dart';

/// ユーザーの投稿一覧（プル更新方式）
class ProfilePostsList extends StatefulWidget {
  final String userId;
  final bool isMyProfile;
  final bool viewerIsAI;
  final Color accentColor;

  /// 親から渡されるコールバック: ロード完了時に呼び出し
  final VoidCallback? onLoadComplete;
  final Key? favoritesTabKey;
  final Key? tabsContainerKey;

  const ProfilePostsList({
    super.key,
    required this.userId,
    this.isMyProfile = false,
    this.viewerIsAI = false,
    this.accentColor = AppColors.primary,
    this.onLoadComplete,
    this.favoritesTabKey,
    this.tabsContainerKey,
  });

  @override
  State<ProfilePostsList> createState() => ProfilePostsListState();
}

/// ProfilePostsListの状態クラス（GlobalKey参照用にpublic）
class ProfilePostsListState extends State<ProfilePostsList>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // TL/サークル用：全投稿を一括管理（最初30件 + 追加読み込み分）
  List<PostModel> _posts = [];
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  // お気に入り用：別途Firestoreから直接クエリ
  List<PostModel> _favoritePosts = [];
  DocumentSnapshot? _favoriteLastDocument;
  bool _favoriteHasMore = true;
  bool _favoriteIsLoading = false;
  bool _favoriteIsLoadingMore = false;

  // 初期読み込み件数
  static const int _initialLoadCount = 30;
  static const int _loadMoreCount = 10;

  int get _currentTab => _tabController.index;

  // タブごとにフィルタリング
  List<PostModel> get _tlPosts =>
      _posts.where((p) => p.circleId == null).toList();
  List<PostModel> get _circlePosts =>
      _posts.where((p) => p.circleId != null).toList();

  List<PostModel> get _currentPosts {
    switch (_currentTab) {
      case 0:
        return _tlPosts;
      case 1:
        return _circlePosts;
      case 2:
        return _favoritePosts;
      default:
        return _tlPosts;
    }
  }

  /// 親から参照可能: 現在追加読み込み中か
  bool get isLoadingMore =>
      _currentTab == 2 ? _favoriteIsLoadingMore : _isLoadingMore;

  /// 親から参照可能: 追加データあるか
  bool get hasMore => _currentTab == 2 ? _favoriteHasMore : _hasMore;

  /// 親から参照可能: 初回ロード完了しており追加読み込み可能か
  bool get canLoadMore =>
      _currentTab == 2 ? _favoriteLastDocument != null : _lastDocument != null;

  /// 親から呼び出されるメソッド：追加読み込み
  void loadMoreCurrentTab() {
    if (_currentTab == 2) {
      // お気に入りタブ
      if (_favoriteHasMore && !_favoriteIsLoadingMore) {
        _loadMoreFavorites();
      }
    } else {
      // TL/サークルタブ
      if (_hasMore && !_isLoadingMore) {
        _loadMorePosts();
      }
    }
  }

  /// 親から参照可能: タブを選択
  void selectTab(int index) {
    if (index < 0 || index >= _tabController.length) return;
    _tabController.animateTo(index);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadPosts();
    _loadFavorites(); // お気に入りも並行読み込み
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final tabIndex = _tabController.index;

      if (tabIndex == 2) {
        // お気に入りタブ：まだ読み込んでいなければ読み込み
        if (_favoritePosts.isEmpty && !_favoriteIsLoading) {
          _loadFavorites();
        }
      } else {
        // TL/サークルタブ：30件を超えた分を破棄
        if (_posts.length > _initialLoadCount) {
          setState(() {
            _posts = _posts.take(_initialLoadCount).toList();
            _hasMore = true;
          });
        }
      }
      // タブ切替後に親へ通知
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onLoadComplete?.call();
      });
      setState(() {});
    }
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('userId', isEqualTo: widget.userId)
          .orderBy('createdAt', descending: true)
          .limit(_initialLoadCount)
          .get();

      var posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      // AIモードのフィルタリング
      if (!widget.isMyProfile && !widget.viewerIsAI) {
        posts = posts.where((post) => post.postMode != 'ai').toList();
      }

      if (mounted) {
        setState(() {
          _posts = posts;
          _lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
          _hasMore = snapshot.docs.length == _initialLoadCount;
          _isLoading = false;
        });
        // ロード完了を親へ通知
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onLoadComplete?.call();
        });
      }
    } catch (e) {
      debugPrint('Error loading posts: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMorePosts() async {
    if (!_hasMore || _isLoadingMore || _lastDocument == null) {
      return;
    }

    setState(() => _isLoadingMore = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('userId', isEqualTo: widget.userId)
          .orderBy('createdAt', descending: true)
          .limit(_loadMoreCount)
          .startAfterDocument(_lastDocument!)
          .get();

      var newPosts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      // AIモードのフィルタリング
      if (!widget.isMyProfile && !widget.viewerIsAI) {
        newPosts = newPosts.where((post) => post.postMode != 'ai').toList();
      }

      if (mounted) {
        setState(() {
          _posts.addAll(newPosts);
          _lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
          _hasMore = snapshot.docs.length == _loadMoreCount;
          _isLoadingMore = false;
        });
        // ロード完了を親へ通知
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onLoadComplete?.call();
        });
      }
    } catch (e) {
      debugPrint('Error loading more posts: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  /// お気に入り投稿の読み込み（Firestoreから直接クエリ）
  Future<void> _loadFavorites() async {
    setState(() => _favoriteIsLoading = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('userId', isEqualTo: widget.userId)
          .where('isFavorite', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(_loadMoreCount)
          .get();

      var posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      // AIモードのフィルタリング
      if (!widget.isMyProfile && !widget.viewerIsAI) {
        posts = posts.where((post) => post.postMode != 'ai').toList();
      }

      if (mounted) {
        setState(() {
          _favoritePosts = posts;
          _favoriteLastDocument = snapshot.docs.isNotEmpty
              ? snapshot.docs.last
              : null;
          _favoriteHasMore = snapshot.docs.length == _loadMoreCount;
          _favoriteIsLoading = false;
        });
        // ロード完了を親へ通知
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onLoadComplete?.call();
        });
      }
    } catch (e) {
      debugPrint('Error loading favorites: $e');
      if (mounted) {
        setState(() => _favoriteIsLoading = false);
      }
    }
  }

  /// お気に入り投稿の追加読み込み
  Future<void> _loadMoreFavorites() async {
    if (!_favoriteHasMore ||
        _favoriteIsLoadingMore ||
        _favoriteLastDocument == null) {
      return;
    }

    setState(() => _favoriteIsLoadingMore = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('userId', isEqualTo: widget.userId)
          .where('isFavorite', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(_loadMoreCount)
          .startAfterDocument(_favoriteLastDocument!)
          .get();

      var newPosts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      // AIモードのフィルタリング
      if (!widget.isMyProfile && !widget.viewerIsAI) {
        newPosts = newPosts.where((post) => post.postMode != 'ai').toList();
      }

      if (mounted) {
        setState(() {
          _favoritePosts.addAll(newPosts);
          _favoriteLastDocument = snapshot.docs.isNotEmpty
              ? snapshot.docs.last
              : null;
          _favoriteHasMore = snapshot.docs.length == _loadMoreCount;
          _favoriteIsLoadingMore = false;
        });
        // ロード完了を親へ通知
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onLoadComplete?.call();
        });
      }
    } catch (e) {
      debugPrint('Error loading more favorites: $e');
      if (mounted) {
        setState(() => _favoriteIsLoadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ロード中
    final isCurrentlyLoading = _currentTab == 2
        ? _favoriteIsLoading
        : _isLoading;
    if (isCurrentlyLoading) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    }

    // タブ表示（複数Sliverを SliverMainAxisGroup でまとめる）
    return SliverMainAxisGroup(
      slivers: [
        // タブバー
        SliverToBoxAdapter(
          child: Container(
            key: widget.tabsContainerKey,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: widget.accentColor,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              dividerColor: Colors.transparent,
              tabs: [
                const Tab(child: Icon(Icons.home_outlined, size: 20)),
                const Tab(child: Icon(Icons.people_outline, size: 20)),
                Tab(
                  key: widget.favoritesTabKey,
                  child: const Icon(
                    Icons.star_outline,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        // 投稿リスト（SliverList.builder で遅延ビルド）
        _buildPostSliver(),
      ],
    );
  }

  Widget _buildPostSliver() {
    final posts = _currentPosts;

    if (posts.isEmpty) {
      String emptyMessage;
      switch (_currentTab) {
        case 0:
          emptyMessage = 'まだTL投稿がないよ';
          break;
        case 1:
          emptyMessage = 'まだサークル投稿がないよ';
          break;
        case 2:
          emptyMessage = 'お気に入りがないよ';
          break;
        default:
          emptyMessage = 'まだ投稿がないよ';
      }

      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Text(
                _currentTab == 2 ? '⭐' : '📝',
                style: const TextStyle(fontSize: 48),
              ),
              const SizedBox(height: 8),
              Text(
                emptyMessage,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return SliverList.builder(
      itemCount: posts.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        // ローディングインジケーター（最後のアイテム）
        if (index == posts.length) {
          if (isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            );
          }
          // 追加データがある場合はスペースを確保
          return const SizedBox(height: 50);
        }

        final post = posts[index];
        return ProfilePostCard(
          key: ValueKey('${post.id}_${post.isFavorite}'),
          post: post,
          isMyProfile: widget.isMyProfile,
          onDeleted: () {
            setState(() {
              _posts.removeWhere((p) => p.id == post.id);
              _favoritePosts.removeWhere((p) => p.id == post.id);
            });
          },
          onFavoriteToggled: (bool isFavorite) {
            setState(() {
              // TL/サークル投稿を更新
              final idx = _posts.indexWhere((p) => p.id == post.id);
              if (idx != -1) {
                _posts[idx] = _posts[idx].copyWith(isFavorite: isFavorite);
              }

              // お気に入りリストを更新
              if (isFavorite) {
                // お気に入りに追加
                if (!_favoritePosts.any((p) => p.id == post.id)) {
                  _favoritePosts.insert(0, post.copyWith(isFavorite: true));
                }
              } else {
                // お気に入りから削除
                _favoritePosts.removeWhere((p) => p.id == post.id);
              }
            });
          },
        );
      },
    );
  }
}
