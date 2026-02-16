// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/utils/dialog_helper.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/models/avatar_parts_model.dart';
import '../../../../core/constants/avatar_assets.dart';
import '../../../../shared/widgets/avatar_parts_widget.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/services/inquiry_service.dart';
import '../../../../shared/services/nsfw_detector_service.dart';
import '../../../../shared/services/color_extraction_service.dart';
import '../../../../shared/services/image_moderation_service.dart';
import '../../../../shared/providers/tutorial_phase1_provider.dart';
import '../../../../shared/widgets/tutorial_overlay.dart';
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

enum ProfileVisualMode {
  icon('icon'),
  avatar('avatar'),
  image('image');

  const ProfileVisualMode(this.value);
  final String value;
}

/// 設定画面
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final ScrollController _settingsScrollController = ScrollController();
  final _bioController = TextEditingController();
  int _selectedAvatarIndex = 0;
  AvatarParts? _avatarParts;
  bool _avatarPartsDirty = false;
  ProfileVisualMode _profileVisualMode = ProfileVisualMode.icon;
  File? _profileImageFile;
  String? _profileImageUrl;
  bool _isLoading = false;
  bool _hasChanges = false;
  bool _isUploadingHeader = false;
  bool _isUploadingProfileImage = false;
  bool _isCompletingPhase1Tutorial = false;
  bool _isFinishedTutorialOverlayDismissed = false;
  bool _didAutoScrollToPrivacy = false;
  int _privacyCardResolveRetryCount = 0;
  TutorialPhase1Step? _lastTutorialStep;
  PrivacyMode _tutorialSelectedMode = PrivacyMode.ai;
  bool _isPrivacyExpandedForTutorial = false;
  int _privacyTileVersion = 0;
  final GlobalKey _tutorialOverlayStackKey = GlobalKey();
  final GlobalKey _privacyCardKey = GlobalKey();
  final GlobalKey _privacyOptionAiKey = GlobalKey();
  final GlobalKey _privacyOptionMixKey = GlobalKey();
  final GlobalKey _privacyOptionHumanKey = GlobalKey();
  Rect? _tutorialSpotlightRect;

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
      _avatarParts = user.avatarParts ?? AvatarAssets.defaultParts();
      _avatarPartsDirty = false;
      _profileVisualMode = _parseProfileVisualMode(user.profileVisualMode);
      _profileImageUrl = user.profileImageUrl;
      _profileImageFile = null;
      _tutorialSelectedMode = PrivacyMode.values.firstWhere(
        (m) => m.value == user.postMode,
        orElse: () => PrivacyMode.ai,
      );
    }
  }

  ProfileVisualMode _parseProfileVisualMode(String raw) {
    switch (raw) {
      case 'avatar':
        return ProfileVisualMode.avatar;
      case 'image':
        return ProfileVisualMode.image;
      default:
        return ProfileVisualMode.icon;
    }
  }

  @override
  void dispose() {
    _settingsScrollController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  /// ヘッダー画像を変更
  Future<void> _changeHeaderImage() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    if (!user.isSubscriber) {
      await _showProfileImageSubscriptionDialog(
        unlockActionLabel: AppMessages.profile.profileHeaderUnlockAction,
      );
      return;
    }

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
        SnackBarHelper.showSuccess(
          context,
          AppMessages.profile.headerChangeSuccess,
        );
      }
    } catch (e) {
      debugPrint('Error uploading header image: $e');
      if (mounted) {
        SnackBarHelper.showError(
          context,
          AppMessages.profile.headerChangeFailed,
        );
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
      title: AppMessages.profile.headerResetTitle,
      message: AppMessages.profile.headerResetMessage,
      confirmText: AppMessages.profile.headerResetConfirm,
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
        SnackBarHelper.showSuccess(
          context,
          AppMessages.profile.headerResetSuccess,
        );
      }
    } catch (e) {
      debugPrint('Error resetting header image: $e');
      if (mounted) {
        SnackBarHelper.showError(
          context,
          AppMessages.profile.headerResetFailed,
        );
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
        SnackBarHelper.showSuccess(
          context,
          AppMessages.profile.headerChangeSuccess,
        );
      }
    } catch (e) {
      debugPrint('Error selecting default header: $e');
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.profile.changeFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingHeader = false);
      }
    }
  }

  Future<void> _onProfileVisualModeSelected(ProfileVisualMode mode) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    final isSubscriber = user?.isSubscriber ?? false;
    if (mode == ProfileVisualMode.image && !isSubscriber) {
      await _showProfileImageSubscriptionDialog();
      return;
    }
    if (_profileVisualMode == mode) return;
    setState(() {
      _profileVisualMode = mode;
      _hasChanges = true;
    });
  }

  Future<void> _showProfileImageSubscriptionDialog({
    String? unlockActionLabel,
  }) async {
    final rootContext = context;
    bool isProcessing = false;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                constraints: const BoxConstraints(maxWidth: 340),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppMessages.profile.profileImageSubscriptionTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppMessages.profile.profileImageSubscriptionMessage,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isProcessing
                            ? null
                            : () {
                                setDialogState(() => isProcessing = true);
                                Navigator.of(dialogContext).pop();
                                Future.microtask(() {
                                  if (!rootContext.mounted) return;
                                  rootContext.push('/premium');
                                });
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.virtue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                unlockActionLabel ??
                                    AppMessages
                                        .profile
                                        .profileImageUnlockAction,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: isProcessing
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                      child: Text(
                        AppMessages.label.cancel,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickProfileImage() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null || _isUploadingProfileImage) return;
    if (!user.isSubscriber) {
      await _showProfileImageSubscriptionDialog();
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (pickedFile == null) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 85,
      maxWidth: 512,
      maxHeight: 512,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: AppMessages.profile.profileImageCropTitle,
          toolbarColor: AppColors.primary,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: AppMessages.profile.profileImageCropTitle,
          aspectRatioLockEnabled: true,
        ),
      ],
    );
    if (cropped == null) return;

    setState(() {
      _profileVisualMode = ProfileVisualMode.image;
      _profileImageFile = File(cropped.path);
      _hasChanges = true;
    });
  }

  Future<Map<String, String>> _uploadProfileImage({
    required String uid,
    required File imageFile,
  }) async {
    final extension = imageFile.path.split('.').last.toLowerCase();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$extension';
    final storagePath = 'users/$uid/profile/$fileName';
    final storageRef = FirebaseStorage.instance.ref().child(storagePath);
    final contentType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };

    final uploadTask = await storageRef.putFile(
      imageFile,
      SettableMetadata(contentType: contentType),
    );
    final downloadUrl = await uploadTask.ref.getDownloadURL();
    return {'url': downloadUrl, 'path': storagePath};
  }

  Future<void> _deleteProfileImageFile({
    String? storagePath,
    String? downloadUrl,
  }) async {
    try {
      if (storagePath != null && storagePath.isNotEmpty) {
        await FirebaseStorage.instance.ref().child(storagePath).delete();
        return;
      }
      if (downloadUrl != null && downloadUrl.isNotEmpty) {
        await FirebaseStorage.instance.refFromURL(downloadUrl).delete();
      }
    } catch (_) {
      // 削除失敗は保存処理を止めない
    }
  }

  Future<void> _saveChanges() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isLoading = true);

    String? uploadedImagePathForRollback;
    String? uploadedImageUrlForRollback;
    try {
      final authService = ref.read(authServiceProvider);
      final previousMode = user.profileVisualMode;
      final previousImageUrl = user.profileImageUrl;
      final previousImagePath = user.profileImageStoragePath;
      var nextImageUrl = previousImageUrl;
      var nextImagePath = previousImagePath;

      if (_profileVisualMode == ProfileVisualMode.image) {
        if (_profileImageFile != null) {
          setState(() => _isUploadingProfileImage = true);
          final moderationService = ImageModerationService();
          final moderationError = await moderationService.moderateImage(
            _profileImageFile!,
          );
          if (moderationError != null) {
            if (mounted) {
              SnackBarHelper.showError(context, moderationError);
            }
            return;
          }

          final uploaded = await _uploadProfileImage(
            uid: user.uid,
            imageFile: _profileImageFile!,
          );
          nextImageUrl = uploaded['url'];
          nextImagePath = uploaded['path'];
          uploadedImagePathForRollback = nextImagePath;
          uploadedImageUrlForRollback = nextImageUrl;
        }

        if (nextImageUrl == null || nextImageUrl.isEmpty) {
          if (mounted) {
            SnackBarHelper.showError(
              context,
              AppMessages.profile.profileImageRequired,
            );
          }
          return;
        }
      } else {
        nextImageUrl = null;
        nextImagePath = null;
      }

      final profileExtraUpdates = <String, dynamic>{
        'profileVisualMode': _profileVisualMode.value,
      };
      if (nextImageUrl != null && nextImageUrl.isNotEmpty) {
        profileExtraUpdates['profileImageUrl'] = nextImageUrl;
      } else {
        profileExtraUpdates['profileImageUrl'] = FieldValue.delete();
      }
      if (nextImagePath != null && nextImagePath.isNotEmpty) {
        profileExtraUpdates['profileImageStoragePath'] = nextImagePath;
      } else {
        profileExtraUpdates['profileImageStoragePath'] = FieldValue.delete();
      }

      // 名前は名前パーツ方式で変更するので、ここでは更新しない
      await authService.updateUserProfile(
        uid: user.uid,
        displayName: user.displayName, // 現在の名前を維持
        bio: _bioController.text.trim(),
        avatarIndex: _selectedAvatarIndex,
        avatarParts: _avatarPartsDirty ? _avatarParts : null,
        extraUpdates: profileExtraUpdates,
      );

      final movedFromImageToOther =
          previousMode == ProfileVisualMode.image.value &&
          _profileVisualMode != ProfileVisualMode.image;
      final replacedImage =
          previousImagePath != null &&
          previousImagePath.isNotEmpty &&
          nextImagePath != null &&
          nextImagePath.isNotEmpty &&
          previousImagePath != nextImagePath;

      if (movedFromImageToOther || replacedImage) {
        await _deleteProfileImageFile(
          storagePath: previousImagePath,
          downloadUrl: previousImageUrl,
        );
      }

      if (mounted) {
        SnackBarHelper.showSuccess(context, AppMessages.profile.savedFriendly);
        ref.invalidate(currentUserProvider);
        setState(() {
          _profileImageUrl = nextImageUrl;
          _profileImageFile = null;
          _isUploadingProfileImage = false;
          _hasChanges = false;
        });
      }
    } catch (e) {
      debugPrint('Error saving changes: $e');
      await _deleteProfileImageFile(
        storagePath: uploadedImagePathForRollback,
        downloadUrl: uploadedImageUrlForRollback,
      );
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isUploadingProfileImage = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await DialogHelper.showLogoutConfirmDialog(context);
    if (confirmed == true) {
      await ref.read(authServiceProvider).signOut();
    }
  }

  Future<void> _completePhase1Tutorial() async {
    if (_isCompletingPhase1Tutorial) return;
    setState(() => _isCompletingPhase1Tutorial = true);
    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      if (user != null) {
        final authService = ref.read(authServiceProvider);
        await authService.updateUserProfile(
          uid: user.uid,
          postMode: _tutorialSelectedMode.value,
        );
      }
      await ref.read(tutorialPhase1Provider.notifier).advance();
      if (!mounted) return;
      context.go('/home');
    } catch (_) {
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
        setState(() => _isCompletingPhase1Tutorial = false);
      }
    }
  }

  void _maybeAutoScrollToPrivacyCard() {
    if (_didAutoScrollToPrivacy) return;
    debugPrint(
      '[TUTORIAL_SCROLL] schedule auto-scroll '
      'didAuto=$_didAutoScrollToPrivacy retry=$_privacyCardResolveRetryCount',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _didAutoScrollToPrivacy) return;
      final targetContext = _privacyCardKey.currentContext;
      if (targetContext == null) {
        debugPrint(
          '[TUTORIAL_SCROLL] target context not ready '
          'retry=$_privacyCardResolveRetryCount/12',
        );
        if (_privacyCardResolveRetryCount < 12) {
          _privacyCardResolveRetryCount++;
          await Future.delayed(const Duration(milliseconds: 120));
          if (mounted) setState(() {});
        }
        return;
      }
      debugPrint('[TUTORIAL_SCROLL] target context resolved');
      _didAutoScrollToPrivacy = true;
      try {
        debugPrint(
          '[TUTORIAL_SCROLL] ensureVisible start '
          'offset=${_settingsScrollController.hasClients ? _settingsScrollController.offset.toStringAsFixed(1) : 'n/a'}',
        );
      } catch (_) {
        debugPrint('[TUTORIAL_SCROLL] ensureVisible start offset=unavailable');
      }
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
      try {
        debugPrint(
          '[TUTORIAL_SCROLL] ensureVisible done '
          'offset=${_settingsScrollController.hasClients ? _settingsScrollController.offset.toStringAsFixed(1) : 'n/a'}',
        );
      } catch (_) {
        debugPrint('[TUTORIAL_SCROLL] ensureVisible done offset=unavailable');
      }
      await _resolveSpotlightRectForStep(ref.read(tutorialPhase1Provider));
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _resolveSpotlightRectForStep(TutorialPhase1Step step) async {
    GlobalKey targetKey = _privacyCardKey;
    switch (step) {
      case TutorialPhase1Step.explainAI:
        targetKey = _privacyOptionAiKey;
        break;
      case TutorialPhase1Step.explainMix:
        targetKey = _privacyOptionMixKey;
        break;
      case TutorialPhase1Step.explainHuman:
        targetKey = _privacyOptionHumanKey;
        break;
      case TutorialPhase1Step.settingsScroll:
      case TutorialPhase1Step.finished:
        targetKey = _privacyCardKey;
        break;
      default:
        targetKey = _privacyCardKey;
        break;
    }

    final rect = await resolveRectWithRetry(
      targetKey,
      ancestorKey: _tutorialOverlayStackKey,
    );
    debugPrint('[TUTORIAL_SCROLL] resolved rect(step=$step): $rect');
    if (!mounted) return;
    setState(() => _tutorialSpotlightRect = rect);
  }

  void _setTutorialPrivacyExpanded(bool expanded) {
    if (_isPrivacyExpandedForTutorial == expanded) return;
    setState(() {
      _isPrivacyExpandedForTutorial = expanded;
      _privacyTileVersion++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tutorialStep = ref.watch(tutorialPhase1Provider);
    if (_lastTutorialStep != tutorialStep) {
      debugPrint(
        '[TUTORIAL_SCROLL] step changed $_lastTutorialStep -> $tutorialStep',
      );
      _lastTutorialStep = tutorialStep;
      if (tutorialStep == TutorialPhase1Step.settingsScroll) {
        _didAutoScrollToPrivacy = false;
        _privacyCardResolveRetryCount = 0;
        _tutorialSpotlightRect = null;
        _isFinishedTutorialOverlayDismissed = false;
        _setTutorialPrivacyExpanded(false);
        debugPrint('[TUTORIAL_SCROLL] reset auto-scroll state for settingsScroll');
      } else if (tutorialStep == TutorialPhase1Step.explainAI ||
          tutorialStep == TutorialPhase1Step.explainMix ||
          tutorialStep == TutorialPhase1Step.explainHuman ||
          tutorialStep == TutorialPhase1Step.finished) {
        if (tutorialStep != TutorialPhase1Step.finished) {
          _isFinishedTutorialOverlayDismissed = false;
        }
        _setTutorialPrivacyExpanded(true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _resolveSpotlightRectForStep(tutorialStep);
        });
      }
    }
    final isPhase1Tutorial =
        tutorialStep != TutorialPhase1Step.inactive &&
        tutorialStep != TutorialPhase1Step.homeWelcome &&
        tutorialStep != TutorialPhase1Step.profileSettings;
    if (isPhase1Tutorial) {
      _maybeAutoScrollToPrivacyCard();
    }

    // チュートリアルステップに合うメッセージ
    String? tutorialMessage;
    switch (tutorialStep) {
      case TutorialPhase1Step.settingsScroll:
        tutorialMessage = AppMessages.tutorial.scrollToPrivacy;
        break;
      case TutorialPhase1Step.explainAI:
        tutorialMessage = AppMessages.tutorial.explainAI;
        break;
      case TutorialPhase1Step.explainMix:
        tutorialMessage = AppMessages.tutorial.explainMix;
        break;
      case TutorialPhase1Step.explainHuman:
        tutorialMessage = AppMessages.tutorial.explainHuman;
        break;
      case TutorialPhase1Step.finished:
        tutorialMessage = AppMessages.tutorial.complete;
        break;
      default:
        break;
    }

    final page = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !isPhase1Tutorial,
        leading: isPhase1Tutorial
            ? null
            : IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(AppMessages.profile.settingsTitle),
        actions: [
          if (_hasChanges && !isPhase1Tutorial)
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
                  : Text(AppMessages.label.save),
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: Stack(
          key: _tutorialOverlayStackKey,
          children: [
            SingleChildScrollView(
              controller: _settingsScrollController,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // プロフィール編集
                    Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppMessages.profile.profileEditTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 20),

                        Text(
                          AppMessages.profile.profileVisualLabel,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _ProfileVisualModeButton(
                                label: AppMessages.auth.registerIconTab,
                                icon: Icons.emoji_emotions_outlined,
                                isSelected:
                                    _profileVisualMode ==
                                    ProfileVisualMode.icon,
                                onTap: () => _onProfileVisualModeSelected(
                                  ProfileVisualMode.icon,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ProfileVisualModeButton(
                                label: AppMessages.auth.registerAvatarTab,
                                icon: Icons.face_retouching_natural_outlined,
                                isSelected:
                                    _profileVisualMode ==
                                    ProfileVisualMode.avatar,
                                onTap: () => _onProfileVisualModeSelected(
                                  ProfileVisualMode.avatar,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ProfileVisualModeButton(
                                label:
                                    AppMessages.profile.profileImageModeLabel,
                                icon: Icons.image_outlined,
                                isSelected:
                                    _profileVisualMode ==
                                    ProfileVisualMode.image,
                                isLocked:
                                    !(ref
                                            .watch(currentUserProvider)
                                            .valueOrNull
                                            ?.isSubscriber ??
                                        false),
                                onTap: () => _onProfileVisualModeSelected(
                                  ProfileVisualMode.image,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_profileVisualMode == ProfileVisualMode.icon)
                          Center(
                            child: AvatarSelector(
                              selectedIndex: _selectedAvatarIndex,
                              onSelected: (index) {
                                setState(() {
                                  _selectedAvatarIndex = index;
                                  _hasChanges = true;
                                });
                              },
                              size: 96,
                            ),
                          )
                        else if (_profileVisualMode == ProfileVisualMode.avatar)
                          Center(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () async {
                                final result = await context.push<AvatarParts>(
                                  '/avatar-edit',
                                  extra:
                                      _avatarParts ??
                                      AvatarAssets.defaultParts(),
                                );
                                if (!mounted || result == null) return;
                                setState(() {
                                  _avatarParts = result;
                                  _avatarPartsDirty = true;
                                  _hasChanges = true;
                                });
                              },
                              child: Column(
                                children: [
                                  Stack(
                                    children: [
                                      AvatarPartsWidget(
                                        parts:
                                            _avatarParts ??
                                            AvatarAssets.defaultParts(),
                                        size: 96,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: AppColors.primary,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.edit,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    AppMessages.profile.tapToEditAvatar,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: _pickProfileImage,
                                  child: Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.4,
                                        ),
                                      ),
                                      color: AppColors.primaryLight.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: _profileImageFile != null
                                        ? Image.file(
                                            _profileImageFile!,
                                            fit: BoxFit.cover,
                                          )
                                        : (_profileImageUrl != null &&
                                              _profileImageUrl!.isNotEmpty)
                                        ? Image.network(
                                            _profileImageUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    const Icon(
                                                      Icons.person,
                                                      color: AppColors.primary,
                                                      size: 42,
                                                    ),
                                          )
                                        : const Icon(
                                            Icons.add_photo_alternate_outlined,
                                            color: AppColors.primary,
                                            size: 42,
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppMessages.profile.tapToChangeImage,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 24),

                        // ヘッダー画像
                        Text(
                          AppMessages.profile.headerImageLabel,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Consumer(
                          builder: (context, ref, _) {
                            final user = ref
                                .watch(currentUserProvider)
                                .valueOrNull;
                            final hasCustomHeader =
                                user?.headerImageUrl != null;
                            final isSubscriber = user?.isSubscriber ?? false;

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
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => Container(
                                                    color:
                                                        AppColors.primaryLight,
                                                    child: const Center(
                                                      child: Icon(
                                                        Icons.image,
                                                        size: 40,
                                                        color:
                                                            AppColors.primary,
                                                      ),
                                                    ),
                                                  ),
                                            )
                                          : Container(
                                              color: AppColors.primaryLight
                                                  .withValues(alpha: 0.3),
                                              child: Center(
                                                child: Text(
                                                  AppMessages
                                                      .profile
                                                      .defaultHeaderLabel,
                                                  style: TextStyle(
                                                    color:
                                                        AppColors.textSecondary,
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
                                        : (isSubscriber
                                              ? _changeHeaderImage
                                              : () => _showProfileImageSubscriptionDialog(
                                                  unlockActionLabel: AppMessages
                                                      .profile
                                                      .profileHeaderUnlockAction,
                                                )),
                                    icon: _isUploadingHeader
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Icon(
                                            isSubscriber
                                                ? Icons.image
                                                : Icons.lock_outline,
                                          ),
                                    label: Text(
                                      _isUploadingHeader
                                          ? AppMessages.profile.processing
                                          : AppMessages.profile.changeImage,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // デフォルト画像から選択
                                Text(
                                  AppMessages.profile.selectFromDefault,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
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
                                          (user?.headerImageIndex ?? 0) ==
                                              index;
                                      return Padding(
                                        padding: EdgeInsets.only(
                                          right:
                                              index <
                                                  _defaultHeaderImages.length -
                                                      1
                                              ? 8
                                              : 0,
                                        ),
                                        child: GestureDetector(
                                          onTap: () =>
                                              _selectDefaultHeader(index),
                                          child: Container(
                                            width: 100,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(8),
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
                        Text(
                          AppMessages.profile.nameLabel,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
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
                                    color: Theme.of(context).colorScheme.outline
                                        .withValues(alpha: 0.3),
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
                                                AppMessages
                                                    .profile
                                                    .tapToSetName,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            AppMessages.profile.tapToChangeName,
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
                        Text(
                          AppMessages.profile.bioLabel,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _bioController,
                          maxLength: AppConstants.maxBioLength,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: AppMessages.profile.bioHint,
                          ),
                          onChanged: (_) => setState(() => _hasChanges = true),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ?????
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.workspace_premium,
                      color: AppColors.accent,
                    ),
                    title: Text(AppMessages.profile.premiumTitle),
                    subtitle: Text(AppMessages.profile.premiumSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/premium'),
                  ),
                ),

                const SizedBox(height: 16),

                // 通知設定
                Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: Text(AppMessages.profile.notificationSettingsTitle),
                    subtitle: Consumer(
                      builder: (context, ref, _) {
                        final user = ref.watch(currentUserProvider).valueOrNull;
                        final enabledCount =
                            (user?.notificationSettings.values
                                .where((e) => e)
                                .length ??
                            0);
                        return Text(
                          enabledCount == 0
                              ? AppMessages.profile.allOff
                              : AppMessages.profile.customizing,
                        );
                      },
                    ),
                    children: [
                      Consumer(
                        builder: (context, ref, _) {
                          final user = ref
                              .watch(currentUserProvider)
                              .valueOrNull;
                          if (user == null) return const SizedBox.shrink();

                          return Column(
                            children: [
                              SwitchListTile(
                                title: Text(
                                  AppMessages.profile.commentNotificationTitle,
                                ),
                                subtitle: Text(
                                  AppMessages
                                      .profile
                                      .commentNotificationSubtitle,
                                ),
                                secondary: const Icon(
                                  Icons.chat_bubble_outline,
                                ),
                                value:
                                    user.notificationSettings['comments'] ??
                                    true,
                                onChanged: (value) async {
                                  final authService = ref.read(
                                    authServiceProvider,
                                  );
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
                                title: Text(
                                  AppMessages.profile.reactionNotificationTitle,
                                ),
                                subtitle: Text(
                                  AppMessages
                                      .profile
                                      .reactionNotificationSubtitle,
                                ),
                                secondary: const Icon(Icons.favorite_border),
                                value:
                                    user.notificationSettings['reactions'] ??
                                    true,
                                onChanged: (value) async {
                                  final authService = ref.read(
                                    authServiceProvider,
                                  );
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

                // 公開範囲設定
                Card(
                  key: _privacyCardKey,
                  child: ExpansionTile(
                    key: ValueKey('privacyTile-$_privacyTileVersion'),
                    initiallyExpanded: isPhase1Tutorial
                        ? _isPrivacyExpandedForTutorial
                        : false,
                    enabled: !isPhase1Tutorial ||
                        tutorialStep == TutorialPhase1Step.settingsScroll,
                    onExpansionChanged: (expanded) async {
                      if (!isPhase1Tutorial) return;
                      _setTutorialPrivacyExpanded(expanded);
                      if (!expanded) return;
                      await _resolveSpotlightRectForStep(
                        ref.read(tutorialPhase1Provider),
                      );
                      if (ref.read(tutorialPhase1Provider) ==
                          TutorialPhase1Step.settingsScroll) {
                        await ref.read(tutorialPhase1Provider.notifier).advance();
                      }
                    },
                    leading: const Icon(Icons.visibility_outlined),
                    title: Text(AppMessages.profile.privacyTitle),
                    subtitle: Consumer(
                      builder: (context, ref, _) {
                        final user = ref.watch(currentUserProvider).valueOrNull;
                        final currentValue = isPhase1Tutorial
                            ? _tutorialSelectedMode.value
                            : (user?.postMode ?? PrivacyMode.ai.value);
                        final currentMode = PrivacyMode.values.firstWhere(
                          (m) => m.value == currentValue,
                          orElse: () => PrivacyMode.ai,
                        );
                        return Text(
                          AppMessages.profile.privacyCurrent(currentMode.label),
                        );
                      },
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight.withValues(
                              alpha: 0.3,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  AppMessages.profile.privacyInfo,
                                  style: const TextStyle(
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
                            final user = ref
                                .watch(currentUserProvider)
                                .valueOrNull;
                            if (user == null) return const SizedBox.shrink();

                            return Column(
                              children: PrivacyMode.values.map((mode) {
                                final isSelected = isPhase1Tutorial
                                    ? _tutorialSelectedMode == mode
                                    : user.postMode == mode.value;
                                final optionKey = switch (mode) {
                                  PrivacyMode.ai => _privacyOptionAiKey,
                                  PrivacyMode.mix => _privacyOptionMixKey,
                                  PrivacyMode.human => _privacyOptionHumanKey,
                                };
                                return Padding(
                                  key: optionKey,
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _PrivacyOption(
                                    mode: mode,
                                    isSelected: isSelected,
                                    onTap: () async {
                                      if (isPhase1Tutorial) {
                                        final step = ref.read(tutorialPhase1Provider);
                                        if (step != TutorialPhase1Step.finished) {
                                          return;
                                        }
                                        if (!isSelected) {
                                          setState(
                                            () => _tutorialSelectedMode = mode,
                                          );
                                        }
                                        await _completePhase1Tutorial();
                                        return;
                                      }
                                      if (isSelected) return;

                                      // 確認ダイアログ
                                      final confirmed =
                                          await DialogHelper.showConfirmDialog(
                                            context: context,
                                            title: AppMessages.profile
                                                .privacyChangeTitle(mode.label),
                                            message: AppMessages.profile
                                                .privacyChangeMessage(
                                                  mode.label,
                                                ),
                                            confirmText: AppMessages
                                                .profile
                                                .privacyChangeConfirm,
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
                                            AppMessages.profile.privacyChanged(
                                              mode.label,
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
                        title: Text(AppMessages.profile.inquiryTitle),
                        subtitle: Text(AppMessages.profile.inquirySubtitle),
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
                        title: Text(AppMessages.profile.aboutTitle),
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
                        title: Text(AppMessages.profile.helpTitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          // TODO: ヘルプ画面
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(AppMessages.profile.termsTitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          // TODO: 利用規約画面
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: Text(AppMessages.profile.privacyPolicyTitle),
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
                    title: Text(
                      AppMessages.profile.logoutTitle,
                      style: const TextStyle(color: AppColors.error),
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
                  ],
                ),
              ),
            ),
            // チュートリアルオーバーレイ（Step 2-6）
            if (isPhase1Tutorial &&
                tutorialMessage != null &&
                !(tutorialStep == TutorialPhase1Step.finished &&
                    _isFinishedTutorialOverlayDismissed))
              TutorialOverlay(
                message: tutorialMessage,
                spotlightRect: _tutorialSpotlightRect,
                pulseMinScale: 1.0,
                pulseMaxScale: 1.06,
                onMaskTap: () async {
                  final currentStep = ref.read(tutorialPhase1Provider);
                  if (currentStep == TutorialPhase1Step.finished) {
                    if (mounted) {
                      setState(() => _isFinishedTutorialOverlayDismissed = true);
                    }
                    return;
                  }
                  if (currentStep == TutorialPhase1Step.explainAI ||
                      currentStep == TutorialPhase1Step.explainMix ||
                      currentStep == TutorialPhase1Step.explainHuman) {
                    await ref.read(tutorialPhase1Provider.notifier).advance();
                  }
                },
                onSpotlightTap:
                    (tutorialStep == TutorialPhase1Step.settingsScroll ||
                        tutorialStep == TutorialPhase1Step.explainAI ||
                        tutorialStep == TutorialPhase1Step.explainMix ||
                        tutorialStep == TutorialPhase1Step.explainHuman)
                    ? () async {
                        final currentStep = ref.read(tutorialPhase1Provider);
                        if (currentStep == TutorialPhase1Step.settingsScroll) {
                          _setTutorialPrivacyExpanded(true);
                          await _resolveSpotlightRectForStep(currentStep);
                          await ref
                              .read(tutorialPhase1Provider.notifier)
                              .advance();
                          return;
                        }
                        if (currentStep == TutorialPhase1Step.explainAI ||
                            currentStep == TutorialPhase1Step.explainMix ||
                            currentStep == TutorialPhase1Step.explainHuman) {
                          await ref
                              .read(tutorialPhase1Provider.notifier)
                              .advance();
                        }
                      }
                    : null,
                isActionEnabled: !_isCompletingPhase1Tutorial,
              ),
          ],
        ),
      ),
    );
    if (!isPhase1Tutorial) return page;
    return PopScope(canPop: false, child: page);
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

class _ProfileVisualModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool isLocked;
  final VoidCallback onTap;

  const _ProfileVisualModeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.isLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final background = isSelected
        ? AppColors.primary.withValues(alpha: 0.12)
        : AppColors.surfaceVariant;
    final borderColor = isSelected
        ? AppColors.primary
        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2);
    final iconColor = isSelected ? AppColors.primary : AppColors.textSecondary;
    final textColor = isSelected ? AppColors.primary : AppColors.textPrimary;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 18, color: iconColor),
                if (isLocked)
                  Positioned(
                    right: -8,
                    top: -8,
                    child: Icon(
                      Icons.lock,
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: textColor,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
