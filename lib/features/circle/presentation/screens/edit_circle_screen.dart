// ignore_for_file: deprecated_member_use
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/mixins/loading_state_mixin.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/models/circle_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/circle_service.dart';
import '../../../../shared/services/media_service.dart';
import '../../../../shared/services/image_moderation_service.dart';
import '../../../../shared/widgets/report_dialog.dart';

class EditCircleScreen extends ConsumerStatefulWidget {
  final String circleId;
  final CircleModel circle;

  const EditCircleScreen({
    super.key,
    required this.circleId,
    required this.circle,
  });

  @override
  ConsumerState<EditCircleScreen> createState() => _EditCircleScreenState();
}

class _EditCircleScreenState extends ConsumerState<EditCircleScreen>
    with LoadingStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _goalController;
  late TextEditingController _rulesController;

  late String _selectedCategory;
  late bool _isPublic;

  // 画像設定
  File? _iconImage;
  File? _coverImage;
  String? _iconImageUrl;
  String? _iconImageStoragePath;
  String? _coverImageUrl;
  String? _coverImageStoragePath;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.circle.name);
    _descriptionController = TextEditingController(
      text: widget.circle.description,
    );
    _goalController = TextEditingController(text: widget.circle.goal);
    _rulesController = TextEditingController(text: widget.circle.rules ?? '');
    _selectedCategory = widget.circle.category;
    _isPublic = widget.circle.isPublic;
    _iconImageUrl = widget.circle.iconImageUrl;
    _iconImageStoragePath = widget.circle.iconImageStoragePath;
    _coverImageUrl = widget.circle.coverImageUrl;
    _coverImageStoragePath = widget.circle.coverImageStoragePath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _goalController.dispose();
    _rulesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool isIcon}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (picked != null) {
      // クロッピング
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: isIcon
            ? const CropAspectRatio(ratioX: 1, ratioY: 1) // アイコンは1:1
            : const CropAspectRatio(ratioX: 16, ratioY: 9), // ヘッダーは16:9
        compressQuality: 85,
        maxWidth: isIcon ? 512 : 1920,
        maxHeight: isIcon ? 512 : 1080,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: isIcon ? 'アイコンを調整' : 'ヘッダーを調整',
            toolbarColor: AppColors.primary,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: true,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: isIcon ? 'アイコンを調整' : 'ヘッダーを調整',
            aspectRatioLockEnabled: true,
          ),
        ],
      );

      if (croppedFile != null) {
        setState(() {
          if (isIcon) {
            _iconImage = File(croppedFile.path);
          } else {
            _coverImage = File(croppedFile.path);
          }
        });
      }
    }
  }

  bool _shouldRollbackAfterAttachFailure(Object error) {
    if (error is FirebaseException) {
      const ambiguousCodes = {
        'aborted',
        'cancelled',
        'deadline-exceeded',
        'internal',
        'unavailable',
        'unknown',
      };
      return !ambiguousCodes.contains(error.code);
    }
    return true;
  }

  Future<void> _deletePreviousCircleImage({
    required MediaService mediaService,
    required String pendingType,
    required String ownerId,
    required String circleId,
    required String? previousUrl,
    required String? previousStoragePath,
    required String? nextUrl,
    required String? nextStoragePath,
  }) async {
    final pathChanged = previousStoragePath != nextStoragePath;
    final urlChanged = previousUrl != nextUrl;
    if (!pathChanged && !urlChanged) return;

    final cleanupStoragePath =
        previousStoragePath ??
        (previousUrl != null && previousUrl.isNotEmpty
            ? mediaService.getStoragePathFromUrl(previousUrl)
            : null);

    if (cleanupStoragePath != null && cleanupStoragePath.isNotEmpty) {
      var registeredForCleanup = false;
      try {
        await mediaService.registerPendingMedia(
          type: pendingType,
          ownerId: ownerId,
          storagePath: cleanupStoragePath,
          circleId: circleId,
        );
        registeredForCleanup = true;
      } catch (error, stackTrace) {
        debugPrint('Failed to register previous circle image for cleanup: $error');
        debugPrint('$stackTrace');
      }
      final deleted = await mediaService.deleteMediaByStoragePath(
        cleanupStoragePath,
      );
      if (deleted && registeredForCleanup) {
        await mediaService.resolvePendingMediaByStoragePath(cleanupStoragePath);
      }
      return;
    }
    if (previousUrl != null && previousUrl.isNotEmpty) {
      await mediaService.deleteMedia(previousUrl);
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) return;

    await runWithLoading(() async {
      final uploadedImages = <UploadedStorageItem>[];
      var attachAttempted = false;
      final mediaService = MediaService();
      try {
        final circleService = ref.read(circleServiceProvider);
        final moderationService = ImageModerationService();

        // 新しい画像のモデレーションを先に実行（並列）
        if (_iconImage != null || _coverImage != null) {
          final results = await Future.wait([
            if (_iconImage != null) moderationService.moderateImage(_iconImage!),
            if (_coverImage != null) moderationService.moderateImage(_coverImage!),
          ]);
          for (final error in results) {
            if (error != null) {
              if (mounted) {
                SnackBarHelper.showError(context, error);
              }
              return;
            }
          }
        }

        // テキストフィールド更新（Cloud Functions経由 — テキストモデレーション付き）
        final rulesText = _rulesController.text.trim();
        await circleService.updateCircleWithModeration(
          circleId: widget.circleId,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          category: _selectedCategory,
          goal: _goalController.text.trim(),
          isPublic: _isPublic,
          rules: rulesText.isNotEmpty ? rulesText : null,
        );

        // 画像アップロード — テキスト更新成功後に実行
        final previousIconUrl = _iconImageUrl;
        final previousIconStoragePath = _iconImageStoragePath;
        final previousCoverUrl = _coverImageUrl;
        final previousCoverStoragePath = _coverImageStoragePath;
        String? newIconUrl = _iconImageUrl;
        String? newIconStoragePath = _iconImageStoragePath;
        String? newCoverUrl = _coverImageUrl;
        String? newCoverStoragePath = _coverImageStoragePath;
        bool uploadFailed = false;

        if (_iconImage != null || _coverImage != null) {
          Future<UploadedStorageItem?> uploadCircleImageOrNull({
            required String filePath,
            required String imageType,
          }) async {
            try {
              return await mediaService.uploadCircleImage(
                filePath: filePath,
                circleId: widget.circleId,
                ownerId: currentUser.uid,
                imageType: imageType,
              );
            } catch (e) {
              debugPrint('$imageType upload error: $e');
              return null;
            }
          }

          final iconResult = _iconImage != null
              ? uploadCircleImageOrNull(
                  filePath: _iconImage!.path,
                  imageType: 'icon',
                )
              : Future<UploadedStorageItem?>.value(null);
          final coverResult = _coverImage != null
              ? uploadCircleImageOrNull(
                  filePath: _coverImage!.path,
                  imageType: 'cover',
                )
              : Future<UploadedStorageItem?>.value(null);

          final results = await Future.wait([iconResult, coverResult]);
          final uploadedIcon = results[0];
          final uploadedCover = results[1];
          if (_iconImage != null) {
            newIconUrl = uploadedIcon?.downloadUrl ?? _iconImageUrl;
            newIconStoragePath =
                uploadedIcon?.storagePath ?? _iconImageStoragePath;
          }
          if (_coverImage != null) {
            newCoverUrl = uploadedCover?.downloadUrl ?? _coverImageUrl;
            newCoverStoragePath =
                uploadedCover?.storagePath ?? _coverImageStoragePath;
          }

          if (uploadedIcon != null) {
            uploadedImages.add(uploadedIcon);
          }
          if (uploadedCover != null) {
            uploadedImages.add(uploadedCover);
          }

          if ((_iconImage != null && uploadedIcon == null) ||
              (_coverImage != null && uploadedCover == null)) {
            uploadFailed = true;
          }
        }

        // 画像URLを更新（Firestore直接）
        attachAttempted = true;
        await circleService.updateCircle(widget.circleId, {
          'iconImageUrl': newIconUrl,
          'iconImageStoragePath': newIconStoragePath,
          'coverImageUrl': newCoverUrl,
          'coverImageStoragePath': newCoverStoragePath,
        });
        await mediaService.resolvePendingStorageItems(uploadedImages);
        await _deletePreviousCircleImage(
          mediaService: mediaService,
          pendingType: 'circle_icon',
          ownerId: currentUser.uid,
          circleId: widget.circleId,
          previousUrl: previousIconUrl,
          previousStoragePath: previousIconStoragePath,
          nextUrl: newIconUrl,
          nextStoragePath: newIconStoragePath,
        );
        await _deletePreviousCircleImage(
          mediaService: mediaService,
          pendingType: 'circle_cover',
          ownerId: currentUser.uid,
          circleId: widget.circleId,
          previousUrl: previousCoverUrl,
          previousStoragePath: previousCoverStoragePath,
          nextUrl: newCoverUrl,
          nextStoragePath: newCoverStoragePath,
        );

        if (mounted) {
          if (uploadFailed) {
            SnackBarHelper.showWarning(
              context,
              AppMessages.circle.imageUploadFailedButUpdated,
            );
          } else {
            SnackBarHelper.showSuccess(context, AppMessages.success.circleUpdated);
          }
          context.pop();
        }
      } catch (e) {
        if (uploadedImages.isNotEmpty &&
            (!attachAttempted || _shouldRollbackAfterAttachFailure(e))) {
          await mediaService.rollbackUploadedStorageItems(uploadedImages);
        }
        if (mounted) {
          if (e is FirebaseFunctionsException) {
            if (e.code == 'invalid-argument' && e.message != null && e.message!.isNotEmpty) {
              final msg = e.message!;
              if (msg.contains('提案:') || msg.contains('NGワード')) {
                await NegativeContentDialog.show(
                  context: context,
                  message: msg,
                );
              } else {
                SnackBarHelper.showError(context, msg);
              }
            } else {
              SnackBarHelper.showError(context, AppMessages.error.general);
            }
          } else {
            SnackBarHelper.showError(context, AppMessages.error.general);
          }
          debugPrint('Circle update failed: $e');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = CircleService.categories
        .where((c) => c != '全て')
        .toList();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('サークル編集'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: isLoading ? null : _saveChanges,
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '保存',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // アイコン・ヘッダー画像
            _buildSection(
              title: 'サークル画像',
              subtitle: 'アイコンとヘッダーをカスタマイズ（任意）',
              child: Row(
                children: [
                  // アイコン
                  Column(
                    children: [
                      Stack(
                        children: [
                          GestureDetector(
                            onTap: () => _pickImage(isIcon: true),
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey[200],
                                border: Border.all(color: Colors.grey[300]!),
                                image: _iconImage != null
                                    ? DecorationImage(
                                        image: FileImage(_iconImage!),
                                        fit: BoxFit.cover,
                                      )
                                    : _iconImageUrl != null
                                    ? DecorationImage(
                                        image: NetworkImage(_iconImageUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: _iconImage == null && _iconImageUrl == null
                                  ? Icon(
                                      Icons.camera_alt,
                                      color: Colors.grey[400],
                                    )
                                  : null,
                            ),
                          ),
                          // 削除ボタン
                          if (_iconImage != null || _iconImageUrl != null)
                            Positioned(
                              top: -4,
                              right: -4,
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _iconImage = null;
                                  _iconImageUrl = null;
                                  _iconImageStoragePath = null;
                                }),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'アイコン',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  // ヘッダー
                  Expanded(
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            GestureDetector(
                              onTap: () => _pickImage(isIcon: false),
                              child: Container(
                                height: 80,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.grey[200],
                                  border: Border.all(color: Colors.grey[300]!),
                                  image: _coverImage != null
                                      ? DecorationImage(
                                          image: FileImage(_coverImage!),
                                          fit: BoxFit.cover,
                                        )
                                      : _coverImageUrl != null
                                      ? DecorationImage(
                                          image: NetworkImage(_coverImageUrl!),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child:
                                    _coverImage == null &&
                                        _coverImageUrl == null
                                    ? Center(
                                        child: Icon(
                                          Icons.panorama,
                                          color: Colors.grey[400],
                                          size: 32,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            // 削除ボタン
                            if (_coverImage != null || _coverImageUrl != null)
                              Positioned(
                                top: -4,
                                right: -4,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _coverImage = null;
                                    _coverImageUrl = null;
                                    _coverImageStoragePath = null;
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ヘッダー',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // サークル名
            _buildSection(
              title: 'サークル名',
              child: TextFormField(
                controller: _nameController,
                maxLength: 30,
                decoration: _inputDecoration('サークル名を入力'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'サークル名を入力してください';
                  }
                  return null;
                },
              ),
            ),

            const SizedBox(height: 16),

            // 説明
            _buildSection(
              title: '説明',
              child: TextFormField(
                controller: _descriptionController,
                maxLength: 150,
                maxLines: 3,
                decoration: _inputDecoration('サークルの説明を入力'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '説明を入力してください';
                  }
                  return null;
                },
              ),
            ),

            const SizedBox(height: 16),

            // カテゴリ
            _buildSection(
              title: 'カテゴリ',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categories.map((category) {
                  final isSelected = _selectedCategory == category;
                  return ChoiceChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedCategory = category);
                      }
                    },
                    selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: isSelected ? AppColors.primary : Colors.grey[700],
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 16),

            // 目標
            _buildSection(
              title: '目標',
              child: TextFormField(
                controller: _goalController,
                maxLength: 100,
                decoration: _inputDecoration('サークルの目標（任意）'),
                maxLines: 2,
              ),
            ),

            const SizedBox(height: 16),

            // ルール
            _buildSection(
              title: 'サークルルール',
              subtitle: '参加時に同意を求めます（任意・300文字以内）',
              child: TextFormField(
                controller: _rulesController,
                decoration: _inputDecoration('サークルのルールを入力'),
                maxLines: 5,
                maxLength: 300,
              ),
            ),

            const SizedBox(height: 16),

            // AIモードの場合は公開設定を非表示
            if (widget.circle.aiMode != CircleAIMode.aiOnly) ...[
              // 公開設定
              _buildSection(
                title: '公開設定',
                child: Column(
                  children: [
                    _buildRadioTile(
                      title: '公開',
                      subtitle: '誰でも参加できます',
                      value: true,
                      groupValue: _isPublic,
                      onChanged: (value) => setState(() => _isPublic = value!),
                    ),
                    _buildRadioTile(
                      title: '招待制',
                      subtitle: 'オーナーの承認が必要です',
                      value: false,
                      groupValue: _isPublic,
                      onChanged: (value) => setState(() => _isPublic = value!),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400]),
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget _buildRadioTile({
    required String title,
    required String subtitle,
    required bool value,
    required bool groupValue,
    required ValueChanged<bool?> onChanged,
  }) {
    return RadioListTile<bool>(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      activeColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
    );
  }
}
