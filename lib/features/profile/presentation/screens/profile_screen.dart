import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/models/post_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/follow_service.dart';
import '../../../../shared/services/post_service.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/widgets/virtue_indicator.dart';
import '../../../home/presentation/widgets/reaction_background.dart';

/// プロフィール画面
class ProfileScreen extends ConsumerStatefulWidget {
  final String? userId; // nullの場合は自分のプロフィール

  const ProfileScreen({super.key, this.userId});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  UserModel? _targetUser;
  bool _isLoading = true;
  bool _isOwnProfile = false;
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  final _followService = FollowService();
  final _userPostsListKey = GlobalKey<_UserPostsListState>();

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;

    debugPrint('ProfileScreen: Loading user with userId: ${widget.userId}');
    debugPrint('ProfileScreen: Current user uid: ${currentUser?.uid}');

    if (widget.userId == null || widget.userId == currentUser?.uid) {
      // 自分のプロフィール
      setState(() {
        _targetUser = currentUser;
        _isOwnProfile = true;
        _isLoading = false;
      });
    } else {
      // 他ユーザーのプロフィール
      try {
        debugPrint(
          'ProfileScreen: Fetching user from Firestore: ${widget.userId}',
        );
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .get();

        debugPrint('ProfileScreen: Document exists: ${doc.exists}');

        if (doc.exists) {
          // フォロー状態を取得
          final isFollowing = await _followService.getFollowStatus(
            widget.userId!,
          );

          setState(() {
            _targetUser = UserModel.fromFirestore(doc);
            _isOwnProfile = false;
            _isFollowing = isFollowing;
            _isLoading = false;
          });
        } else {
          debugPrint('ProfileScreen: User not found in Firestore');
          setState(() {
            _isLoading = false;
          });
        }
      } catch (e) {
        debugPrint('ProfileScreen: Error loading user: $e');
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    if (_isFollowLoading || _targetUser == null) return;

    setState(() => _isFollowLoading = true);

    try {
      if (_isFollowing) {
        await _followService.unfollowUser(_targetUser!.uid);
      } else {
        await _followService.followUser(_targetUser!.uid);
      }
      setState(() => _isFollowing = !_isFollowing);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isFollowing ? 'フォロー解除に失敗しました' : 'フォローに失敗しました'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFollowLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 自分のプロフィールの場合はリアルタイム更新
    if (_isOwnProfile) {
      final currentUser = ref.watch(currentUserProvider);
      return currentUser.when(
        data: (user) => _buildProfile(user),
        loading: () => _buildLoading(),
        error: (e, _) => _buildError(),
      );
    }

    if (_isLoading) {
      return _buildLoading();
    }

    return _buildProfile(_targetUser);
  }

  Widget _buildLoading() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: Center(
          child: Text(AppConstants.friendlyMessages['error_general']!),
        ),
      ),
    );
  }

  Widget _buildProfile(UserModel? user) {
    if (user == null) {
      return Scaffold(
        appBar: _isOwnProfile ? null : AppBar(title: const Text('プロフィール')),
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.warmGradient),
          child: const Center(child: Text('ユーザーが見つからないよ 😢')),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: SafeArea(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification) {
                debugPrint(
                  'ProfileScreen: ScrollEnd - extentAfter: ${notification.metrics.extentAfter}',
                );
                if (notification.metrics.extentAfter < 300) {
                  debugPrint(
                    'ProfileScreen: Near bottom, calling loadMoreCurrentTab',
                  );
                  _userPostsListKey.currentState?.loadMoreCurrentTab();
                }
              }
              return false;
            },
            child: CustomScrollView(
              slivers: [
                // ヘッダー
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        if (!_isOwnProfile)
                          IconButton(
                            onPressed: () => context.pop(),
                            icon: const Icon(Icons.arrow_back),
                          ),
                        Text(
                          _isOwnProfile ? 'マイページ' : 'プロフィール',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const Spacer(),
                        // 管理者専用：レビュー画面リンク
                        if (_isOwnProfile && widget.userId == null)
                          StreamBuilder<String?>(
                            stream: Stream.value(
                              ref.read(currentUserProvider).valueOrNull?.uid,
                            ),
                            builder: (context, snapshot) {
                              const adminUid = 'hYr5LUH4mhR60oQfVOggrjGYJjG2';
                              if (snapshot.data == adminUid) {
                                return IconButton(
                                  onPressed: () =>
                                      context.push('/admin-review'),
                                  icon: const Icon(Icons.flag_outlined),
                                  tooltip: '要審査投稿',
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        if (_isOwnProfile)
                          IconButton(
                            onPressed: () => context.push('/settings'),
                            icon: const Icon(Icons.settings_outlined),
                          ),
                      ],
                    ),
                  ),
                ),

                // プロフィールカード
                SliverToBoxAdapter(
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          // アバター
                          AvatarWidget(avatarIndex: user.avatarIndex, size: 80),
                          const SizedBox(height: 16),

                          // 名前
                          Text(
                            user.displayName,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),

                          // フォローボタン（他ユーザーのみ）
                          if (!_isOwnProfile) ...[
                            const SizedBox(height: 16),
                            SizedBox(
                              width: 140,
                              child: ElevatedButton(
                                onPressed: _isFollowLoading
                                    ? null
                                    : _toggleFollow,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isFollowing
                                      ? AppColors.surfaceVariant
                                      : AppColors.primary,
                                  foregroundColor: _isFollowing
                                      ? AppColors.textPrimary
                                      : Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    side: _isFollowing
                                        ? BorderSide(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.3,
                                            ),
                                          )
                                        : BorderSide.none,
                                  ),
                                ),
                                child: _isFollowLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      )
                                    : Text(_isFollowing ? 'フォロー中' : 'フォローする'),
                              ),
                            ),
                          ],

                          // 自己紹介
                          if (user.bio != null && user.bio!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              user.bio!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],

                          const SizedBox(height: 20),

                          // 統計
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _StatItem(
                                label: '投稿',
                                value: '${user.totalPosts}',
                                icon: Icons.article_outlined,
                              ),
                              _StatItem(
                                label: '称賛',
                                value: '${user.totalPraises}',
                                icon: Icons.favorite_outline,
                              ),
                              // 自分のプロフィールの場合は詳細な徳ポイント表示
                              if (_isOwnProfile)
                                const VirtueIndicator(showLabel: true, size: 50)
                              else
                                _StatItem(
                                  label: '徳',
                                  value: '${user.virtue}',
                                  icon: Icons.stars_outlined,
                                  color: AppColors.virtue,
                                ),
                            ],
                          ),

                          // BAN状態の警告
                          if (user.isBanned) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.error.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: AppColors.error,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'アカウントが制限されています。投稿やコメントができません。',
                                      style: TextStyle(
                                        color: AppColors.error,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 24)),

                // フォロー中（自分のプロフィールのみ）
                // 実際のfollowingリストの長さを使用（followingCountとの不整合を防ぐ）
                if (_isOwnProfile && user.following.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Text(
                            'フォロー中',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverToBoxAdapter(
                    child: _FollowingList(followingIds: user.following),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],

                // 過去の投稿
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      '${user.displayName}さんの投稿',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // 投稿一覧
                _UserPostsList(
                  key: _userPostsListKey,
                  userId: user.uid,
                  isMyProfile: _isOwnProfile,
                  viewerIsAI:
                      ref.watch(currentUserProvider).valueOrNull?.isAI ?? false,
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ユーザーの投稿一覧（プル更新方式）
class _UserPostsList extends StatefulWidget {
  final String userId;
  final bool isMyProfile;
  final bool viewerIsAI;

  const _UserPostsList({
    super.key,
    required this.userId,
    this.isMyProfile = false,
    this.viewerIsAI = false,
  });

  @override
  State<_UserPostsList> createState() => _UserPostsListState();
}

class _UserPostsListState extends State<_UserPostsList>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 全投稿を一括管理（最初30件 + 追加読み込み分）
  List<PostModel> _posts = [];
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  // 初期読み込み件数
  static const int _initialLoadCount = 30;
  static const int _loadMoreCount = 10;

  int get _currentTab => _tabController.index;

  // タブごとにフィルタリング
  List<PostModel> get _tlPosts =>
      _posts.where((p) => p.circleId == null).toList();
  List<PostModel> get _circlePosts =>
      _posts.where((p) => p.circleId != null).toList();
  List<PostModel> get _favoritePosts =>
      _posts.where((p) => p.isFavorite).toList();

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

  /// 親から呼び出されるメソッド：追加読み込み
  void loadMoreCurrentTab() {
    if (_hasMore && !_isLoadingMore) {
      _loadMorePosts();
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadPosts();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      // タブ切替時：30件を超えた分を破棄
      if (_posts.length > _initialLoadCount) {
        setState(() {
          _posts = _posts.take(_initialLoadCount).toList();
          // lastDocumentをリセット（30件目のドキュメントに戻す）
          // 次回追加読み込み時に再取得される
          _hasMore = true;
        });
      }
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
      }
    } catch (e) {
      debugPrint('Error loading more posts: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ロード中
    if (_isLoading) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    }

    // タブ表示
    return SliverToBoxAdapter(
      child: Column(
        children: [
          // タブバー
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppColors.primary,
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
              tabs: const [
                Tab(child: Icon(Icons.home_outlined, size: 20)),
                Tab(child: Icon(Icons.people_outline, size: 20)),
                Tab(child: Icon(Icons.star_outline, size: 20)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 投稿リスト
          _buildPostList(),
        ],
      ),
    );
  }

  Widget _buildPostList() {
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

      return Padding(
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
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: posts.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        // ローディングインジケーター（最後のアイテム）
        if (index == posts.length) {
          if (_isLoadingMore) {
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
        return _ProfilePostCard(
          key: ValueKey('${post.id}_${post.isFavorite}'),
          post: post,
          isMyProfile: widget.isMyProfile,
          onDeleted: () {
            setState(() {
              _posts.removeWhere((p) => p.id == post.id);
            });
          },
          onFavoriteToggled: (bool isFavorite) {
            setState(() {
              final idx = _posts.indexWhere((p) => p.id == post.id);
              if (idx != -1) {
                _posts[idx] = _posts[idx].copyWith(isFavorite: isFavorite);
              }
            });
          },
        );
      },
    );
  }
}

/// プロフィール画面用の投稿カード
class _ProfilePostCard extends StatefulWidget {
  final PostModel post;
  final bool isMyProfile;
  final VoidCallback? onDeleted;
  final void Function(bool isFavorite)? onFavoriteToggled;

  const _ProfilePostCard({
    super.key,
    required this.post,
    this.isMyProfile = false,
    this.onDeleted,
    this.onFavoriteToggled,
  });

  @override
  State<_ProfilePostCard> createState() => _ProfilePostCardState();
}

class _ProfilePostCardState extends State<_ProfilePostCard> {
  bool _isDeleting = false;

  Future<void> _deletePost() async {
    setState(() => _isDeleting = true);

    final deleted = await PostService().deletePost(
      context: context,
      post: widget.post,
      onDeleted: widget.onDeleted,
    );

    if (!deleted && mounted) {
      setState(() => _isDeleting = false);
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final newValue = !widget.post.isFavorite;
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.post.id)
          .update({'isFavorite': newValue});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newValue ? 'お気に入りに追加しました' : 'お気に入りから削除しました'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 1),
          ),
        );
        // リストを即時更新
        widget.onFavoriteToggled?.call(newValue);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラーが発生しました: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // リアクション背景
          if (widget.post.reactions.isNotEmpty)
            Positioned.fill(
              child: ReactionBackground(
                reactions: widget.post.reactions,
                postId: widget.post.id,
                opacity: 0.15,
                maxIcons: 15,
              ),
            ),
          // コンテンツ
          InkWell(
            onTap: () => context.push('/post/${widget.post.id}'),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ヘッダー（自分のプロフィールなら削除ボタン）
                  if (widget.isMyProfile)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // お気に入りアイコン
                        if (widget.post.isFavorite)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.star,
                              size: 18,
                              color: Colors.amber,
                            ),
                          ),
                        if (_isDeleting)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_horiz,
                              color: AppColors.textHint,
                              size: 20,
                            ),
                            onSelected: (value) {
                              if (value == 'delete') {
                                _deletePost();
                              } else if (value == 'favorite') {
                                _toggleFavorite();
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'favorite',
                                child: Row(
                                  children: [
                                    Icon(
                                      widget.post.isFavorite
                                          ? Icons.star
                                          : Icons.star_outline,
                                      size: 18,
                                      color: Colors.amber,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      widget.post.isFavorite
                                          ? 'お気に入りから削除'
                                          : 'お気に入りに追加',
                                    ),
                                  ],
                                ),
                              ),
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
                            ],
                          ),
                      ],
                    ),

                  // サークル名バッジ（サークル投稿の場合）
                  if (widget.post.circleId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('circles')
                            .doc(widget.post.circleId)
                            .get(),
                        builder: (context, snapshot) {
                          // ロード中は何も表示しない
                          if (!snapshot.hasData) {
                            return const SizedBox.shrink();
                          }
                          // サークルが削除されている場合
                          if (!snapshot.data!.exists) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.group_off_outlined,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '削除済みサークル',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          final circleName =
                              snapshot.data!.get('name') as String? ?? 'サークル';
                          return GestureDetector(
                            onTap: () =>
                                context.push('/circle/${widget.post.circleId}'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.group_outlined,
                                    size: 14,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    circleName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  // 投稿内容
                  Text(
                    widget.post.content,
                    style: Theme.of(context).textTheme.bodyLarge,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),

                  // フッター
                  Row(
                    children: [
                      // 時間
                      Text(
                        timeago.format(widget.post.createdAt, locale: 'ja'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textHint,
                        ),
                      ),

                      // メディアアイコン
                      if (widget.post.allMedia.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        ..._buildMediaIcons(),
                      ],

                      const Spacer(),
                      // リアクション数
                      Row(
                        children: [
                          Icon(Icons.favorite, size: 16, color: AppColors.love),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.post.reactions.values.fold(0, (a, b) => a + b)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 12),
                          // コメント数（PostModelから取得）
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.chat_bubble_outline,
                                size: 16,
                                color: AppColors.textHint,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${widget.post.commentCount}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
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

  /// メディアアイコンを生成
  List<Widget> _buildMediaIcons() {
    final imageCount = widget.post.allMedia
        .where((m) => m.type == MediaType.image)
        .length;
    final videoCount = widget.post.allMedia
        .where((m) => m.type == MediaType.video)
        .length;

    final icons = <Widget>[];

    if (imageCount > 0) {
      icons.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.image_outlined,
              size: 16,
              color: AppColors.textHint,
            ),
            if (imageCount > 1) ...[
              const SizedBox(width: 2),
              Text(
                '$imageCount',
                style: const TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
            ],
          ],
        ),
      );
    }

    if (videoCount > 0) {
      if (icons.isNotEmpty) icons.add(const SizedBox(width: 8));
      icons.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_outlined,
              size: 16,
              color: AppColors.textHint,
            ),
            if (videoCount > 1) ...[
              const SizedBox(width: 2),
              Text(
                '$videoCount',
                style: const TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
            ],
          ],
        ),
      );
    }

    return icons;
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color ?? AppColors.primary, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color ?? AppColors.textPrimary,
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// フォロー中リスト（横スクロール）
class _FollowingList extends StatelessWidget {
  final List<String> followingIds;

  const _FollowingList({required this.followingIds});

  @override
  Widget build(BuildContext context) {
    if (followingIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: followingIds.length,
        itemBuilder: (context, index) {
          final userId = followingIds[index];
          return _FollowingUserItem(userId: userId);
        },
      ),
    );
  }
}

/// フォロー中ユーザーアイテム
class _FollowingUserItem extends StatelessWidget {
  final String userId;

  const _FollowingUserItem({required this.userId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final user = UserModel.fromFirestore(snapshot.data!);

        return GestureDetector(
          onTap: () => context.push('/user/${user.uid}'),
          child: Container(
            width: 80,
            margin: const EdgeInsets.only(right: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AvatarWidget(avatarIndex: user.avatarIndex, size: 56),
                const SizedBox(height: 8),
                Text(
                  user.displayName,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
