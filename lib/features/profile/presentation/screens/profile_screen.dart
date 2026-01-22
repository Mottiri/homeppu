import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/utils/dialog_helper.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/follow_service.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../admin/presentation/widgets/admin_menu_bottom_sheet.dart';
import '../widgets/profile_posts_list.dart';
import '../widgets/profile_following_list.dart';
import '../../../../shared/widgets/infinite_scroll_listener.dart';
import '../../../../shared/widgets/load_more_footer.dart';

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
  final _userPostsListKey = GlobalKey<ProfilePostsListState>();
  final ScrollController _scrollController = ScrollController();
  bool _isScrollable = false;

  // ヘッダー画像とカラーパレット
  late int _headerImageIndex;
  late Color _primaryAccent;
  late Color _secondaryAccent;

  // ヘッダー画像のパスリスト（6種類）
  static const List<String> _headerImages = [
    'assets/images/headers/header_wave_1.png',
    'assets/images/headers/header_wave_2.png',
    'assets/images/headers/header_wave_3.png',
    'assets/images/headers/header_wave_4.png',
    'assets/images/headers/header_wave_5.png',
    'assets/images/headers/header_wave_6.png',
  ];

  // 各ヘッダー画像に対応するカラーパレット [primaryAccent, secondaryAccent]
  static const List<List<Color>> _headerColorPalettes = [
    [Color(0xFF7DD3C0), Color(0xFFE8A87C)], // 1: ティール＆コーラル
    [Color(0xFF9B7EDE), Color(0xFFE890A0)], // 2: パープル＆ピンク
    [Color(0xFF6CB4EE), Color(0xFFFFB366)], // 3: ブルー＆オレンジ
    [Color(0xFF7EC889), Color(0xFFF9D56E)], // 4: グリーン＆イエロー
    [Color(0xFFE8A0BF), Color(0xFFB392AC)], // 5: ピンク＆パープル
    [Color(0xFF70B8C4), Color(0xFFD4A574)], // 6: スカイブルー＆サンド
  ];

  @override
  void initState() {
    super.initState();
    _generateHeaderAndColors();
    _loadUser();
    // 初回レイアウト後にスクロール可能か評価
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollable();
    });
  }

  @override
  void dispose() {
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

  void _handlePostsListUpdated() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollable();
    });
  }

  // ヘッダー画像とカラーパレットを生成（ユーザーIDで固定）
  void _generateHeaderAndColors() {
    // ユーザーIDまたは現在時刻からシードを生成
    final seedBase =
        widget.userId?.hashCode ?? DateTime.now().millisecondsSinceEpoch;
    _headerImageIndex = seedBase.abs() % _headerImages.length;
    _primaryAccent = _headerColorPalettes[_headerImageIndex][0];
    _secondaryAccent = _headerColorPalettes[_headerImageIndex][1];
  }

  // ユーザーの抽出された色を適用（あれば）
  void _applyUserColors(UserModel user) {
    // ユーザーが選択したデフォルト画像インデックスがあればそれを使用
    if (user.headerImageUrl == null && user.headerImageIndex != null) {
      _headerImageIndex = user.headerImageIndex!;
      _primaryAccent = _headerColorPalettes[_headerImageIndex][0];
      _secondaryAccent = _headerColorPalettes[_headerImageIndex][1];
    }
    // カスタム画像から抽出した色があればそれを使用
    if (user.headerPrimaryColor != null) {
      _primaryAccent = Color(user.headerPrimaryColor!);
    }
    if (user.headerSecondaryColor != null) {
      _secondaryAccent = Color(user.headerSecondaryColor!);
    }
  }

  Future<void> _loadUser() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;

    debugPrint('ProfileScreen: Loading user with userId: ${widget.userId}');
    debugPrint('ProfileScreen: Current user uid: ${currentUser?.uid}');

    if (widget.userId == null || widget.userId == currentUser?.uid) {
      // 自分のプロフィール
      if (currentUser != null) {
        _applyUserColors(currentUser);
      }
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

          final user = UserModel.fromFirestore(doc);
          _applyUserColors(user);

          setState(() {
            _targetUser = user;
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
        final message = _isFollowing
            ? AppMessages.error.unfollowFailed
            : AppMessages.error.followFailed;
        SnackBarHelper.showError(context, message);
        debugPrint('フォロー操作エラー: $e');
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
        data: (user) {
          if (user != null) {
            // 色を再適用
            _applyUserColors(user);
          }
          return _buildProfile(user);
        },
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
          child: InfiniteScrollListener(
            isLoadingMore:
                _userPostsListKey.currentState?.isLoadingMore ?? false,
            hasMore: _userPostsListKey.currentState?.hasMore ?? false,
            onLoadMore: () {
              _userPostsListKey.currentState?.loadMoreCurrentTab();
            },
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // ヘッダー画像 + アバター（Stack構造）
                SliverToBoxAdapter(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // ヘッダー画像
                      Consumer(
                        builder: (context, ref, _) {
                          // 自分のプロフィールの場合はRiverpodから最新のユーザー情報を取得
                          final displayUser = _isOwnProfile
                              ? ref.watch(currentUserProvider).valueOrNull
                              : _targetUser;
                          final headerUrl = displayUser?.headerImageUrl;

                          return ClipRect(
                            child: SizedBox(
                              width: double.infinity,
                              height: 180,
                              child: headerUrl != null
                                  ? Image.network(
                                      headerUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (
                                            context,
                                            error,
                                            stackTrace,
                                          ) => Image.asset(
                                            _headerImages[_headerImageIndex],
                                            fit: BoxFit.cover,
                                          ),
                                    )
                                  : Image.asset(
                                      _headerImages[_headerImageIndex],
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          );
                        },
                      ),
                      // 角丸の白い背景（コンテンツエリア上部）
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 30,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFDF8F3), // warmGradientの上部色
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(30),
                              topRight: Radius.circular(30),
                            ),
                          ),
                        ),
                      ),
                      // 戻るボタン（他ユーザー閲覧時）
                      if (!_isOwnProfile)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: IconButton(
                            onPressed: () => context.pop(),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black26,
                            ),
                          ),
                        ),
                      // 設定ボタン等（右上）
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Row(
                          children: [
                            Consumer(
                              builder: (context, ref, _) {
                                final isAdminAsync = ref.watch(isAdminProvider);
                                return isAdminAsync.maybeWhen(
                                  data: (isAdmin) {
                                    if (!isAdmin) {
                                      return const SizedBox.shrink();
                                    }
                                    if (!_isOwnProfile) {
                                      return IconButton(
                                        icon: const Icon(
                                          Icons.admin_panel_settings,
                                          color: Colors.white,
                                        ),
                                        onPressed: () =>
                                            _showUserAdminMenu(context, user),
                                        tooltip: '管理者メニュー',
                                        style: IconButton.styleFrom(
                                          backgroundColor: AppColors.error
                                              .withValues(alpha: 0.8),
                                        ),
                                      );
                                    }
                                    if (_isOwnProfile &&
                                        widget.userId == null) {
                                      return const AdminMenuIcon();
                                    }
                                    return const SizedBox.shrink();
                                  },
                                  orElse: () => const SizedBox.shrink(),
                                );
                              },
                            ),
                            if (_isOwnProfile)
                              IconButton(
                                onPressed: () => context.push('/settings'),
                                icon: const Icon(
                                  Icons.settings_outlined,
                                  color: Colors.white,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black26,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // アバター（中央配置、グラデーション枠 + グロー効果）
                      Positioned(
                        bottom: -55,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [_primaryAccent, _secondaryAccent],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _primaryAccent.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: AvatarWidget(
                                avatarIndex: user.avatarIndex,
                                size: 100,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // アバター分のスペース + 名前（中央揃え）
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 60, 16, 0),
                    child: Column(
                      children: [
                        Text(
                          user.displayName,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        // 自己紹介
                        if (user.bio != null && user.bio!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              user.bio!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // 統計情報（パステルカラー背景）
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _primaryAccent.withValues(alpha: 0.15),
                            _secondaryAccent.withValues(alpha: 0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: _buildProfileStat(
                                '投稿',
                                '${user.totalPosts}',
                              ),
                            ),
                            Container(width: 1, color: Colors.grey.shade300),
                            Expanded(
                              child: _buildProfileStat(
                                '称賛',
                                '${user.totalPraises}',
                              ),
                            ),
                            Container(width: 1, color: Colors.grey.shade300),
                            Expanded(
                              child: _buildProfileStat('徳', '${user.virtue}'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // フォローボタン（ヘッダーカラー）+ メッセージボタン
                if (!_isOwnProfile)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: _isFollowing
                                    ? null
                                    : LinearGradient(
                                        colors: [
                                          _primaryAccent,
                                          _secondaryAccent,
                                        ],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                color: _isFollowing
                                    ? Colors.grey.shade200
                                    : null,
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: ElevatedButton(
                                onPressed: _isFollowLoading
                                    ? null
                                    : _toggleFollow,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: _isFollowing
                                      ? AppColors.textPrimary
                                      : Colors.white,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                ),
                                child: _isFollowLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        _isFollowing ? 'フォロー中' : 'フォロー',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // メッセージボタン
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [_primaryAccent, _secondaryAccent],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: IconButton(
                              onPressed: () {
                                // TODO: メッセージ機能
                              },
                              icon: const Icon(
                                Icons.mail_outline,
                                color: Colors.white,
                              ),
                              padding: const EdgeInsets.all(12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 管理者のみ: 累計被通報回数
                Consumer(
                  builder: (context, ref, _) {
                    final isAdmin =
                        ref.watch(isAdminProvider).valueOrNull ?? false;
                    if (!isAdmin || user.reportCount == 0) {
                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                    }
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: user.reportCount >= 3
                                  ? AppColors.error.withValues(alpha: 0.1)
                                  : Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.flag,
                                  size: 14,
                                  color: user.reportCount >= 3
                                      ? AppColors.error
                                      : Colors.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '累計被通報: ${user.reportCount}回',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: user.reportCount >= 3
                                        ? AppColors.error
                                        : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // BAN状態の警告
                if (user.isBanned)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
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
                            if (_isOwnProfile)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        context.push('/ban-appeal'),
                                    icon: const Icon(
                                      Icons.support_agent,
                                      size: 20,
                                    ),
                                    label: const Text('運営へ問い合わせる'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.error,
                                      side: const BorderSide(
                                        color: AppColors.error,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
                    child: ProfileFollowingList(followingIds: user.following),
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
                ProfilePostsList(
                  key: _userPostsListKey,
                  userId: user.uid,
                  isMyProfile: _isOwnProfile,
                  viewerIsAI:
                      ref.watch(currentUserProvider).valueOrNull?.isAI ?? false,
                  accentColor: _primaryAccent,
                  onLoadComplete: _handlePostsListUpdated,
                ),

                // LoadMoreFooter（ショートリスト用手動フォールバック）
                SliverToBoxAdapter(
                  child: LoadMoreFooter(
                    hasMore: _userPostsListKey.currentState?.hasMore ?? false,
                    isLoadingMore:
                        _userPostsListKey.currentState?.isLoadingMore ?? false,
                    isInitialLoadComplete: true,
                    canLoadMore:
                        _userPostsListKey.currentState?.canLoadMore ?? false,
                    isScrollable: _isScrollable,
                    onLoadMore: () {
                      _userPostsListKey.currentState?.loadMoreCurrentTab();
                    },
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // プロフィール統計項目を構築（ラベルが上、数字が下）
  Widget _buildProfileStat(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // 管理者メニュー表示
  void _showUserAdminMenu(BuildContext context, UserModel user) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('ユーザー情報'),
              subtitle: Text('UID: ${user.uid}\nStatus: ${user.banStatus}'),
            ),
            const Divider(),
            if (user.banStatus == 'none' || user.banStatus == 'temporary') ...[
              if (user.banStatus == 'none')
                ListTile(
                  leading: const Icon(Icons.block, color: Colors.orange),
                  title: const Text('一時BANにする'),
                  onTap: () {
                    Navigator.pop(context);
                    _showBanDialog(context, user, 'temporary');
                  },
                ),
              ListTile(
                leading: const Icon(Icons.gavel, color: Colors.red),
                title: const Text('永久BANにする'),
                onTap: () {
                  Navigator.pop(context);
                  _showBanDialog(context, user, 'permanent');
                },
              ),
            ],
            if (user.banStatus != 'none')
              ListTile(
                leading: const Icon(
                  Icons.settings_backup_restore,
                  color: Colors.green,
                ),
                title: const Text('BANを解除する'),
                onTap: () {
                  Navigator.pop(context);
                  _showUnbanDialog(context, user);
                },
              ),
            if (user.isBanned)
              ListTile(
                leading: const Icon(Icons.chat_outlined, color: Colors.blue),
                title: const Text('異議申し立てチャットを確認'),
                onTap: () {
                  Navigator.pop(context);
                  // 管理者としてチャット画面を開く
                  // FirestoreからappealIdを探す処理は画面側でやるか、あるいはクエリパラメータでuserIdを渡す
                  // BanAppealScreenは appealId を受け取るが、なければ userId から検索するロジック（_findExistingAppeal）が入っている
                  // ただし現状の _findExistingAppeal は currentUser を使うため、管理者が見る場合は appealId が必須か、
                  // もしくは BanAppealScreen に targetUserId 引数を追加する必要がある。
                  // 現状の実装： appealId があればそれを開く。なければ currentUser (管理者自身) のチャットを探す（これは間違い）。

                  // 管理者が見るには appealId を特定する必要がある。
                  // ここで特定するのは面倒なので、BanAppealScreen を改修するか、
                  // とりあえず「ユーザーID指定」で開けるようにルートを修正するか...

                  // 簡易策：BanAppealScreen に targetUserId を渡せるようにし、
                  // 管理者の場合は targetUserId で検索するように改修する。
                  // しかしこれは BanAppealScreen の修正も必要。

                  // 管理者として特定のユーザーのチャットを開く
                  context.push(
                    '/ban-appeal',
                    extra: {'targetUserId': user.uid},
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // BAN選択ダイアログ
  void _showBanDialog(BuildContext context, UserModel user, String type) {
    final reasonController = TextEditingController();
    final isPermanent = type == 'permanent';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(isPermanent ? '永久BAN' : '一時BAN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPermanent
                  ? 'このユーザーを永久に停止します。ログインできなくなります。\n180日後にデータが削除されます。'
                  : 'このユーザーの機能を制限します。\nプロフィール閲覧と異議申し立てのみ可能になります。',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'BAN理由（必須）',
                border: OutlineInputBorder(),
                hintText: '例: 繰り返しの規約違反行為を確認したため',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;
              Navigator.pop(context);
              await _executeBanAction(user.uid, type, reason);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('実行'),
          ),
        ],
      ),
    );
  }

  // BAN解除ダイアログ
  Future<void> _showUnbanDialog(BuildContext context, UserModel user) async {
    final confirmed = await DialogHelper.showConfirmDialog(
      context: context,
      title: 'BAN解除',
      message: 'このユーザーの制限を解除しますか？',
      confirmText: '解除する',
      barrierDismissible: false,
    );
    if (confirmed == true) {
      await _executeBanAction(user.uid, 'unban', '');
    }
  }

  // Cloud Functions呼び出し
  Future<void> _executeBanAction(String uid, String type, String reason) async {
    setState(() => _isLoading = true);

    try {
      String functionName;
      if (type == 'temporary') {
        functionName = 'banUser';
      } else if (type == 'permanent') {
        functionName = 'permanentBanUser';
      } else {
        functionName = 'unbanUser';
      }

      final data = {'userId': uid};
      if (type != 'unban') {
        data['reason'] = reason;
      }

      await FirebaseFunctions.instanceFor(
        region: 'asia-northeast1',
      ).httpsCallable(functionName).call(data);

      if (mounted) {
        final message = type == 'unban' ? '制限を解除しました' : 'BAN処理を実行しました';
        SnackBarHelper.showSuccess(context, message);
        // 最新状態を再取得
        _loadUser();
      }
    } catch (e) {
      debugPrint('Error executing ban action: $e');
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
        setState(() => _isLoading = false);
      }
    }
  }
}
