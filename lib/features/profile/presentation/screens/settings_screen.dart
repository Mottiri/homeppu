// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/utils/dialog_helper.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/services/inquiry_service.dart';
import '../../../../shared/services/nsfw_detector_service.dart';
import '../../../../shared/services/color_extraction_service.dart';
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
  bool _isUploadingHeader = false;

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

  /// ヘッダー画像を変更
  Future<void> _changeHeaderImage() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    // 画像を選択
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1500,
      maxHeight: 360,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    setState(() => _isUploadingHeader = true);

    try {
      // 1. クライアント側NSFWチェック
      await NsfwDetectorService.instance.initialize();
      final nsfwResult = await NsfwDetectorService.instance.checkImage(
        pickedFile.path,
      );

      if (nsfwResult != null) {
        if (mounted) {
          SnackBarHelper.showError(context, nsfwResult);
        }
        return;
      }

      // 2. Firebase Storageにアップロード
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('headers')
          .child('${user.uid}.jpg');

      final uploadTask = await storageRef.putFile(
        File(pickedFile.path),
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final downloadUrl = await uploadTask.ref.getDownloadURL();

      // 3. 画像から色を抽出
      final colors = await ColorExtractionService.extractColorsFromNetworkImage(
        downloadUrl,
      );

      // 4. Firestoreを更新
      final updateData = <String, dynamic>{
        'headerImageUrl': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (colors != null) {
        updateData['headerPrimaryColor'] = colors['primary'];
        updateData['headerSecondaryColor'] = colors['secondary'];
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update(updateData);

      // ユーザー情報を再取得
      ref.invalidate(currentUserProvider);

      if (mounted) {
        SnackBarHelper.showSuccess(context, 'ヘッダー画像を変更しました！');
      }
    } catch (e) {
      debugPrint('Error uploading header image: $e');
      if (mounted) {
        SnackBarHelper.showError(context, 'ヘッダー画像の変更に失敗しました');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingHeader = false);
      }
    }
  }

  /// ヘッダー画像をリセット（デフォルトに戻す）
  Future<void> _resetHeaderImage() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    final confirmed = await DialogHelper.showConfirmDialog(
      context: context,
      title: 'ヘッダー画像をリセット',
      message: 'ヘッダー画像をデフォルトに戻しますか？',
      confirmText: 'リセット',
    );

    if (confirmed != true) return;

    setState(() => _isUploadingHeader = true);

    try {
      // Storageから画像を削除（存在する場合）
      if (user.headerImageUrl != null) {
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('headers')
              .child('${user.uid}.jpg');
          await storageRef.delete();
        } catch (_) {
          // 削除失敗しても続行
        }
      }

      // Firestoreを更新
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
            'headerImageUrl': FieldValue.delete(),
            'headerPrimaryColor': FieldValue.delete(),
            'headerSecondaryColor': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      // ユーザー情報を再取得
      ref.invalidate(currentUserProvider);

      if (mounted) {
        SnackBarHelper.showSuccess(context, 'ヘッダー画像をリセットしました');
      }
    } catch (e) {
      debugPrint('Error resetting header image: $e');
      if (mounted) {
        SnackBarHelper.showError(context, 'リセットに失敗しました');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingHeader = false);
      }
    }
  }

  // デフォルトヘッダー画像リスト
  static const List<String> _defaultHeaderImages = [
    'assets/images/headers/header_wave_1.png',
    'assets/images/headers/header_wave_2.png',
    'assets/images/headers/header_wave_3.png',
    'assets/images/headers/header_wave_4.png',
    'assets/images/headers/header_wave_5.png',
    'assets/images/headers/header_wave_6.png',
  ];

  // 各デフォルト画像に対応するカラーパレット [primary, secondary]
  static const List<List<int>> _defaultHeaderColors = [
    [0xFF7DD3C0, 0xFFE8A87C], // 1: ティール & コーラル
    [0xFF9B7EDE, 0xFFE890A0], // 2: パープル & ピンク
    [0xFF6CB4EE, 0xFFFFB366], // 3: ブルー & オレンジ
    [0xFF7EC889, 0xFFF9D56E], // 4: グリーン & イエロー
    [0xFFE8A0BF, 0xFFB392AC], // 5: ピンク & パープル
    [0xFF87CEEB, 0xFFDEB887], // 6: スカイブルー & サンド
  ];

  /// デフォルト画像を選択
  Future<void> _selectDefaultHeader(int index) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null || _isUploadingHeader) return;

    setState(() => _isUploadingHeader = true);

    try {
      // カスタム画像があれば削除
      if (user.headerImageUrl != null) {
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('headers')
              .child('${user.uid}.jpg');
          await storageRef.delete();
        } catch (_) {}
      }

      // Firestoreを更新
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
            'headerImageUrl': FieldValue.delete(),
            'headerImageIndex': index,
            'headerPrimaryColor': _defaultHeaderColors[index][0],
            'headerSecondaryColor': _defaultHeaderColors[index][1],
            'updatedAt': FieldValue.serverTimestamp(),
          });

      ref.invalidate(currentUserProvider);

      if (mounted) {
        SnackBarHelper.showSuccess(context, 'ヘッダー画像を変更しました！');
      }
    } catch (e) {
      debugPrint('Error selecting default header: $e');
      if (mounted) {
        SnackBarHelper.showError(context, '変更に失敗しました');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingHeader = false);
      }
    }
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
        SnackBarHelper.showSuccess(context, '保存できたよ！');
        setState(() => _hasChanges = false);
      }
    } catch (e) {
      debugPrint('Error saving changes: $e');
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await DialogHelper.showLogoutConfirmDialog(context);
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

                    // ヘッダー画像
                    Text(
                      'ヘッダー画像',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Consumer(
                      builder: (context, ref, _) {
                        final user = ref.watch(currentUserProvider).valueOrNull;
                        final hasCustomHeader = user?.headerImageUrl != null;

                        return Column(
                          children: [
                            // プレビュー（カスタム画像の場合は×ボタン付き）
                            Stack(
                              children: [
                                Container(
                                  height: 100,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: hasCustomHeader
                                      ? Image.network(
                                          user!.headerImageUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                              Container(
                                                color: AppColors.primaryLight,
                                                child: const Center(
                                                  child: Icon(
                                                    Icons.image,
                                                    size: 40,
                                                    color: AppColors.primary,
                                                  ),
                                                ),
                                              ),
                                        )
                                      : Container(
                                          color: AppColors.primaryLight
                                              .withValues(alpha: 0.3),
                                          child: const Center(
                                            child: Text(
                                              'デフォルト画像',
                                              style: TextStyle(
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                                // カスタム画像の場合は×ボタン表示
                                if (hasCustomHeader)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: _isUploadingHeader
                                          ? null
                                          : _resetHeaderImage,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.6,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // 変更ボタンのみ
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isUploadingHeader
                                    ? null
                                    : _changeHeaderImage,
                                icon: _isUploadingHeader
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.image),
                                label: Text(
                                  _isUploadingHeader ? '処理中...' : '画像を変更',
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // デフォルト画像から選択
                            Text(
                              'またはデフォルトから選択',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 60,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _defaultHeaderImages.length,
                                itemBuilder: (context, index) {
                                  final isSelected =
                                      !hasCustomHeader &&
                                      (user?.headerImageIndex ?? 0) == index;
                                  return Padding(
                                    padding: EdgeInsets.only(
                                      right:
                                          index <
                                              _defaultHeaderImages.length - 1
                                          ? 8
                                          : 0,
                                    ),
                                    child: GestureDetector(
                                      onTap: () => _selectDefaultHeader(index),
                                      child: Container(
                                        width: 100,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: isSelected
                                              ? Border.all(
                                                  color: AppColors.primary,
                                                  width: 2,
                                                )
                                              : null,
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            Image.asset(
                                              _defaultHeaderImages[index],
                                              fit: BoxFit.cover,
                                            ),
                                            if (isSelected)
                                              Container(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.3),
                                                child: const Icon(
                                                  Icons.check_circle,
                                                  color: Colors.white,
                                                  size: 24,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
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
                                  final confirmed =
                                      await DialogHelper.showConfirmDialog(
                                        context: context,
                                        title: '${mode.label}に変更',
                                        message:
                                            '公開範囲を「${mode.label}」に変更しますか？\n\n'
                                            '次回以降の投稿から適用されます。',
                                        confirmText: '変更する',
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
                                      SnackBarHelper.showSuccess(
                                        context,
                                        '公開範囲を「${mode.label}」に変更しました',
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

            const SizedBox(height: 32),

            // バージョン情報
            Center(
              child: Text(
                'Version 1.0.0',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

            const SizedBox(height: 100),

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
