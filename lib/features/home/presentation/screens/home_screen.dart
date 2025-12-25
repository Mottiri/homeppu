import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/models/post_model.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/repositories/notification_repository.dart';
import '../widgets/post_card.dart';
import 'package:go_router/go_router.dart';

/// タイムラインリフレッシュ用のProvider（投稿作成後にインクリメント）
final timelineRefreshProvider = StateProvider<int>((ref) => 0);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final refreshKey = ref.watch(timelineRefreshProvider); // リフレッシュキーを取得

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: SafeArea(
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                // ヘッダー
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        // ロゴアイコン
                        Image.asset(
                          'assets/icons/logo.png',
                          width: 40,
                          height: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppConstants.appName,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              currentUser.when(
                                data: (user) => Text(
                                  user != null
                                      ? '${user.displayName}さん、おはよう！'
                                      : 'ようこそ！',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                loading: () => const SizedBox.shrink(),
                                error: (e, _) => const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                        // 通知アイコン
                        currentUser.when(
                          data: (user) {
                            if (user == null) return const SizedBox.shrink();
                            return StreamBuilder<int>(
                              stream: ref
                                  .watch(notificationRepositoryProvider)
                                  .getUnreadCountStream(user.uid),
                              builder: (context, snapshot) {
                                final count = snapshot.data ?? 0;
                                return Stack(
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.notifications_outlined,
                                        size: 28,
                                      ),
                                      onPressed: () =>
                                          context.push('/notifications'),
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
                          loading: () => const SizedBox.shrink(),
                          error: (e, _) => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),

                // タブバー
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverTabBarDelegate(
                    TabBar(
                      controller: _tabController,
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
                      tabs: const [
                        Tab(text: 'おすすめ'),
                        Tab(text: 'フォロー中'),
                      ],
                    ),
                  ),
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                // おすすめタブ（全体のタイムライン）
                _TimelineTab(
                  isFollowingOnly: false,
                  currentUser: currentUser.valueOrNull,
                  refreshKey: refreshKey,
                ),
                // フォロー中タブ
                _TimelineTab(
                  isFollowingOnly: true,
                  currentUser: currentUser.valueOrNull,
                  refreshKey: refreshKey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// タブバー用のデリゲート
class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _SliverTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: AppColors.background, child: tabBar);
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    // タブバーが変わった場合は再構築（新着ドット表示のため）
    return tabBar != oldDelegate.tabBar;
  }
}

/// タイムラインタブ
class _TimelineTab extends StatelessWidget {
  final bool isFollowingOnly;
  final UserModel? currentUser;
  final int refreshKey;

  const _TimelineTab({
    required this.isFollowingOnly,
    required this.currentUser,
    this.refreshKey = 0,
  });

  String? get currentUserId => currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    // フォロー中タブの場合、フォローしているユーザーのIDを取得する必要がある
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

          return _PostsList(
            query: FirebaseFirestore.instance
                .collection('posts')
                .where('isVisible', isEqualTo: true)
                .where('userId', whereIn: followingIds.take(10).toList())
                .orderBy('createdAt', descending: true)
                .limit(AppConstants.postsPerPage),
            isAIViewer: currentUser!.isAI,
            currentUserId: currentUserId,
            refreshKey: refreshKey,
          );
        },
      );
    }

    // おすすめタブ（全体）
    return _PostsList(
      query: FirebaseFirestore.instance
          .collection('posts')
          .where('isVisible', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(AppConstants.postsPerPage),
      isAIViewer: currentUser?.isAI ?? false,
      currentUserId: currentUserId,
      refreshKey: refreshKey,
    );
  }
}

/// 投稿リスト（プル更新方式 + 無限スクロール）
class _PostsList extends StatefulWidget {
  final Query query;
  final bool isAIViewer;
  final String? currentUserId;
  final int refreshKey; // リフレッシュ用のキー

  const _PostsList({
    required this.query,
    this.isAIViewer = false,
    this.currentUserId,
    this.refreshKey = 0,
  });

  @override
  State<_PostsList> createState() => _PostsListState();
}

class _PostsListState extends State<_PostsList> {
  List<PostModel> _posts = [];
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  @override
  void didUpdateWidget(_PostsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // クエリが変わった場合、またはrefreshKeyが変わった場合は再読み込み
    if (widget.query != oldWidget.query ||
        widget.refreshKey != oldWidget.refreshKey) {
      _loadPosts();
    }
  }

  /// 初回読み込み & プルダウン時の読み込み
  Future<void> _loadPosts() async {
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

      // AIモードのフィルタリング
      if (!widget.isAIViewer) {
        posts = posts
            .where(
              (post) =>
                  post.postMode != 'ai' || post.userId == widget.currentUserId,
            )
            .toList();
      }

      setState(() {
        _posts = posts;
        _lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length == AppConstants.postsPerPage;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading posts: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  /// 追加読み込み（無限スクロール）
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

      // AIモードのフィルタリング
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text('みんなの投稿を読み込み中...'),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('😢', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              AppConstants.friendlyMessages['error_general']!,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadPosts, child: const Text('再読み込み')),
          ],
        ),
      );
    }

    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPosts,
        color: AppColors.primary,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('✨', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 16),
                  Text(
                    'まだ投稿がないよ',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '最初の投稿をしてみよう！',
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

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // スクロール末尾に近づいたら追加読み込み
        if (notification is ScrollEndNotification &&
            notification.metrics.extentAfter < 300) {
          _loadMorePosts();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: _loadPosts,
        color: AppColors.primary,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 120),
          itemCount: _posts.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _posts.length) {
              // ローディングインジケーター
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              );
            }
            return PostCard(
              key: ValueKey(_posts[index].id),
              post: _posts[index],
              onDeleted: () {
                // 自分の投稿を削除した場合、ローカルリストから即座に削除
                setState(() {
                  _posts.removeAt(index);
                });
              },
            );
          },
        ),
      ),
    );
  }
}

/// フォロー中が空の状態
class _EmptyFollowingState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('👥', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              'まだ誰もフォローしていないよ',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '「おすすめ」タブで気になる人を\n見つけてフォローしてみよう！',
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
