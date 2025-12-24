import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// AIサービス
/// Cloud Functionsを呼び出すラッパー
class AIService {
  final FirebaseFunctions _functions;

  AIService()
    : _functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  /// AIアカウントを初期化（管理者用）
  Future<void> initializeAIAccounts() async {
    try {
      final callable = _functions.httpsCallable('initializeAIAccounts');
      final result = await callable.call();
      debugPrint('AIアカウント初期化: ${result.data}');
    } catch (e) {
      debugPrint('AIアカウント初期化エラー: $e');
      rethrow;
    }
  }

  /// AI過去投稿を生成（管理者用）
  Future<Map<String, dynamic>> generateAIPosts() async {
    try {
      final callable = _functions.httpsCallable(
        'generateAIPosts',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
      );
      final result = await callable.call();
      debugPrint('AI投稿生成: ${result.data}');
      return Map<String, dynamic>.from(result.data as Map);
    } catch (e) {
      debugPrint('AI投稿生成エラー: $e');
      rethrow;
    }
  }

  /// レート制限付きで投稿を作成
  Future<String?> createPostWithRateLimit({
    required String content,
    required String userDisplayName,
    required int userAvatarIndex,
    required String postMode,
    String? circleId,
  }) async {
    try {
      final callable = _functions.httpsCallable('createPostWithRateLimit');
      final result = await callable.call({
        'content': content,
        'userDisplayName': userDisplayName,
        'userAvatarIndex': userAvatarIndex,
        'postMode': postMode,
        'circleId': circleId,
      });
      return result.data['postId'] as String?;
    } catch (e) {
      debugPrint('投稿作成エラー: $e');
      rethrow;
    }
  }

  /// AIユーザーを全削除（管理者用）
  Future<void> deleteAllAIUsers() async {
    try {
      final callable = _functions.httpsCallable(
        'deleteAllAIUsers',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
      );
      final result = await callable.call();
      debugPrint('AIユーザー全削除: ${result.data}');
    } catch (e) {
      debugPrint('AIユーザー全削除エラー: $e');
      rethrow;
    }
  }
}
