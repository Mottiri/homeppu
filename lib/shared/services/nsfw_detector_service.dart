import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nsfw_detector_flutter/nsfw_detector_flutter.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';

/// クライアント側NSFW検出サービス
/// 画像選択時に即座にNSFW判定を行い、不適切な画像をブロックする
class NsfwDetectorService {
  static NsfwDetectorService? _instance;
  NsfwDetector? _detector;
  bool _isInitialized = false;

  /// シングルトンインスタンス
  static NsfwDetectorService get instance {
    _instance ??= NsfwDetectorService._();
    return _instance!;
  }

  NsfwDetectorService._();

  /// 初期化
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _detector = await NsfwDetector.load(); // threshold: 0.7 がデフォルト
      _isInitialized = true;
      debugPrint('NsfwDetectorService: Initialized successfully');
    } catch (e) {
      debugPrint('NsfwDetectorService: Failed to initialize - $e');
      // 初期化失敗しても続行（Cloud Functionsで二重チェックするため）
    }
  }

  /// 画像がNSFWかどうか判定
  ///
  /// Returns: エラーメッセージ（NSFWの場合）、または null（安全な場合）
  Future<String?> checkImage(String imagePath) async {
    if (!_isInitialized || _detector == null) {
      debugPrint('NsfwDetectorService: Not initialized, skipping check');
      return null; // 初期化されていない場合はスキップ
    }

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        debugPrint('NsfwDetectorService: File not found');
        return null;
      }

      debugPrint('NsfwDetectorService: Checking image: $imagePath');
      final result = await _detector!.detectNSFWFromFile(file);

      if (result == null) {
        debugPrint('NsfwDetectorService: Result is null');
        return null;
      }

      debugPrint(
        'NsfwDetectorService: Result - isNsfw=${result.isNsfw}, score=${result.score}',
      );

      // NSFW判定されたらブロック
      if (result.isNsfw) {
        return '不適切な画像が検出されました。別の画像を選んでください。';
      }

      return null; // 安全
    } catch (e) {
      debugPrint('NsfwDetectorService: Error during check - $e');
      // エラー時はスキップ（Cloud Functionsで二重チェック）
      return null;
    }
  }

  /// 動画がNSFWかどうか判定（サムネイルを抽出してチェック）
  ///
  /// Returns: エラーメッセージ（NSFWの場合）、または null（安全な場合）
  Future<String?> checkVideo(String videoPath) async {
    if (!_isInitialized || _detector == null) {
      debugPrint('NsfwDetectorService: Not initialized, skipping video check');
      return null;
    }

    try {
      debugPrint('NsfwDetectorService: Checking video: $videoPath');

      // 動画からサムネイルを抽出
      final tempDir = await getTemporaryDirectory();
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.JPEG,
        quality: 75,
      );

      if (thumbnailPath == null) {
        debugPrint('NsfwDetectorService: Failed to extract thumbnail');
        return null;
      }

      debugPrint('NsfwDetectorService: Thumbnail extracted: $thumbnailPath');

      // サムネイルをNSFWチェック
      final result = await checkImage(thumbnailPath);

      // 一時ファイルを削除
      try {
        await File(thumbnailPath).delete();
      } catch (_) {}

      if (result != null) {
        return '不適切な動画が検出されました。別の動画を選んでください。';
      }

      return null;
    } catch (e) {
      debugPrint('NsfwDetectorService: Error during video check - $e');
      return null;
    }
  }

  /// 画像バイトからNSFWかどうか判定
  Future<String?> checkImageBytes(Uint8List bytes) async {
    if (!_isInitialized || _detector == null) {
      return null;
    }

    try {
      debugPrint('NsfwDetectorService: Checking image bytes');
      final result = await _detector!.detectNSFWFromBytes(bytes);

      if (result == null) {
        return null;
      }

      debugPrint(
        'NsfwDetectorService: Result - isNsfw=${result.isNsfw}, score=${result.score}',
      );

      if (result.isNsfw) {
        return '不適切な画像が検出されました。別の画像を選んでください。';
      }

      return null;
    } catch (e) {
      debugPrint('NsfwDetectorService: Error during bytes check - $e');
      return null;
    }
  }
}
