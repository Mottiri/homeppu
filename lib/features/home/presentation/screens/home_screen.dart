import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/loading_state.dart';
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
        decoration: const BoxDecoration(
          // 放射状グラデーション背景で深みを演出
          gradient: AppColors.heroGradient,
        ),
        child: SafeArea(
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                // ヘッダー（ロゴ中央 + 通知アイコン右）
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // ロゴ（中央）- 繊細なアニメーション
                        Image.asset(
                          'assets/icons/logo.png',
                          width: 72,
                          height: 72,
                        )
                            .animate(
                              onPlay: (controller) => controller.repeat(),
                            )
                            .shimmer(
                              duration: 3000.ms,
                              color: AppColors.primary.withValues(alpha: 0.1),
                            ),
                        // 通知アイコン（右端）
                        Positioned(
                          right: 0,
                          child: currentUser.when(
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
                        ),
                      ],
                    ),
                  ),
                ),

                // タブバー（強化版）
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StyledTabBarDelegate(
                    TabBar(
                      controller: _tabController,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.textHint,
                      indicatorColor: Colors.transparent,
                      dividerColor: Colors.transparent,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                      indicator: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      indicatorPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      tabs: const [
                        _StyledTab(label: 'おすすめ', icon: Icons.explore_outlined),
                        _StyledTab(label: 'フォロー中', icon: Icons.people_outline),
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

/// スタイル付きタブ
class _StyledTab extends StatelessWidget {
  final String label;
  final IconData icon;

  const _StyledTab({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

/// タブバー用のデリゲート（強化版）
class _StyledTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _StyledTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height + 16;

  @override
  double get maxExtent => tabBar.preferredSize.height + 16;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        // 下にスクロールした時の微細なシャドウ
        boxShadow: overlapsContent
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: tabBar,
      ),
    );
  }

  @override
  bool shouldRebuild(_StyledTabBarDelegate oldDelegate) {
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

    // おすすめタブ（全体）- サークル投稿を除外
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
      return const LoadingStates.posts;
    }

    if (_hasError) {
      return EmptyStates.error(onRetry: _loadPosts);
    }

    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPosts,
        color: AppColors.primary,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            EmptyStates.noPosts(),
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
    return EmptyStates.noFollowing();
  }
}
