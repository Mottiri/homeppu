import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../models/post_model.dart';

class UploadedStorageItem {
  final String downloadUrl;
  final String storagePath;

  const UploadedStorageItem({
    required this.downloadUrl,
    required this.storagePath,
  });
}

class MediaService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _imagePicker = ImagePicker();
  final Uuid _uuid = const Uuid();

  static const int maxImageSize = 5 * 1024 * 1024;
  static const int maxMediaCount = 4;

  static const List<String> allowedImageExtensions = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
  ];

  CollectionReference<Map<String, dynamic>> get _pendingMediaCollection =>
      _firestore.collection('pendingMedia');

  String _describeError(Object error) {
    if (error is FirebaseException) {
      return 'FirebaseException(code=${error.code}, message=${error.message})';
    }
    return '${error.runtimeType}: $error';
  }

  Future<List<XFile>> pickImages({int maxCount = 4}) async {
    final images = await _imagePicker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
      limit: maxCount,
    );
    return images.take(maxCount).toList();
  }

  Future<XFile?> takePhoto() async {
    return _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
  }

  Future<MediaItem> uploadFile({
    required String filePath,
    required String userId,
    required MediaType type,
    String? fileName,
    Function(double)? onProgress,
  }) async {
    final file = File(filePath);
    final fileSize = await file.length();

    if (fileSize > maxImageSize) {
      throw Exception('File is too large (max ${maxImageSize ~/ (1024 * 1024)}MB)');
    }

    final extension = path.extension(filePath).toLowerCase();
    final uniqueFileName = '${_uuid.v4()}$extension';
    final storagePath = 'posts/$userId/images/$uniqueFileName';
    debugPrint(
      '[MediaService] uploadFile start '
      'userId=$userId type=${type.name} filePath=$filePath '
      'storagePath=$storagePath fileSize=$fileSize',
    );

    final ref = _storage.ref().child(storagePath);
    final uploadTask = ref.putFile(
      file,
      SettableMetadata(
        contentType: _getMimeType(extension),
        customMetadata: {
          'originalFileName': fileName ?? path.basename(filePath),
          'uploadedAt': DateTime.now().millisecondsSinceEpoch.toString(),
          'postId': 'PENDING',
        },
      ),
    );

    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((event) {
        onProgress(event.bytesTransferred / event.totalBytes);
      });
    }

    final snapshot = await uploadTask;
    final downloadUrl = await snapshot.ref.getDownloadURL();
    debugPrint(
      '[MediaService] uploadFile success '
      'storagePath=$storagePath bytes=${snapshot.totalBytes}',
    );

    try {
      debugPrint(
        '[MediaService] registerPendingMedia start '
        'type=post_image ownerId=$userId storagePath=$storagePath',
      );
      await registerPendingMedia(
        type: 'post_image',
        ownerId: userId,
        storagePath: storagePath,
      );
      debugPrint(
        '[MediaService] registerPendingMedia success '
        'type=post_image storagePath=$storagePath',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[MediaService] registerPendingMedia failed '
        'type=post_image ownerId=$userId storagePath=$storagePath '
        'error=${_describeError(error)}',
      );
      debugPrint('$stackTrace');
      await deleteMediaByStoragePath(storagePath);
      rethrow;
    }

    return MediaItem(
      url: downloadUrl,
      type: type,
      fileName: fileName ?? path.basename(filePath),
      mimeType: _getMimeType(extension),
      fileSize: fileSize,
      storagePath: storagePath,
    );
  }

  Future<List<MediaItem>> uploadMultiple({
    required List<String> filePaths,
    required String userId,
    required MediaType type,
    Function(int current, int total, double progress)? onProgress,
  }) async {
    final results = <MediaItem>[];

    for (var i = 0; i < filePaths.length; i++) {
      final item = await uploadFile(
        filePath: filePaths[i],
        userId: userId,
        type: type,
        onProgress: (progress) =>
            onProgress?.call(i + 1, filePaths.length, progress),
      );
      results.add(item);
    }

    return results;
  }

  Future<UploadedStorageItem> uploadCircleImage({
    required String filePath,
    required String circleId,
    required String ownerId,
    required String imageType,
    Function(double)? onProgress,
  }) async {
    final file = File(filePath);
    final fileSize = await file.length();

    if (fileSize > maxImageSize) {
      throw Exception('File is too large (max ${maxImageSize ~/ (1024 * 1024)}MB)');
    }

    final extension = path.extension(filePath).toLowerCase();
    final uniqueFileName = '${_uuid.v4()}$extension';
    final storagePath = 'circles/$circleId/$imageType/$uniqueFileName';
    debugPrint(
      '[MediaService] uploadCircleImage start '
      'ownerId=$ownerId circleId=$circleId imageType=$imageType '
      'filePath=$filePath storagePath=$storagePath fileSize=$fileSize',
    );

    final ref = _storage.ref().child(storagePath);
    final uploadTask = ref.putFile(
      file,
      SettableMetadata(
        contentType: _getMimeType(extension),
        customMetadata: {'uploadedAt': DateTime.now().toIso8601String()},
      ),
    );

    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((event) {
        onProgress(event.bytesTransferred / event.totalBytes);
      });
    }

    final snapshot = await uploadTask;
    final downloadUrl = await snapshot.ref.getDownloadURL();
    final pendingType = imageType == 'icon' ? 'circle_icon' : 'circle_cover';
    debugPrint(
      '[MediaService] uploadCircleImage success '
      'storagePath=$storagePath bytes=${snapshot.totalBytes}',
    );

    try {
      debugPrint(
        '[MediaService] registerPendingMedia start '
        'type=$pendingType ownerId=$ownerId circleId=$circleId '
        'storagePath=$storagePath',
      );
      await registerPendingMedia(
        type: pendingType,
        ownerId: ownerId,
        storagePath: storagePath,
        circleId: circleId,
      );
      debugPrint(
        '[MediaService] registerPendingMedia success '
        'type=$pendingType storagePath=$storagePath',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[MediaService] registerPendingMedia failed '
        'type=$pendingType ownerId=$ownerId circleId=$circleId '
        'storagePath=$storagePath error=${_describeError(error)}',
      );
      debugPrint('$stackTrace');
      await deleteMediaByStoragePath(storagePath);
      rethrow;
    }

    return UploadedStorageItem(
      downloadUrl: downloadUrl,
      storagePath: storagePath,
    );
  }

  Future<String> uploadInquiryImage(File file, {required String userId}) async {
    final fileSize = await file.length();
    if (fileSize > maxImageSize) {
      throw Exception('File is too large (max ${maxImageSize ~/ (1024 * 1024)}MB)');
    }

    final extension = path.extension(file.path).toLowerCase();
    final uniqueFileName = '${_uuid.v4()}$extension';
    final storagePath = 'inquiries/$userId/$uniqueFileName';

    final ref = _storage.ref().child(storagePath);
    final uploadTask = ref.putFile(
      file,
      SettableMetadata(
        contentType: _getMimeType(extension),
        customMetadata: {'uploadedAt': DateTime.now().toIso8601String()},
      ),
    );

    final snapshot = await uploadTask;
    return snapshot.ref.getDownloadURL();
  }

  Future<void> registerPendingMedia({
    required String type,
    required String ownerId,
    required String storagePath,
    String? circleId,
  }) async {
    debugPrint(
      '[MediaService] pendingMedia write '
      'docId=${_pendingMediaDocId(storagePath)} type=$type ownerId=$ownerId '
      'circleId=$circleId storagePath=$storagePath',
    );
    await _pendingMediaCollection.doc(_pendingMediaDocId(storagePath)).set({
      'type': type,
      'ownerId': ownerId,
      'storagePath': storagePath,
      if (circleId != null) 'circleId': circleId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resolvePendingMediaByStoragePath(String? storagePath) async {
    if (storagePath == null || storagePath.isEmpty) return;

    try {
      await _pendingMediaCollection.doc(_pendingMediaDocId(storagePath)).delete();
    } catch (error, stackTrace) {
      debugPrint('Failed to resolve pending media: $storagePath $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> resolvePendingMediaItems(Iterable<MediaItem> mediaItems) async {
    for (final item in mediaItems) {
      await resolvePendingMediaByStoragePath(item.storagePath);
    }
  }

  Future<void> resolvePendingStorageItems(
    Iterable<UploadedStorageItem> items,
  ) async {
    for (final item in items) {
      await resolvePendingMediaByStoragePath(item.storagePath);
    }
  }

  Future<void> rollbackUploadedMediaItems(Iterable<MediaItem> mediaItems) async {
    for (final item in mediaItems) {
      if (item.storagePath != null && item.storagePath!.isNotEmpty) {
        await deleteMediaByStoragePath(item.storagePath!);
        await resolvePendingMediaByStoragePath(item.storagePath);
      } else {
        await deleteMedia(item.url);
      }
    }
  }

  Future<void> rollbackUploadedStorageItems(
    Iterable<UploadedStorageItem> items,
  ) async {
    for (final item in items) {
      await deleteMediaByStoragePath(item.storagePath);
      await resolvePendingMediaByStoragePath(item.storagePath);
    }
  }

  String? getStoragePathFromUrl(String url) {
    try {
      return _storage.refFromURL(url).fullPath;
    } catch (e, stackTrace) {
      debugPrint('MediaService.getStoragePathFromUrl error: $e');
      debugPrint('$stackTrace');
      return null;
    }
  }

  Future<bool> deleteMedia(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
      return true;
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') {
        debugPrint('MediaService.deleteMedia FirebaseException: ${e.code} ${e.message}');
      }
      return false;
    } catch (e, stackTrace) {
      debugPrint('MediaService.deleteMedia error: $e');
      debugPrint('$stackTrace');
      return false;
    }
  }

  Future<bool> deleteMediaByStoragePath(String storagePath) async {
    try {
      await _storage.ref().child(storagePath).delete();
      return true;
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') {
        debugPrint(
          'MediaService.deleteMediaByStoragePath FirebaseException: ${e.code} ${e.message}',
        );
      }
      return false;
    } catch (e, stackTrace) {
      debugPrint('MediaService.deleteMediaByStoragePath error: $e');
      debugPrint('$stackTrace');
      return false;
    }
  }

  String _pendingMediaDocId(String storagePath) =>
      Uri.encodeComponent(storagePath);

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

  MediaType getMediaType(String filePath) {
    return MediaType.image;
  }
}
