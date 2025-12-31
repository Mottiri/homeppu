// ignore_for_file: use_build_context_synchronously
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/ai_provider.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/services/name_parts_service.dart';
import '../../../../shared/services/inquiry_service.dart';
import 'name_edit_screen.dart';

/// 公開範囲モード
enum PrivacyMode {
  ai('ai', 'AIモード', 'AIだけが見れるよ\n人間には見えないから安心して投稿できる！', Icons.auto_awesome),
  mix('mix', 'ミックス', 'AIも人間も両方見れるよ\n色んな人からリアクションがもらえる！', Icons.groups),
  human('human', '人間モード', '人間だけが見れるよ\n本物のリアクションだけがほしい人向け', Icons.person);

  const PrivacyMode(this.value, this.label, this.description, this.icon);

  final String value;
  final String label;
  final String description;
  final IconData icon;
}

/// 設定画面
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _bioController = TextEditingController();
  int _selectedAvatarIndex = 0;
  bool _isLoading = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user != null) {
      _bioController.text = user.bio ?? '';
      _selectedAvatarIndex = user.avatarIndex;
    }
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final authService = ref.read(authServiceProvider);
      // 名前は名前パーツ方式で変更するので、ここでは更新しない
      await authService.updateUserProfile(
        uid: user.uid,
        displayName: user.displayName, // 現在の名前を維持
        bio: _bioController.text.trim(),
        avatarIndex: _selectedAvatarIndex,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存できたよ！✨'),
            backgroundColor: AppColors.success,
          ),
        );
        setState(() => _hasChanges = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppConstants.friendlyMessages['error_general']!),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウト'),
        content: Text(AppConstants.friendlyMessages['logout_confirm']!),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('やっぱりやめる'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(authServiceProvider).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('設定'),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _isLoading ? null : _saveChanges,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Text('保存'),
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // プロフィール編集
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'プロフィール編集',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 20),

                    // アバター
                    Center(
                      child: AvatarSelector(
                        selectedIndex: _selectedAvatarIndex,
                        onSelected: (index) {
                          setState(() {
                            _selectedAvatarIndex = index;
                            _hasChanges = true;
                          });
                        },
                        size: 70,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 表示名（名前パーツ方式）
                    Text('なまえ', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Consumer(
                      builder: (context, ref, _) {
                        final currentUser = ref
                            .watch(currentUserProvider)
                            .valueOrNull;
                        return InkWell(
                          onTap: () async {
                            final result = await Navigator.of(context)
                                .push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => const NameEditScreen(),
                                  ),
                                );
                            if (result == true) {
                              // 名前が変更された場合、ユーザー情報を再取得
                              ref.invalidate(currentUserProvider);
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outline.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        currentUser?.displayName ??
                                            'タップして名前を設定',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'タップして名前を変更',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey[600],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // 自己紹介
                    Text('自己紹介', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _bioController,
                      maxLength: AppConstants.maxBioLength,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: '自己紹介を入力（任意）',
                      ),
                      onChanged: (_) => setState(() => _hasChanges = true),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 通知設定
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('通知設定'),
                subtitle: Consumer(
                  builder: (context, ref, _) {
                    final user = ref.watch(currentUserProvider).valueOrNull;
                    final enabledCount =
                        (user?.notificationSettings.values
                            .where((e) => e)
                            .length ??
                        0);
                    return Text(enabledCount == 0 ? 'すべてオフ' : 'カスタマイズ中');
                  },
                ),
                children: [
                  Consumer(
                    builder: (context, ref, _) {
                      final user = ref.watch(currentUserProvider).valueOrNull;
                      if (user == null) return const SizedBox.shrink();

                      return Column(
                        children: [
                          SwitchListTile(
                            title: const Text('コメント通知'),
                            subtitle: const Text('投稿へのコメントを通知します'),
                            secondary: const Icon(Icons.chat_bubble_outline),
                            value:
                                user.notificationSettings['comments'] ?? true,
                            onChanged: (value) async {
                              final authService = ref.read(authServiceProvider);
                              final newSettings = Map<String, bool>.from(
                                user.notificationSettings,
                              );
                              newSettings['comments'] = value;

                              await authService.updateUserProfile(
                                uid: user.uid,
                                notificationSettings: newSettings,
                              );
                            },
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            title: const Text('リアクション通知'),
                            subtitle: const Text('投稿へのリアクションを通知します'),
                            secondary: const Icon(Icons.favorite_border),
                            value:
                                user.notificationSettings['reactions'] ?? true,
                            onChanged: (value) async {
                              final authService = ref.read(authServiceProvider);
                              final newSettings = Map<String, bool>.from(
                                user.notificationSettings,
                              );
                              newSettings['reactions'] = value;

                              await authService.updateUserProfile(
                                uid: user.uid,
                                notificationSettings: newSettings,
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 自動投稿設定
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.celebration_outlined),
                title: const Text('自動投稿設定'),
                subtitle: Consumer(
                  builder: (context, ref, _) {
                    final user = ref.watch(currentUserProvider).valueOrNull;
                    final enabledCount =
                        (user?.autoPostSettings.values.where((e) => e).length ??
                        0);
                    return Text(enabledCount == 0 ? 'すべてオフ' : 'カスタマイズ中');
                  },
                ),
                children: [
                  Consumer(
                    builder: (context, ref, _) {
                      final user = ref.watch(currentUserProvider).valueOrNull;
                      if (user == null) return const SizedBox.shrink();

                      return Column(
                        children: [
                          SwitchListTile(
                            title: const Text('ストリーク達成時'),
                            subtitle: const Text('連続達成（マイルストーン）した時に自動で投稿します'),
                            secondary: const Icon(
                              Icons.local_fire_department_outlined,
                            ),
                            value: user.autoPostSettings['milestones'] ?? true,
                            onChanged: (value) async {
                              final authService = ref.read(authServiceProvider);
                              final newSettings = Map<String, bool>.from(
                                user.autoPostSettings,
                              );
                              newSettings['milestones'] = value;

                              await authService.updateUserProfile(
                                uid: user.uid,
                                autoPostSettings: newSettings,
                              );
                            },
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            title: const Text('目標達成時'),
                            subtitle: const Text('目標を達成した時に自動で投稿します'),
                            secondary: const Icon(Icons.flag_outlined),
                            value: user.autoPostSettings['goals'] ?? true,
                            onChanged: (value) async {
                              final authService = ref.read(authServiceProvider);
                              final newSettings = Map<String, bool>.from(
                                user.autoPostSettings,
                              );
                              newSettings['goals'] = value;

                              await authService.updateUserProfile(
                                uid: user.uid,
                                autoPostSettings: newSettings,
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            // 公開範囲設定
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('公開範囲'),
                subtitle: Consumer(
                  builder: (context, ref, _) {
                    final user = ref.watch(currentUserProvider).valueOrNull;
                    final currentMode = PrivacyMode.values.firstWhere(
                      (m) => m.value == user?.postMode,
                      orElse: () => PrivacyMode.ai,
                    );
                    return Text('現在: ${currentMode.label}');
                  },
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '次回以降の投稿から適用されます\n過去の投稿は変わりません',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Consumer(
                      builder: (context, ref, _) {
                        final user = ref.watch(currentUserProvider).valueOrNull;
                        if (user == null) return const SizedBox.shrink();

                        return Column(
                          children: PrivacyMode.values.map((mode) {
                            final isSelected = user.postMode == mode.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _PrivacyOption(
                                mode: mode,
                                isSelected: isSelected,
                                onTap: () async {
                                  if (isSelected) return;

                                  // 確認ダイアログ
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text('${mode.label}に変更'),
                                      content: Text(
                                        '公開範囲を「${mode.label}」に変更しますか？\n\n'
                                        '次回以降の投稿から適用されます。',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('キャンセル'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('変更する'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirmed == true) {
                                    final authService = ref.read(
                                      authServiceProvider,
                                    );
                                    await authService.updateUserProfile(
                                      uid: user.uid,
                                      postMode: mode.value,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '公開範囲を「${mode.label}」に変更しました',
                                          ),
                                          backgroundColor: AppColors.success,
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // サポート
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.mail_outline,
                      color: AppColors.primary,
                    ),
                    title: const Text('問い合わせ・要望'),
                    subtitle: const Text('バグ報告や機能要望を送信'),
                    trailing: StreamBuilder<int>(
                      stream: InquiryService().getUnreadCount(),
                      builder: (context, snapshot) {
                        final count = snapshot.data ?? 0;
                        if (count == 0) {
                          return const Icon(Icons.chevron_right);
                        }
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right),
                          ],
                        );
                      },
                    ),
                    onTap: () => context.push('/inquiry'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // アプリ情報
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('アプリについて'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: AppConstants.appName,
                        applicationVersion: '1.0.0',
                        children: [
                          const SizedBox(height: 16),
                          Text(
                            AppConstants.appDescription,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('ヘルプ'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // TODO: ヘルプ画面
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('利用規約'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // TODO: 利用規約画面
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('プライバシーポリシー'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // TODO: プライバシーポリシー画面
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ログアウト
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout, color: AppColors.error),
                title: const Text(
                  'ログアウト',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: _logout,
              ),
            ),

            const SizedBox(height: 16),

            const SizedBox(height: 16),

            // 管理者設定（開発用）
            if (ref.watch(currentUserProvider).valueOrNull?.email ==
                'movielike4@gmail.com')
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.admin_panel_settings),
                  title: const Text('管理者設定'),
                  subtitle: const Text(
                    '開発者専用',
                    style: TextStyle(fontSize: 12, color: AppColors.textHint),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                try {
                                  final aiService = ref.read(aiServiceProvider);
                                  await aiService.initializeAIAccounts();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('AIアカウントを作成しました！🤖'),
                                        backgroundColor: AppColors.success,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('エラー: $e'),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.group_add),
                              label: const Text('AIアカウントを初期化'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 問い合わせ管理
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => context.push('/admin/inquiries'),
                              icon: const Icon(Icons.mail_outline),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                              label: const Text('問い合わせ管理'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 通報管理
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => context.push('/admin/reports'),
                              icon: const Icon(Icons.flag_outlined),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.warning,
                                foregroundColor: Colors.white,
                              ),
                              label: const Text('通報管理'),
                            ),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                try {
                                  final aiService = ref.read(aiServiceProvider);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('AI投稿を生成中...（少し時間がかかります）'),
                                      backgroundColor: AppColors.primary,
                                      duration: Duration(seconds: 10),
                                    ),
                                  );
                                  final result = await aiService
                                      .generateAIPosts();
                                  if (mounted) {
                                    ScaffoldMessenger.of(
                                      context,
                                    ).hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'AI投稿を生成しました！📝 ${result['posts']}件の投稿、${result['comments']}件のコメント',
                                        ),
                                        backgroundColor: AppColors.success,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(
                                      context,
                                    ).hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('エラー: $e'),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.auto_awesome),
                              label: const Text('AI過去投稿を生成'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final namePartsService = NamePartsService();
                                try {
                                  await namePartsService.initializeNameParts();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('名前パーツを初期化しました'),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('エラー: $e')),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.abc),
                              label: const Text('名前パーツ初期化'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                try {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'サークルAI投稿を生成中...（少し時間がかかります）',
                                      ),
                                      backgroundColor: AppColors.primary,
                                      duration: Duration(seconds: 30),
                                    ),
                                  );
                                  final functions =
                                      FirebaseFunctions.instanceFor(
                                        region: 'asia-northeast1',
                                      );
                                  final result = await functions
                                      .httpsCallable('triggerCircleAIPosts')
                                      .call();
                                  if (mounted) {
                                    ScaffoldMessenger.of(
                                      context,
                                    ).hideCurrentSnackBar();
                                    final data =
                                        result.data as Map<String, dynamic>?;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'サークルAI投稿を生成しました！🎯 ${data?['totalPosts'] ?? 0}件',
                                        ),
                                        backgroundColor: AppColors.success,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(
                                      context,
                                    ).hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('エラー: $e'),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.groups),
                              label: const Text('サークルAI投稿を生成'),
                            ),
                          ),

                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('本当に削除しますか？'),
                                    content: const Text(
                                      '全てのAIユーザーと、その投稿・コメント・リアクションが完全に削除されます。\nこの操作は取り消せません。',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('キャンセル'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.error,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('全削除実行'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirmed != true) return;

                                try {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'AIユーザーを削除中...（数分かかる場合があります）',
                                        ),
                                        duration: Duration(minutes: 5),
                                      ),
                                    );
                                  }

                                  final aiService = ref.read(aiServiceProvider);
                                  await aiService.deleteAllAIUsers();

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(
                                      context,
                                    ).hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('AIデータの全削除が完了しました！🧹'),
                                        backgroundColor: AppColors.success,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(
                                      context,
                                    ).hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('エラー: $e')),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.delete_forever),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.error,
                                foregroundColor: Colors.white,
                              ),
                              label: const Text('データ全削除（危険）'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            // バージョン情報
            Center(
              child: Text(
                'Version 1.0.0',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

class _PrivacyOption extends StatelessWidget {
  final PrivacyMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  const _PrivacyOption({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryLight.withValues(alpha: 0.5)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                mode.icon,
                size: 22,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mode.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppColors.primary,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}
