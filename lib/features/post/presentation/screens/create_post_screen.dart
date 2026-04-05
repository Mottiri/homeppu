import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/models/post_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/moderation_provider.dart';
import '../../../../shared/providers/tutorial_phase4_provider.dart';
import '../../../../shared/services/media_service.dart';
import '../../../../shared/services/moderation_service.dart';
import '../../../../shared/services/nsfw_detector_service.dart';
import '../../../../shared/services/interstitial_ad_service.dart';
import '../../../../shared/services/post_ad_policy_service.dart';
import '../../../../shared/widgets/tutorial_overlay.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/widgets/report_dialog.dart';
import '../../../../shared/widgets/ad_banner.dart';
import '../widgets/waiting_character_overlay.dart';

/// 投稿作成画面
class CreatePostScreen extends ConsumerStatefulWidget {
  final String? circleId; // サークルへの投稿の場合はcircleIdを受け取る

  const CreatePostScreen({super.key, this.circleId});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _contentController = TextEditingController();
  final _mediaService = MediaService();
  final _postAdPolicyService = PostAdPolicyService();
  final _uuid = const Uuid();
  final ValueNotifier<bool> _waitingCharacterVisible = ValueNotifier<bool>(
    false,
  );
  final GlobalKey _tutorialOverlayStackKey = GlobalKey();
  final GlobalKey _postButtonKey = GlobalKey();
  bool _isLoading = false;
  bool _isUploading = false;
  double _uploadProgress = 0;
  bool _phase4Initialized = false;
  Rect? _phase4SpotlightRect;
  String? _pendingPostRequestId;
  List<MediaItem> _pendingUploadedMedia = [];

  // 選択されたメディア
  final List<_SelectedMedia> _selectedMedia = [];

  bool get _hasPendingPostRetry => _pendingPostRequestId != null;

  @override
  void initState() {
    super.initState();
    InterstitialAdService.instance.preload();
  }

  @override
  void dispose() {
    _waitingCharacterVisible.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _startWaitingCharacter() {
    FocusScope.of(context).unfocus();
    _waitingCharacterVisible.value = true;
  }

  void _stopWaitingCharacter() {
    _waitingCharacterVisible.value = false;
  }

  void _resolvePhase4SpotlightRect() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final rect = await resolveRectWithRetry(
        _postButtonKey,
        ancestorKey: _tutorialOverlayStackKey,
      );
      if (!mounted || rect == null) return;
      if (_phase4SpotlightRect != rect) {
        setState(() => _phase4SpotlightRect = rect);
      }
    });
  }

  Widget _buildNoticeItem(BuildContext context, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '•',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.info,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showPostAdNoticeDialog(String userId) async {
    var dontShowAgain = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
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
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // アイコン
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.info_outline,
                          color: AppColors.info,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // タイトル
                      Text(
                        AppMessages.confirm.postAdNoticeTitle,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 本文（箇条書き風）
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildNoticeItem(
                              context,
                              AppMessages.confirm.postAdNoticeReview,
                            ),
                            const SizedBox(height: 6),
                            _buildNoticeItem(
                              context,
                              AppMessages.confirm.postAdNoticeMayShowAd,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // チェックボックス
                      GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            dontShowAgain = !dontShowAgain;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: dontShowAgain,
                                  onChanged: (value) {
                                    setDialogState(() {
                                      dontShowAgain = value ?? false;
                                    });
                                  },
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                AppMessages.label.dontShowAgain,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // OKボタン
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            AppMessages.label.ok,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (dontShowAgain) {
      await _postAdPolicyService.setNoticeSkip(userId, true);
    }
  }

  /// メディア選択メニューを表示
  void _showMediaPicker() {
    if (_selectedMedia.length >= MediaService.maxMediaCount) {
      SnackBarHelper.showWarning(
        context,
        '最大${MediaService.maxMediaCount}つまで添付できます',
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'メディアを追加',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _MediaPickerOption(
                icon: Icons.photo_library,
                label: '写真を選択',
                color: Colors.blue,
                onTap: () {
                  Navigator.pop(context);
                  _pickImages();
                },
              ),
              _MediaPickerOption(
                icon: Icons.camera_alt,
                label: '写真を撮影',
                color: Colors.green,
                onTap: () {
                  Navigator.pop(context);
                  _takePhoto();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 画像を選択
  Future<void> _pickImages() async {
    try {
      final remaining = MediaService.maxMediaCount - _selectedMedia.length;
      final images = await _mediaService.pickImages(maxCount: remaining);

      // NSFWチェック
      final nsfwService = NsfwDetectorService.instance;
      await nsfwService.initialize();

      for (final image in images) {
        final error = await nsfwService.checkImage(image.path);
        if (error != null) {
          _showError(error);
          continue; // この画像はスキップ
        }
        _addMedia(image.path, MediaType.image);
      }
    } catch (e) {
      _showError('画像の選択に失敗しました');
    }
  }

  /// 写真を撮影
  Future<void> _takePhoto() async {
    try {
      final photo = await _mediaService.takePhoto();
      if (photo != null) {
        // NSFWチェック
        final nsfwService = NsfwDetectorService.instance;
        await nsfwService.initialize();

        final error = await nsfwService.checkImage(photo.path);
        if (error != null) {
          _showError(error);
          return;
        }
        _addMedia(photo.path, MediaType.image);
      }
    } catch (e) {
      _showError('撮影に失敗しました');
    }
  }

  /// メディアを追加
  void _addMedia(String path, MediaType type) {
    if (_selectedMedia.length >= MediaService.maxMediaCount) return;

    setState(() {
      _selectedMedia.add(_SelectedMedia(path: path, type: type));
    });
  }

  /// メディアを削除
  void _removeMedia(int index) {
    setState(() {
      _selectedMedia.removeAt(index);
    });
  }

  bool _isAmbiguousPostRequestError(ModerationException error) {
    const ambiguousCodes = {
      'aborted',
      'cancelled',
      'deadline-exceeded',
      'internal',
      'unavailable',
      'unknown',
    };
    return ambiguousCodes.contains(error.code);
  }

  bool _isPostRequestStillProcessing(ModerationException error) {
    return error.code == 'aborted';
  }

  bool _shouldRollbackUploadedMedia(ModerationException error) {
    return !_isAmbiguousPostRequestError(error);
  }

  void _setPendingPostRetry({
    required String clientRequestId,
    required List<MediaItem> uploadedMedia,
  }) {
    _pendingPostRequestId = clientRequestId;
    _pendingUploadedMedia = List<MediaItem>.from(uploadedMedia);
  }

  void _clearPendingPostRetry() {
    _pendingPostRequestId = null;
    _pendingUploadedMedia = [];
  }

  /// エラーを表示
  void _showError(String message) {
    if (mounted) {
      SnackBarHelper.showError(context, message);
    }
  }

  Future<void> _createPost() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final content = _contentController.text.trim();
    if (content.isEmpty &&
        _selectedMedia.isEmpty &&
        _pendingUploadedMedia.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final isRetry = _hasPendingPostRetry;
    final clientRequestId = _pendingPostRequestId ?? _uuid.v4();

    if (!isRetry && kDebugMode) {
      final debugState = await _postAdPolicyService.debugState(user.uid);
      debugPrint(
        '[PostAd] before submit: isSubscriber=${user.isSubscriber} $debugState',
      );
    }

    if (!isRetry &&
        !user.isSubscriber &&
        await _postAdPolicyService.shouldShowNoticeDialog(user.uid) &&
        mounted) {
      await _showPostAdNoticeDialog(user.uid);
    }

    final shouldTryPostAd =
        !isRetry &&
        !user.isSubscriber &&
        await _postAdPolicyService.shouldShowAdOnThisPost(user.uid);
    if (kDebugMode) {
      debugPrint('[PostAd] shouldTryPostAd=$shouldTryPostAd');
    }
    if (!shouldTryPostAd) {
      _startWaitingCharacter();
    }

    ModerationException? moderationError;
    String? generalErrorMessage;
    var postCreated = false;
    var createPostRequested = false;
    final uploadedMedia = List<MediaItem>.from(_pendingUploadedMedia);
    Future<bool>? adFuture;

    try {
      if (!isRetry && _selectedMedia.isNotEmpty) {
        setState(() {
          _isUploading = true;
          _uploadProgress = 0;
        });

        for (int i = 0; i < _selectedMedia.length; i++) {
          final media = _selectedMedia[i];
          final item = await _mediaService.uploadFile(
            filePath: media.path,
            userId: user.uid,
            type: media.type,
            onProgress: (progress) {
              setState(() {
                _uploadProgress = (i + progress) / _selectedMedia.length;
              });
            },
          );
          uploadedMedia.add(item);
        }

        setState(() => _isUploading = false);
      }

      if (shouldTryPostAd) {
        adFuture = InterstitialAdService.instance.showIfAvailable();
      }

      // モデレーション付き投稿作成（Cloud Functions経由）
      final moderationService = ref.read(moderationServiceProvider);
      createPostRequested = true;
      await moderationService.createPostWithModeration(
        content: content,
        userDisplayName: user.displayName,
        userAvatarIndex: user.avatarIndex,
        postMode: user.postMode,
        mediaItems: uploadedMedia,
        clientRequestId: clientRequestId,
        circleId: widget.circleId, // サークルIDを渡す
      );

      // 徳ポイント状態を更新
      if (kDebugMode) {
        try {
          final status = await ref.refresh(virtueStatusProvider.future);
          debugPrint('[VirtueDebug] Post created. virtue=${status.virtue}');
        } catch (e) {
          debugPrint('[VirtueDebug] Post created but virtue fetch failed: $e');
          ref.invalidate(virtueStatusProvider);
        }
      } else {
        ref.invalidate(virtueStatusProvider);
      }
      postCreated = true;
      _clearPendingPostRetry();
    } on ModerationException catch (e) {
      moderationError = e;
      if (_isAmbiguousPostRequestError(e)) {
        _setPendingPostRetry(
          clientRequestId: clientRequestId,
          uploadedMedia: uploadedMedia,
        );
      } else {
        _clearPendingPostRetry();
      }
      ref.invalidate(virtueStatusProvider);
    } catch (e) {
      debugPrint('Error creating post: $e');
      generalErrorMessage = e.toString().contains('ファイルサイズ')
          ? e.toString().replaceFirst('Exception: ', '')
          : AppMessages.error.general;
      _clearPendingPostRetry();
    }

    if (adFuture != null) {
      try {
        final adShown = await adFuture;
        if (adShown) {
          await _postAdPolicyService.markAdShown(user.uid);
        }
        if (kDebugMode) {
          final debugState = await _postAdPolicyService.debugState(user.uid);
          debugPrint('[PostAd] adShown=$adShown $debugState');
        }
      } catch (e) {
        debugPrint('Error awaiting post interstitial ad: $e');
      }
      InterstitialAdService.instance.preload();
    }

    if (!postCreated && uploadedMedia.isNotEmpty) {
      final shouldRollback =
          !createPostRequested ||
          (moderationError != null &&
              _shouldRollbackUploadedMedia(moderationError));
      if (shouldRollback) {
        await _mediaService.rollbackUploadedMediaItems(uploadedMedia);
      } else if (kDebugMode) {
        debugPrint(
          '[CreatePost] Skip immediate rollback due to ambiguous post creation failure.',
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isUploading = false;
    });
    _stopWaitingCharacter();

    if (postCreated) {
      SnackBarHelper.showSuccess(context, AppMessages.success.postCreated);
      context.pop(true); // 成功を返す（ホーム画面でリロードするため）
      return;
    }

    if (moderationError != null) {
      if (_isPostRequestStillProcessing(moderationError)) {
        SnackBarHelper.showWarning(context, AppMessages.error.postResultChecking);
        return;
      }
      if (_isAmbiguousPostRequestError(moderationError)) {
        SnackBarHelper.showWarning(context, AppMessages.error.postResultUnknown);
        return;
      }
      if (moderationError.code == 'resource-exhausted' ||
          moderationError.code == 'permission-denied' ||
          moderationError.code == 'not-found') {
        SnackBarHelper.showError(context, moderationError.message);
        return;
      }
      final isShortWindowRateLimit =
          moderationError.code == 'resource-exhausted' &&
          moderationError.message.contains('短時間での投稿が多すぎます');
      if (isShortWindowRateLimit) {
        SnackBarHelper.showError(context, moderationError.message);
        return;
      }
      await NegativeContentDialog.show(
        context: context,
        message: moderationError.message,
      );
      return;
    }

    if (generalErrorMessage != null) {
      SnackBarHelper.showError(context, generalErrorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final tutorialPhase4Step = ref.watch(tutorialPhase4Provider);
    final shouldRunPhase4 = widget.circleId == null && user != null;
    final isPhase4Active =
        shouldRunPhase4 && tutorialPhase4Step != TutorialPhase4Step.inactive;

    if (shouldRunPhase4 && !_phase4Initialized) {
      _phase4Initialized = true;
      final currentUser = user;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(tutorialPhase4Provider.notifier).restoreOrStart(currentUser);
      });
    }

    if (isPhase4Active) {
      _resolvePhase4SpotlightRect();
    }

    final remainingChars =
        AppConstants.maxPostLength - _contentController.text.length;
    final canSubmit =
        _hasPendingPostRetry ||
        _contentController.text.trim().isNotEmpty ||
        _selectedMedia.isNotEmpty;

    // ユーザーのヘッダー色を取得
    final primaryColor = user?.headerPrimaryColor != null
        ? Color(user!.headerPrimaryColor!)
        : AppColors.primary;
    final secondaryColor = user?.headerSecondaryColor != null
        ? Color(user!.headerSecondaryColor!)
        : AppColors.secondary;

    // ユーザーの色でグラデーションを作成
    final userGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        primaryColor.withValues(alpha: 0.25),
        secondaryColor.withValues(alpha: 0.15),
        const Color(0xFFFDF8F3),
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: userGradient),
        child: SafeArea(
          child: Stack(
            key: _tutorialOverlayStackKey,
            children: [
              Column(
                children: [
                  // ヘッダー（閉じるボタン + タイトル + 投稿ボタン）
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                        const Spacer(),
                        Text(
                          widget.circleId != null ? 'サークルに投稿' : '新しい投稿',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          key: _postButtonKey,
                          onPressed: !canSubmit || _isLoading ? null : _createPost,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _hasPendingPostRetry
                                      ? AppMessages.label.retry
                                      : AppMessages.label.postSubmit,
                                ),
                        ),
                      ],
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: _waitingCharacterVisible,
                    builder: (context, waitingVisible, _) {
                      if (_isLoading || waitingVisible) {
                        return const SizedBox.shrink();
                      }
                      return const AdBanner(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                      );
                    },
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ユーザー情報
                          if (user != null)
                            Row(
                              children: [
                                AvatarWidget(
                                  avatarIndex: user.avatarIndex,
                                  avatarParts:
                                      user.profileVisualMode == 'avatar'
                                      ? user.avatarParts
                                      : null,
                                  imageUrl: user.profileVisualMode == 'image'
                                      ? user.profileImageUrl
                                      : null,
                                  size: 48,
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.displayName,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    if (widget.circleId != null)
                                      Text(
                                        'サークルへの投稿',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                  ],
                                ),
                              ],
                            ),

                          const SizedBox(height: 20),

                          if (_hasPendingPostRetry) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.warning.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                AppMessages.error.postRetryReady,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: AppColors.textPrimary,
                                      height: 1.4,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // 投稿入力
                          TextField(
                            controller: _contentController,
                            enabled: !_hasPendingPostRetry && !_isLoading,
                            autofocus: true, // 画面表示時に自動フォーカス
                            maxLines: null,
                            minLines: 6,
                            maxLength: AppConstants.maxPostLength,
                            decoration: const InputDecoration(
                              hintText: '今日あったこと、がんばったこと、\n何でも投稿してみよう✨',
                              border: InputBorder.none,
                              fillColor: Colors.transparent,
                              counterText: '',
                            ),
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(height: 1.6),
                            onChanged: (value) => setState(() {}),
                          ),

                          // アップロード進捗
                          if (_isUploading) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'アップロード中... ${(_uploadProgress * 100).toInt()}%',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: _uploadProgress,
                                      backgroundColor: Colors.white,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // 選択されたメディアのプレビュー
                          if (_selectedMedia.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 120,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _selectedMedia.length,
                                itemBuilder: (context, index) {
                                  final media = _selectedMedia[index];
                                  return _MediaPreview(
                                    media: media,
                                    canRemove:
                                        !_hasPendingPostRetry && !_isLoading,
                                    onRemove: () => _removeMedia(index),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // ボトムバー
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: Row(
                        children: [
                          // メディア追加ボタン
                          IconButton(
                            onPressed:
                                (_isLoading || _hasPendingPostRetry)
                                    ? null
                                    : _showMediaPicker,
                            icon: Badge(
                              isLabelVisible: _selectedMedia.isNotEmpty,
                              label: Text('${_selectedMedia.length}'),
                              child: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                            ),
                            color: _selectedMedia.isNotEmpty
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                          const Spacer(),
                          // 文字数
                          Text(
                            '$remainingChars',
                            style: TextStyle(
                              color: remainingChars < 20
                                  ? AppColors.warning
                                  : AppColors.textHint,
                              fontWeight: remainingChars < 20
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (isPhase4Active)
                Positioned.fill(
                  child: TutorialOverlay(
                    message: switch (tutorialPhase4Step) {
                      TutorialPhase4Step.postButtonGuide =>
                        AppMessages.tutorial.postCreateStep1,
                      TutorialPhase4Step.moderationDelayGuide =>
                        AppMessages.tutorial.postCreateStep2,
                      TutorialPhase4Step.aiMisjudgeGuide =>
                        AppMessages.tutorial.postCreateStep3,
                      TutorialPhase4Step.inactive => '',
                    },
                    spotlightRect: _phase4SpotlightRect,
                    actionLabel:
                        tutorialPhase4Step == TutorialPhase4Step.aiMisjudgeGuide
                        ? AppMessages.label.ok
                        : AppMessages.tutorial.nextAction,
                    onAction: () async {
                      final notifier = ref.read(
                        tutorialPhase4Provider.notifier,
                      );
                      if (tutorialPhase4Step ==
                          TutorialPhase4Step.aiMisjudgeGuide) {
                        await notifier.markCompleted();
                      } else {
                        await notifier.advance();
                      }
                    },
                  ),
                ),
              ValueListenableBuilder<bool>(
                valueListenable: _waitingCharacterVisible,
                builder: (context, visible, child) {
                  if (!visible) return const SizedBox.shrink();
                  return child!;
                },
                child: const Positioned.fill(child: WaitingCharacterOverlay()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedMedia {
  final String path;
  final MediaType type;

  _SelectedMedia({required this.path, required this.type});
}

/// メディア選択オプション
class _MediaPickerOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MediaPickerOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(label),
      onTap: onTap,
    );
  }
}

/// メディアプレビュー
class _MediaPreview extends StatelessWidget {
  final _SelectedMedia media;
  final bool canRemove;
  final VoidCallback onRemove;

  const _MediaPreview({
    required this.media,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Stack(
        children: [
          // サムネイル
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: _buildThumbnail(),
          ),
          // 削除ボタン
          if (canRemove)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          // 動画アイコン
          if (media.type == MediaType.video)
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                size: 40,
                color: Colors.white70,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    switch (media.type) {
      case MediaType.image:
        return Image.file(
          File(media.path),
          width: 120,
          height: 120,
          fit: BoxFit.cover,
        );
      case MediaType.video:
        return Container(
          width: 120,
          height: 120,
          color: Colors.black87,
          child: const Center(
            child: Icon(Icons.videocam, size: 40, color: Colors.white54),
          ),
        );
      case MediaType.file:
        return Container(
          width: 120,
          height: 120,
          color: Colors.grey.shade200,
          child: const Center(
            child: Icon(Icons.block, size: 40, color: Colors.grey),
          ),
        );
    }
  }
}
