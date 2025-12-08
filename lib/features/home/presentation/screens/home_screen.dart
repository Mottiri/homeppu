import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/models/post_model.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../widgets/post_card.dart';

/// ホーム画面（タイムライン）
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

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.warmGradient,
        ),
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
                        const Text(
                          '🌸',
                          style: TextStyle(fontSize: 32),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppConstants.appName,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            currentUser.when(
                              data: (user) => Text(
                                user != null
                                    ? '${user.displayName}さん、おはよう！'
                                    : 'ようこそ！',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            ),
                          ],
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
                ),
                // フォロー中タブ
                _TimelineTab(
                  isFollowingOnly: true,
                  currentUser: currentUser.valueOrNull,
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
    return Container(
      color: AppColors.background,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}

/// タイムラインタブ
class _TimelineTab extends StatelessWidget {
  final bool isFollowingOnly;
  final UserModel? currentUser;

  const _TimelineTab({
    required this.isFollowingOnly,
    required this.currentUser,
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
    );
  }
}

/// 投稿リスト
class _PostsList extends StatelessWidget {
  final Query query;
  final bool isAIViewer;
  final String? currentUserId;

  const _PostsList({
    required this.query,
    this.isAIViewer = false,
    this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
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

        if (snapshot.hasError) {
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
              ],
            ),
          );
        }

        // 投稿をフィルタリング
        // AIアカウント: 全モードの投稿を見れる
        // 人間アカウント: 'mix'と'human'の投稿のみ見れる（'ai'モードは見えない）
        // ただし、自分の投稿は常に見える
        var posts = snapshot.data?.docs
                .map((doc) => PostModel.fromFirestore(doc))
                .toList() ??
            [];

        if (!isAIViewer) {
          // 人間アカウントの場合、'ai'モードの投稿を除外（自分の投稿は除外しない）
          posts = posts.where((post) => 
            post.postMode != 'ai' || post.userId == currentUserId
          ).toList();
        }

        if (posts.isEmpty) {
          return Center(
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
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 120),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            return PostCard(post: posts[index]);
          },
        );
      },
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
