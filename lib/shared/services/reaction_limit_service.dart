import 'package:shared_preferences/shared_preferences.dart';

/// 投稿ごとのリアクション回数を管理するサービス
class ReactionLimitService {
  static const String _keyPrefix = 'reaction_count_';
  static const int maxReactionsPerPost = 5;

  static String _buildKey(String postId, String? userId) {
    if (userId == null || userId.isEmpty) {
      return '$_keyPrefix$postId';
    }
    return '$_keyPrefix${userId}_$postId';
  }

  /// 指定した投稿のリアクション回数を取得
  static Future<int> getReactionCount(String postId, {String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_buildKey(postId, userId)) ?? 0;
  }

  /// リアクション回数をインクリメント
  static Future<int> incrementReactionCount(
    String postId, {
    String? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _buildKey(postId, userId);
    final currentCount = prefs.getInt(key) ?? 0;
    final newCount = currentCount + 1;
    await prefs.setInt(key, newCount);
    return newCount;
  }

  /// リアクション回数をサーバー値で上書き
  static Future<void> setReactionCount(
    String postId,
    int count, {
    String? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _buildKey(postId, userId);
    await prefs.setInt(key, count);
  }

  /// 指定ユーザーのローカル回数を削除
  static Future<void> clearForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = '$_keyPrefix${userId}_';
    final keys = prefs.getKeys().where((key) => key.startsWith(prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// 残りリアクション可能回数を取得
  static Future<int> getRemainingReactions(
    String postId, {
    String? userId,
  }) async {
    final count = await getReactionCount(postId, userId: userId);
    return (maxReactionsPerPost - count).clamp(0, maxReactionsPerPost);
  }

  /// リアクション可能かどうかをチェック
  static Future<bool> canReact(String postId, {String? userId}) async {
    final count = await getReactionCount(postId, userId: userId);
    return count < maxReactionsPerPost;
  }
}
