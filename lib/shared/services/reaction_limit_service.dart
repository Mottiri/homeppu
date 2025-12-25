import 'package:shared_preferences/shared_preferences.dart';

/// 投稿ごとのリアクション回数を管理するサービス
class ReactionLimitService {
  static const String _keyPrefix = 'reaction_count_';
  static const int maxReactionsPerPost = 5;

  /// 指定した投稿のリアクション回数を取得
  static Future<int> getReactionCount(String postId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_keyPrefix$postId') ?? 0;
  }

  /// リアクション回数をインクリメント
  static Future<int> incrementReactionCount(String postId) async {
    final prefs = await SharedPreferences.getInstance();
    final currentCount = prefs.getInt('$_keyPrefix$postId') ?? 0;
    final newCount = currentCount + 1;
    await prefs.setInt('$_keyPrefix$postId', newCount);
    return newCount;
  }

  /// 残りリアクション可能回数を取得
  static Future<int> getRemainingReactions(String postId) async {
    final count = await getReactionCount(postId);
    return (maxReactionsPerPost - count).clamp(0, maxReactionsPerPost);
  }

  /// リアクション可能かどうかをチェック
  static Future<bool> canReact(String postId) async {
    final count = await getReactionCount(postId);
    return count < maxReactionsPerPost;
  }
}
