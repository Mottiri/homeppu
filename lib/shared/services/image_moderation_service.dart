import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// 画像モデレーションサービス
/// Cloud Functionsを呼び出して画像の適切性を判定
class ImageModerationService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-northeast1',
  );

  /// 画像をモデレーション
  /// 不適切な場合はエラーメッセージを返す、問題なければnull
  Future<String?> moderateImage(File imageFile) async {
    try {
      debugPrint(
        'ImageModerationService: Starting moderation for ${imageFile.path}',
      );

      // 画像をBase64エンコード
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      debugPrint('ImageModerationService: Image size: ${bytes.length} bytes');

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
      debugPrint('ImageModerationService: MIME type: $mimeType');

      // Cloud Functionを呼び出し
      debugPrint('ImageModerationService: Calling moderateImageCallable...');
      final callable = _functions.httpsCallable('moderateImageCallable');
      final result = await callable.call({
        'imageBase64': base64Image,
        'mimeType': mimeType,
      });
      debugPrint('ImageModerationService: Function returned: ${result.data}');

      final data = result.data as Map<String, dynamic>;
      final isInappropriate = data['isInappropriate'] as bool? ?? false;
      final reason = data['reason'] as String? ?? '';
      final category = data['category'] as String? ?? 'none';

      debugPrint(
        'ImageModerationService: isInappropriate=$isInappropriate, category=$category',
      );

      if (isInappropriate) {
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
            return '不適切なコンテンツが検出されました：$reason';
        }
      }

      return null; // 問題なし
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        'ImageModerationService FirebaseFunctionsException: ${e.code} - ${e.message}',
      );
      // Cloud Functions呼び出しエラー時はブロック
      return 'モデレーションに失敗しました。しばらくしてから再度お試しください。';
    } catch (e) {
      debugPrint('ImageModerationService error: $e');
      // その他のエラー時もブロック
      return 'モデレーションに失敗しました: $e';
    }
  }
}
