import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nsfw_detector_flutter/nsfw_detector_flutter.dart';

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
      return null; // 初期化されていない場合はスキップ
    }

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return null;
      }

      final result = await _detector!.detectNSFWFromFile(file);

      if (result == null) {
        return null;
      }


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

  /// 画像バイトからNSFWかどうか判定
  Future<String?> checkImageBytes(Uint8List bytes) async {
    if (!_isInitialized || _detector == null) {
      return null;
    }

    try {
      final result = await _detector!.detectNSFWFromBytes(bytes);

      if (result == null) {
        return null;
      }


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
