import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';

/// 画像モデレーションサービス
/// Cloud Functionsを呼び出して画像の適切性を判定
class ImageModerationService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: AppConstants.functionsRegion,
  );
  static const int _maxImageBytes = 5 * 1024 * 1024;
  static const Set<String> _allowedExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
  };

  void _log(String message) {
    debugPrint('[IMG_MOD] $message');
  }

  /// 画像をモデレーション
  /// 不適切な場合はエラーメッセージを返す、問題なければnull
  Future<String?> moderateImage(File imageFile) async {
    try {
      _log('start path=${imageFile.path}');

      // 画像をBase64エンコード
      final bytes = await imageFile.readAsBytes();
      final simpleCheckError = _runSimpleChecks(imageFile, bytes.length);
      if (simpleCheckError != null) {
        _log('simple_check=blocked reason=$simpleCheckError size=${bytes.length}');
        return simpleCheckError;
      }
      _log('simple_check=pass size=${bytes.length}');
      final base64Image = base64Encode(bytes);

      // MIMEタイプを判定
      final extension = imageFile.path.split('.').last.toLowerCase();
      String mimeType;
      switch (extension) {
        case 'png':
          mimeType = 'image/png';
          break;
        case 'gif':
          mimeType = 'image/gif';
          break;
        case 'webp':
          mimeType = 'image/webp';
          break;
        default:
          mimeType = 'image/jpeg';
      }
      _log('mime_type=$mimeType');

      // Cloud Functionを呼び出し
      _log('callable=moderateImageCallable request');
      final callable = _functions.httpsCallable('moderateImageCallable');
      final result = await callable.call({
        'imageBase64': base64Image,
        'mimeType': mimeType,
      });
      _log('callable response=${result.data}');

      final data = result.data as Map<String, dynamic>;
      final isInappropriate = data['isInappropriate'] as bool? ?? false;
      final category = data['category'] as String? ?? 'none';

      _log(
        'ai_result isInappropriate=$isInappropriate category=$category',
      );

      if (isInappropriate) {
        if (category == 'none') {
          return '画像判定に失敗したためアップロードできませんでした。別の画像をお試しください。';
        }
        // カテゴリに応じたメッセージ
        switch (category) {
          case 'adult':
            return '成人向けコンテンツが検出されました。別の画像を選んでください。';
          case 'violence':
            return '暴力的なコンテンツが検出されました。別の画像を選んでください。';
          case 'hate':
            return '不適切なコンテンツが検出されました。別の画像を選んでください。';
          case 'dangerous':
            return '危険なコンテンツが検出されました。別の画像を選んでください。';
          default:
            return '不適切なコンテンツが検出されました。別の画像を選んでください。';
        }
      }

      return null; // 問題なし
    } on FirebaseFunctionsException catch (e) {
      _log('firebase_exception code=${e.code} message=${e.message}');
      // Cloud Functions呼び出しエラー時はブロック
      return 'モデレーションに失敗しました。しばらくしてから再度お試しください。';
    } catch (e) {
      _log('error=$e');
      // その他のエラー時もブロック（例外詳細はUIに出さない）
      return 'モデレーションに失敗しました。しばらくしてから再度お試しください。';
    }
  }

  String? _runSimpleChecks(File imageFile, int byteLength) {
    if (byteLength <= 0) {
      return '画像を読み込めませんでした。別の画像を選んでください。';
    }
    if (byteLength > _maxImageBytes) {
      return '画像サイズは5MB以下にしてください。';
    }
    final extension = imageFile.path.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(extension)) {
      return '対応していない画像形式です。jpg / png / gif / webp を選んでください。';
    }
    return null;
  }
}
