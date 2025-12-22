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
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/widgets/virtue_indicator.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;

    print('ProfileScreen: Loading user with userId: ${widget.userId}');
    print('ProfileScreen: Current user uid: ${currentUser?.uid}');

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
        print('ProfileScreen: Fetching user from Firestore: ${widget.userId}');
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .get();

        print('ProfileScreen: Document exists: ${doc.exists}');

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
          print('ProfileScreen: User not found in Firestore');
          setState(() {
            _isLoading = false;
          });
        }
      } catch (e) {
        print('ProfileScreen: Error loading user: $e');
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
        error: (_, __) => _buildError(),
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
                                onPressed: () => context.push('/admin-review'),
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
                                          color: AppColors.primary.withOpacity(
                                            0.3,
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
                              color: AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.error.withOpacity(0.3),
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
    );
  }
}

/// ユーザーの投稿一覧（プル更新方式）
class _UserPostsList extends StatefulWidget {
  final String userId;
  final bool isMyProfile;
  final bool viewerIsAI;

  const _UserPostsList({
    required this.userId,
    this.isMyProfile = false,
    this.viewerIsAI = false,
  });

  @override
  State<_UserPostsList> createState() => _UserPostsListState();
}

class _UserPostsListState extends State<_UserPostsList>
    with SingleTickerProviderStateMixin {
  List<PostModel> _posts = [];
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  late TabController _tabController;

  // TL投稿とサークル投稿を分離
  List<PostModel> get _tlPosts =>
      _posts.where((p) => p.circleId == null).toList();
  List<PostModel> get _circlePosts =>
      _posts.where((p) => p.circleId != null).toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPosts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('userId', isEqualTo: widget.userId)
          .orderBy('createdAt', descending: true)
          .limit(20)
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
          _hasMore = snapshot.docs.length == 20;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user posts: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMorePosts() async {
    if (!_hasMore || _isLoadingMore || _lastDocument == null) return;

    setState(() => _isLoadingMore = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('userId', isEqualTo: widget.userId)
          .orderBy('createdAt', descending: true)
          .limit(20)
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
          _hasMore = snapshot.docs.length == 20;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading more user posts: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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

    if (_posts.isEmpty) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                Text('📝', style: TextStyle(fontSize: 48)),
                SizedBox(height: 8),
                Text(
                  'まだ投稿がないよ',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
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
              onTap: (_) => setState(() {}),
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
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('TL投稿'),
                      if (_tlPosts.isNotEmpty) _buildBadge(_tlPosts.length, 0),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('サークル'),
                      if (_circlePosts.isNotEmpty)
                        _buildBadge(_circlePosts.length, 1),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 投稿リスト
          _buildPostList(_tabController.index == 0 ? _tlPosts : _circlePosts),
        ],
      ),
    );
  }

  Widget _buildBadge(int count, int tabIndex) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _tabController.index == tabIndex
            ? Colors.white.withOpacity(0.3)
            : AppColors.primary.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$count', style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _buildPostList(List<PostModel> posts) {
    if (posts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          children: [
            Text('📝', style: TextStyle(fontSize: 48)),
            SizedBox(height: 8),
            Text('まだ投稿がないよ', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return _ProfilePostCard(
          post: post,
          isMyProfile: widget.isMyProfile,
          onDeleted: () {
            setState(() {
              _posts.removeWhere((p) => p.id == post.id);
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

  const _ProfilePostCard({
    required this.post,
    this.isMyProfile = false,
    this.onDeleted,
  });

  @override
  State<_ProfilePostCard> createState() => _ProfilePostCardState();
}

class _ProfilePostCardState extends State<_ProfilePostCard> {
  bool _isDeleting = false;

  Future<void> _deletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('投稿を削除'),
        content: const Text('この投稿を削除しますか？\nこの操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      // バッチ処理で一括削除（整合性担保とルール回避のため）
      final batch = FirebaseFirestore.instance.batch();

      // 1. 関連するコメントを削除対象に追加
      final comments = await FirebaseFirestore.instance
          .collection('comments')
          .where('postId', isEqualTo: widget.post.id)
          .get();

      for (final doc in comments.docs) {
        batch.delete(doc.reference);
      }

      // 2. 関連するリアクションも削除対象に追加
      final reactions = await FirebaseFirestore.instance
          .collection('reactions')
          .where('postId', isEqualTo: widget.post.id)
          .get();

      for (final doc in reactions.docs) {
        batch.delete(doc.reference);
      }

      // 3. 投稿自体を削除対象に追加
      batch.delete(
        FirebaseFirestore.instance.collection('posts').doc(widget.post.id),
      );

      // 4. ユーザーの投稿数を減少
      batch.update(
        FirebaseFirestore.instance.collection('users').doc(widget.post.userId),
        {'totalPosts': FieldValue.increment(-1)},
      );

      // コミット
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('投稿を削除しました'),
            backgroundColor: Colors.green,
          ),
        );
        // 親のリストから削除
        widget.onDeleted?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('削除に失敗しました: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
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
                          }
                        },
                        itemBuilder: (context) => [
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
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.3),
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
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.textHint),
                  ),
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
    );
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
