import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/models/post_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/moderation_provider.dart';
import '../../../../shared/services/circle_service.dart';
import '../../../../shared/services/media_service.dart';
import '../../../../shared/services/moderation_service.dart';
import '../../../../shared/services/nsfw_detector_service.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/widgets/report_dialog.dart';
import '../../../../shared/widgets/virtue_indicator.dart';

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
  bool _isLoading = false;
  bool _isUploading = false;
  double _uploadProgress = 0;

  // 選択されたメディア
  final List<_SelectedMedia> _selectedMedia = [];

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  /// メディア選択メニューを表示
  void _showMediaPicker() {
    if (_selectedMedia.length >= MediaService.maxMediaCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('最大${MediaService.maxMediaCount}つまで添付できます'),
          backgroundColor: AppColors.warning,
        ),
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
              _MediaPickerOption(
                icon: Icons.videocam,
                label: '動画を選択',
                color: Colors.orange,
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo();
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

  /// 動画を選択
  Future<void> _pickVideo() async {
    try {
      final video = await _mediaService.pickVideo();
      if (video != null) {
        // NSFWチェック（サムネイル抽出して検出）
        final nsfwService = NsfwDetectorService.instance;
        await nsfwService.initialize();

        final error = await nsfwService.checkVideo(video.path);
        if (error != null) {
          _showError(error);
          return;
        }
        _addMedia(video.path, MediaType.video);
      }
    } catch (e) {
      _showError('動画の選択に失敗しました');
    }
  }

  /// メディアを追加
  void _addMedia(String path, MediaType type, {String? fileName}) {
    if (_selectedMedia.length >= MediaService.maxMediaCount) return;

    setState(() {
      _selectedMedia.add(
        _SelectedMedia(path: path, type: type, fileName: fileName),
      );
    });
  }

  /// メディアを削除
  void _removeMedia(int index) {
    setState(() {
      _selectedMedia.removeAt(index);
    });
  }

  /// エラーを表示
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _createPost() async {
    final content = _contentController.text.trim();
    if (content.isEmpty && _selectedMedia.isEmpty) return;

    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      // メディアをアップロード
      List<MediaItem> uploadedMedia = [];
      if (_selectedMedia.isNotEmpty) {
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
            fileName: media.fileName,
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

      // モデレーション付き投稿作成（Cloud Functions経由）
      final moderationService = ref.read(moderationServiceProvider);
      await moderationService.createPostWithModeration(
        content: content,
        userDisplayName: user.displayName,
        userAvatarIndex: user.avatarIndex,
        postMode: user.postMode,
        mediaItems: uploadedMedia,
        circleId: widget.circleId, // サークルIDを渡す
      );

      // サークル投稿の場合、postCountをインクリメント
      if (widget.circleId != null) {
        final circleService = ref.read(circleServiceProvider);
        await circleService.incrementPostCount(widget.circleId!);
      }

      // 徳ポイント状態を更新
      ref.invalidate(virtueStatusProvider);

      if (mounted) {
        // 成功メッセージ
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppConstants.friendlyMessages['post_success']!),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop(true); // 成功を返す（ホーム画面でリロードするため）
      }
    } on ModerationException catch (e) {
      if (mounted) {
        // ネガティブコンテンツが検出された場合
        await NegativeContentDialog.show(
          context: context,
          message: e.message,
          onRetry: () {
            // テキストフィールドにフォーカスを戻す
          },
        );
        // 徳ポイント状態を更新
        ref.invalidate(virtueStatusProvider);
      }
    } catch (e) {
      if (mounted) {
        // ファイルサイズエラーなど具体的なメッセージがある場合はそれを表示
        final errorMessage = e.toString().contains('ファイルサイズ')
            ? e.toString().replaceFirst('Exception: ', '')
            : AppConstants.friendlyMessages['error_general']!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final remainingChars =
        AppConstants.maxPostLength - _contentController.text.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.circleId != null ? 'サークルに投稿' : '新しい投稿'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.close_rounded),
        ),
        actions: [
          // 徳ポイントバッジ
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: VirtueBadge()),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton(
              onPressed:
                  (_contentController.text.trim().isEmpty &&
                          _selectedMedia.isEmpty) ||
                      _isLoading
                  ? null
                  : _createPost,
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
                  : const Text('投稿する'),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: Column(
          children: [
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
                          AvatarWidget(avatarIndex: user.avatarIndex, size: 48),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.displayName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (widget.circleId != null)
                                Text(
                                  'サークルへの投稿',
                                  style: Theme.of(context).textTheme.bodySmall
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

                    // 投稿入力
                    TextField(
                      controller: _contentController,
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
                          color: AppColors.primary.withOpacity(0.1),
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
                    color: Colors.black.withOpacity(0.05),
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
                      onPressed: _isLoading ? null : _showMediaPicker,
                      icon: Badge(
                        isLabelVisible: _selectedMedia.isNotEmpty,
                        label: Text('${_selectedMedia.length}'),
                        child: const Icon(Icons.attach_file),
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
                        color: remainingChars < 50
                            ? AppColors.warning
                            : AppColors.textHint,
                        fontWeight: remainingChars < 50
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
      ),
    );
  }
}

/// 選択されたメディア
class _SelectedMedia {
  final String path;
  final MediaType type;
  final String? fileName;

  _SelectedMedia({required this.path, required this.type, this.fileName});
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
          color: color.withOpacity(0.1),
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
  final VoidCallback onRemove;

  const _MediaPreview({required this.media, required this.onRemove});

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
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
          // ファイル名（ファイルの場合）
          if (media.type == MediaType.file)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(11),
                  ),
                ),
                child: Text(
                  media.fileName ?? 'ファイル',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
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
          color: Colors.grey.shade100,
          child: Icon(_getFileIcon(), size: 40, color: Colors.grey.shade600),
        );
    }
  }

  IconData _getFileIcon() {
    final ext = media.path.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'txt':
        return Icons.text_snippet;
      case 'zip':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }
}
