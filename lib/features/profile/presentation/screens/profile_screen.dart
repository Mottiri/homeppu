import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/utils/dialog_helper.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/follow_service.dart';
import '../../../../shared/widgets/virtue_indicator.dart';
import '../../../../shared/providers/moderation_provider.dart';
import '../../../admin/presentation/widgets/admin_menu_bottom_sheet.dart';
import '../widgets/profile_actions.dart';
import '../widgets/profile_admin_actions.dart';
import '../widgets/profile_header.dart';
import '../widgets/profile_menu.dart';
import '../widgets/profile_posts_list.dart';
import '../widgets/profile_stats.dart';
import '../../../../shared/widgets/infinite_scroll_listener.dart';
import '../../../../shared/widgets/load_more_footer.dart';
import '../../../../shared/providers/tutorial_phase1_provider.dart';
import '../../../../shared/widgets/tutorial_overlay.dart';

/// プロフィール画面のスクロールトップを要求するProvider
final profileScrollToTopProvider = StateProvider<int>((ref) => 0);

/// プロフィール画面
class ProfileScreen extends ConsumerStatefulWidget {
  final String? userId; // nullの場合は自分のプロフィール

  const ProfileScreen({super.key, this.userId});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const double _scrollToTopFabMinOffset = 120;
  static const double _fabShowThreshold = 24;
  static const double _fabHideThreshold = 72;
  UserModel? _targetUser;
  bool _isLoading = true;
  bool _isOwnProfile = false;
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  bool _isAdminViewer = false;
  ProviderSubscription<AsyncValue<bool>>? _adminSubscription;
  final _followService = FollowService();
  final _userPostsListKey = GlobalKey<ProfilePostsListState>();
  final ScrollController _scrollController = ScrollController();
  ProviderSubscription<int>? _profileScrollTopSubscription;
  bool _isScrollable = false;
  bool _showScrollToTopFab = false;
  double _fabScrollAccumulator = 0;
  int _fabScrollDirection = 0; // 1: down, -1: up
  bool _isVirtueLoading = false;
  final GlobalKey _tutorialOverlayStackKey = GlobalKey();
  final GlobalKey _settingsIconKey = GlobalKey();
  Rect? _settingsIconRect;

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
    _isAdminViewer = ref.read(isAdminProvider).valueOrNull ?? false;
    _generateHeaderAndColors();
    _loadUser(forceAdmin: _isAdminViewer);
    _adminSubscription = ref.listenManual<AsyncValue<bool>>(isAdminProvider, (
      previous,
      next,
    ) {
      final isAdmin = next.valueOrNull ?? false;
      if (_isAdminViewer != isAdmin) {
        _isAdminViewer = isAdmin;
        final currentUser = ref.read(currentUserProvider).valueOrNull;
        final isOwn =
            widget.userId == null || widget.userId == currentUser?.uid;
        if (!isOwn) {
          _loadUser(forceAdmin: isAdmin);
        }
      }
    });
    _profileScrollTopSubscription = ref.listenManual<int>(
      profileScrollToTopProvider,
      (previous, next) => _scrollToTop(),
    );
    // 初回レイアウト後にスクロール可能か評価
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollable();
    });
  }

  @override
  void dispose() {
    _adminSubscription?.close();
    _profileScrollTopSubscription?.close();
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

  void _scrollToTop() {
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
        if (_showScrollToTopFab && _fabScrollAccumulator >= _fabHideThreshold) {
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

  Future<void> _openVirtueDialog() async {
    if (_isVirtueLoading) return;
    setState(() => _isVirtueLoading = true);
    try {
      final status = await ref.read(virtueStatusProvider.future);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => VirtueDetailDialog(status: status),
      );
    } catch (e) {
      debugPrint('ProfileScreen: virtue status load failed: $e');
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.network);
      }
    } finally {
      if (mounted) {
        setState(() => _isVirtueLoading = false);
      }
    }
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

  Future<void> _loadUser({bool? forceAdmin}) async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    final isAdmin =
        forceAdmin ?? (ref.read(isAdminProvider).valueOrNull ?? false);
    final collectionName = isAdmin ? 'users' : 'publicUsers';

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
            .collection(collectionName)
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.warmGradient),
          child: const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.warmGradient),
          child: Center(child: Text(AppMessages.error.general)),
        ),
      ),
    );
  }

  Widget _buildProfile(UserModel? user) {
    if (user == null) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          appBar: _isOwnProfile ? null : AppBar(title: const Text('プロフィール')),
          body: Container(
            decoration: const BoxDecoration(gradient: AppColors.warmGradient),
            child: const Center(child: Text('ユーザーが見つからないよ 😢')),
          ),
        ),
      );
    }

    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    final showBanWarning = user.isBanned && (_isOwnProfile || isAdmin);
    Widget? adminAction;
    if (isAdmin) {
      if (_isOwnProfile && widget.userId == null) {
        adminAction = const AdminMenuIcon();
      } else if (!_isOwnProfile) {
        adminAction = IconButton(
          icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
          onPressed: () => _showUserAdminMenu(context, user),
          tooltip: '管理者メニュー',
          style: IconButton.styleFrom(
            backgroundColor: AppColors.error.withValues(alpha: 0.8),
          ),
        );
      }
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.warmGradient),
          child: SafeArea(
            child: Stack(
              key: _tutorialOverlayStackKey,
              children: [
                InfiniteScrollListener(
                  isLoadingMore:
                      _userPostsListKey.currentState?.isLoadingMore ?? false,
                  hasMore: _userPostsListKey.currentState?.hasMore ?? false,
                  onLoadMore: () {
                    _userPostsListKey.currentState?.loadMoreCurrentTab();
                  },
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        // ヘッダー画像 + アバター + 名前
                        ProfileHeader(
                          user: user,
                          isOwnProfile: _isOwnProfile,
                          fallbackHeaderImage: _headerImages[_headerImageIndex],
                          primaryAccent: _primaryAccent,
                          secondaryAccent: _secondaryAccent,
                          onBack: _isOwnProfile ? null : () => context.pop(),
                          onOpenSettings: _isOwnProfile
                              ? () {
                                  // チュートリアル Step 1: 設定画面へ遷移して次のステップへ
                                  final step = ref.read(tutorialPhase1Provider);
                                  if (step ==
                                      TutorialPhase1Step.profileSettings) {
                                    ref
                                        .read(tutorialPhase1Provider.notifier)
                                        .advance();
                                  }
                                  context.push('/settings');
                                }
                              : null,
                          settingsIconKey: _isOwnProfile
                              ? _settingsIconKey
                              : null,
                          adminAction: adminAction,
                        ),

                        // 統計情報（パステルカラー背景）
                        ProfileStats(
                          totalPosts: user.totalPosts,
                          totalPraises: user.totalPraises,
                          virtue: user.virtue,
                          primaryAccent: _primaryAccent,
                          secondaryAccent: _secondaryAccent,
                          isVirtueLoading: _isVirtueLoading,
                          onVirtueTap: _isOwnProfile
                              ? () {
                                  _openVirtueDialog();
                                }
                              : null,
                        ),

                        // フォローボタン（ヘッダーカラー）+ メッセージボタン
                        if (!_isOwnProfile)
                          ProfileActions(
                            isFollowing: _isFollowing,
                            isFollowLoading: _isFollowLoading,
                            primaryAccent: _primaryAccent,
                            secondaryAccent: _secondaryAccent,
                            onToggleFollow: _toggleFollow,
                            onMessage: () {},
                          ),

                        // 管理者のみ: 累計被通報回数
                        ProfileAdminReportBadge(
                          isAdmin: isAdmin,
                          reportCount: user.reportCount,
                        ),

                        // BAN状態の警告
                        ProfileBanWarning(
                          showWarning: showBanWarning,
                          showContactButton: _isOwnProfile,
                          onContact: () => context.push('/ban-appeal'),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 24)),

                        // フォロー中（自分のプロフィールのみ）
                        // 実際のfollowingリストの長さを使用（followingCountとの不整合を防ぐ）
                        if (_isOwnProfile && user.following.isNotEmpty)
                          ProfileMenu(followingIds: user.following),

                        // 過去の投稿
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              '${user.displayName}さんの投稿',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
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
                              ref
                                  .watch(currentUserProvider)
                                  .valueOrNull
                                  ?.isAI ??
                              false,
                          accentColor: _primaryAccent,
                          onLoadComplete: _handlePostsListUpdated,
                        ),

                        // LoadMoreFooter（ショートリスト用手動フォールバック）
                        SliverToBoxAdapter(
                          child: LoadMoreFooter(
                            hasMore:
                                _userPostsListKey.currentState?.hasMore ??
                                false,
                            isLoadingMore:
                                _userPostsListKey.currentState?.isLoadingMore ??
                                false,
                            isInitialLoadComplete: true,
                            canLoadMore:
                                _userPostsListKey.currentState?.canLoadMore ??
                                false,
                            isScrollable: _isScrollable,
                            onLoadMore: () {
                              _userPostsListKey.currentState
                                  ?.loadMoreCurrentTab();
                            },
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
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
                          heroTag: 'profile_scroll_top_fab',
                          onPressed: _scrollToTop,
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          child: const Icon(Icons.keyboard_arrow_up_rounded),
                        ),
                      ),
                    ),
                  ),
                ),
                // チュートリアル Step 1: 設定アイコンをスポットライト
                Builder(
                  builder: (context) {
                    final step = ref.watch(tutorialPhase1Provider);
                    if (step != TutorialPhase1Step.profileSettings) {
                      return const SizedBox.shrink();
                    }
                    // Rect 取得を非同期で行い、stateに反映
                    if (_settingsIconRect == null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        if (!mounted) return;
                        final rect = await resolveRectWithRetry(
                          _settingsIconKey,
                          ancestorKey: _tutorialOverlayStackKey,
                        );
                        if (mounted && rect != null) {
                          setState(() => _settingsIconRect = rect);
                        }
                      });
                    }
                    return TutorialOverlay(
                      message: AppMessages.tutorial.tapSettings,
                      spotlightRect: _settingsIconRect,
                      circularSpotlight: true,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
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
