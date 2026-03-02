import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../models/post_model.dart';

class MediaService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
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

  Future<List<XFile>> pickImages({int maxCount = 4}) async {
    final images = await _imagePicker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
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

    return MediaItem(
      url: downloadUrl,
      type: type,
      fileName: fileName ?? path.basename(filePath),
      mimeType: _getMimeType(extension),
      fileSize: fileSize,
    );
  }

  Future<List<MediaItem>> uploadMultiple({
    required List<String> filePaths,
    required String userId,
    required MediaType type,
    Function(int current, int total, double progress)? onProgress,
  }) async {
    final results = <MediaItem>[];

    for (int i = 0; i < filePaths.length; i++) {
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

  Future<String> uploadCircleImage({
    required String filePath,
    required String circleId,
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
    return snapshot.ref.getDownloadURL();
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

  Future<void> deleteMedia(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
    } on FirebaseException catch (e) {
      debugPrint('MediaService.deleteMedia FirebaseException: ${e.code} ${e.message}');
    } catch (e, stackTrace) {
      debugPrint('MediaService.deleteMedia error: $e');
      debugPrint('$stackTrace');
    }
  }

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
