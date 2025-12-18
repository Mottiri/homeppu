import 'package:shared_preferences/shared_preferences.dart';

/// 直近使用したリアクションを管理するサービス
class RecentReactionsService {
  static const String _key = 'recent_reactions';
  static const int maxRecentReactions = 7;

  /// 直近使用したリアクションタイプのリストを取得
  static Future<List<String>> getRecentReactions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  /// リアクションを使用した際に呼び出し、リストを更新
  static Future<void> addReaction(String reactionType) async {
    final prefs = await SharedPreferences.getInstance();
    final recent = prefs.getStringList(_key) ?? [];

    // 既に存在する場合は削除（重複排除）
    recent.remove(reactionType);

    // 先頭に追加
    recent.insert(0, reactionType);

    // 最大件数を超えたら古いものを削除
    if (recent.length > maxRecentReactions) {
      recent.removeRange(maxRecentReactions, recent.length);
    }

    await prefs.setStringList(_key, recent);
  }

  /// リストをクリア
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
