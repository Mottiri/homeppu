import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import '../models/post_model.dart';

/// メディアアップロードサービス
class MediaService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final Uuid _uuid = const Uuid();

  // アップロード制限
  static const int maxImageSize = 5 * 1024 * 1024; // 5MB
  static const int maxVideoSize = 30 * 1024 * 1024; // 30MB
  static const int maxMediaCount = 4; // 最大4つのメディア

  // 許可される拡張子
  static const List<String> allowedImageExtensions = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
  ];
  static const List<String> allowedVideoExtensions = [
    'mp4',
    'mov',
    'avi',
    'mkv',
  ];

  /// ギャラリーから画像を選択
  Future<List<XFile>> pickImages({int maxCount = 4}) async {
    final List<XFile> images = await _imagePicker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    return images.take(maxCount).toList();
  }

  /// カメラで撮影
  Future<XFile?> takePhoto() async {
    return await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
  }

  /// ギャラリーから動画を選択
  Future<XFile?> pickVideo() async {
    return await _imagePicker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 3),
    );
  }

  /// カメラで動画を撮影
  Future<XFile?> recordVideo() async {
    return await _imagePicker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 1),
    );
  }

  /// ファイルをFirebase Storageにアップロード
  Future<MediaItem> uploadFile({
    required String filePath,
    required String userId,
    required MediaType type,
    String? fileName,
    Function(double)? onProgress,
  }) async {
    final file = File(filePath);
    final fileSize = await file.length();

    // サイズチェック（画像: 5MB、動画: 30MB）
    final maxSize = type == MediaType.video ? maxVideoSize : maxImageSize;
    if (fileSize > maxSize) {
      throw Exception('ファイルサイズが大きすぎます（最大${maxSize ~/ (1024 * 1024)}MB）');
    }

    // ファイル名を生成
    final extension = path.extension(filePath).toLowerCase();
    final uniqueFileName = '${_uuid.v4()}$extension';
    final storagePath = 'posts/$userId/${type.name}s/$uniqueFileName';

    // アップロード
    final ref = _storage.ref().child(storagePath);
    final uploadTask = ref.putFile(
      file,
      SettableMetadata(
        contentType: _getMimeType(extension),
        customMetadata: {
          'originalFileName': fileName ?? path.basename(filePath),
          'uploadedAt': DateTime.now().millisecondsSinceEpoch.toString(),
          'postId': 'PENDING', // 投稿前は PENDING、投稿後に実際のpostIdに更新
        },
      ),
    );

    // 進捗を通知
    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((event) {
        final progress = event.bytesTransferred / event.totalBytes;
        onProgress(progress);
      });
    }

    // 完了を待つ
    final snapshot = await uploadTask;
    final downloadUrl = await snapshot.ref.getDownloadURL();

    return MediaItem(
      url: downloadUrl,
      type: type,
      fileName: fileName ?? path.basename(filePath),
      mimeType: _getMimeType(extension),
      fileSize: fileSize,
    );
  }

  /// 複数ファイルをアップロード
  Future<List<MediaItem>> uploadMultiple({
    required List<String> filePaths,
    required String userId,
    required MediaType type,
    Function(int current, int total, double progress)? onProgress,
  }) async {
    final List<MediaItem> results = [];

    for (int i = 0; i < filePaths.length; i++) {
      final item = await uploadFile(
        filePath: filePaths[i],
        userId: userId,
        type: type,
        onProgress: (progress) {
          onProgress?.call(i + 1, filePaths.length, progress);
        },
      );
      results.add(item);
    }

    return results;
  }

  /// タスク添付ファイルをアップロード
  Future<String> uploadTaskAttachment({
    required String filePath,
    required String userId,
    required String taskId,
    Function(double)? onProgress,
  }) async {
    final file = File(filePath);
    final fileSize = await file.length();

    // サイズチェック (5MB - 画像のみ対応)
    if (fileSize > maxImageSize) {
      throw Exception('ファイルサイズが大きすぎます（最大${maxImageSize ~/ (1024 * 1024)}MB）');
    }

    // ファイル名を生成
    final extension = path.extension(filePath).toLowerCase();
    final uniqueFileName = '${_uuid.v4()}$extension';
    final storagePath = 'task_attachments/$userId/$taskId/$uniqueFileName';

    // アップロード
    final ref = _storage.ref().child(storagePath);
    final uploadTask = ref.putFile(
      file,
      SettableMetadata(
        contentType: _getMimeType(extension),
        customMetadata: {
          'originalFileName': path.basename(filePath),
          'uploadedAt': DateTime.now().toIso8601String(),
        },
      ),
    );

    // 進捗を通知
    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((event) {
        final progress = event.bytesTransferred / event.totalBytes;
        onProgress(progress);
      });
    }

    // 完了を待つ
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  /// サークル画像（アイコン・ヘッダー）をアップロード
  Future<String> uploadCircleImage({
    required String filePath,
    required String circleId,
    required String imageType, // 'icon' or 'cover'
    Function(double)? onProgress,
  }) async {
    final file = File(filePath);
    final fileSize = await file.length();

    // サイズチェック (5MB)
    if (fileSize > maxImageSize) {
      throw Exception('ファイルサイズが大きすぎます（最大${maxImageSize ~/ (1024 * 1024)}MB）');
    }

    // ファイル名を生成
    final extension = path.extension(filePath).toLowerCase();
    final uniqueFileName = '${_uuid.v4()}$extension';
    final storagePath = 'circles/$circleId/$imageType/$uniqueFileName';

    // アップロード
    final ref = _storage.ref().child(storagePath);
    final uploadTask = ref.putFile(
      file,
      SettableMetadata(
        contentType: _getMimeType(extension),
        customMetadata: {'uploadedAt': DateTime.now().toIso8601String()},
      ),
    );

    // 進捗を通知
    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((event) {
        final progress = event.bytesTransferred / event.totalBytes;
        onProgress(progress);
      });
    }

    // 完了を待つ
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  /// メディアを削除
  Future<void> deleteMedia(String url) async {
    try {
      debugPrint('MediaService.deleteMedia: Attempting to delete');
      debugPrint('  URL: $url');

      final ref = _storage.refFromURL(url);
      final fullPath = ref.fullPath;
      debugPrint('  Extracted path: $fullPath');

      await ref.delete();
      debugPrint('MediaService.deleteMedia: ✓ Successfully deleted $fullPath');
    } on FirebaseException catch (e) {
      debugPrint('MediaService.deleteMedia: ✗ FirebaseException');
      debugPrint('  Code: ${e.code}');
      debugPrint('  Message: ${e.message}');
      debugPrint('  URL: $url');
    } catch (e, stackTrace) {
      debugPrint('MediaService.deleteMedia: ✗ Error: $e');
      debugPrint('  Type: ${e.runtimeType}');
      debugPrint('  URL: $url');
      debugPrint('  Stack: $stackTrace');
    }
  }

  /// MIMEタイプを取得
  String _getMimeType(String extension) {
    final ext = extension.toLowerCase().replaceAll('.', '');
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt':
        return 'text/plain';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  /// 拡張子からMediaTypeを判定（画像または動画）
  MediaType getMediaType(String filePath) {
    final ext = path.extension(filePath).toLowerCase().replaceAll('.', '');
    if (allowedVideoExtensions.contains(ext)) {
      return MediaType.video;
    }
    // デフォルトは画像
    return MediaType.image;
  }
}
