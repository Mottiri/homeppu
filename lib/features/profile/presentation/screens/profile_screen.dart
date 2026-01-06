import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
import '../../../admin/presentation/widgets/admin_menu_bottom_sheet.dart';
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
                                    if (!isAdmin)
                                      return const SizedBox.shrink();
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

                // 統計情報（シンプルな区切り線のみ）
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
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
                                    label: const Text('管理者へ問い合わせる'),
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
                  accentColor: _primaryAccent,
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
  void _showUnbanDialog(BuildContext context, UserModel user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('BAN解除'),
        content: const Text('このユーザーの制限を解除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _executeBanAction(user.uid, 'unban', '');
            },
            child: const Text('解除する'),
          ),
        ],
      ),
    );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(type == 'unban' ? '制限を解除しました' : 'BAN処理を実行しました'),
          ),
        );
        // 最新状態を再取得
        _loadUser();
      }
    } catch (e) {
      debugPrint('Error executing ban action: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラーが発生しました: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }
}

/// ユーザーの投稿一覧（プル更新方式）
class _UserPostsList extends StatefulWidget {
  final String userId;
  final bool isMyProfile;
  final bool viewerIsAI;
  final Color accentColor;

  const _UserPostsList({
    super.key,
    required this.userId,
    this.isMyProfile = false,
    this.viewerIsAI = false,
    this.accentColor = AppColors.primary,
  });

  @override
  State<_UserPostsList> createState() => _UserPostsListState();
}

class _UserPostsListState extends State<_UserPostsList>
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

    final hasMore = _currentTab == 2 ? _favoriteHasMore : _hasMore;
    final isLoadingMore = _currentTab == 2
        ? _favoriteIsLoadingMore
        : _isLoadingMore;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
        return _ProfilePostCard(
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
