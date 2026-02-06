import 'package:flutter/material.dart';
import '../../shared/models/user_model.dart';
import 'app_colors.dart';

/// アプリ全体の定数
class AppConstants {
  AppConstants._();

  // アプリ情報
  static const String appName = 'ほめっぷ';
  static const String appTagline = '世界一優しいSNS';
  static const String appDescription = '承認欲求による疲弊を解消し、自己肯定感を最大化する';

  // 投稿モード
  static const String modeAI = 'ai';
  static const String modeMix = 'mix';
  static const String modeHuman = 'human';

  // リアクションタイプ
  static const String reactionLove = 'love'; // いいね
  static const String reactionPraise = 'praise'; // すごい
  static const String reactionCheer = 'cheer'; // がんばれ
  static const String reactionEmpathy = 'empathy'; // わかる

  // リアクション一時解放（リワード）
  static const int rewardedReactionUses = 25;
  static const int rewardedReactionHours = 24;

  // システムメッセージ（フレンドリーなトーン）
  static const Map<String, String> friendlyMessages = {
    'welcome': 'ようこそ、ほめっぷへ！\nあなたの毎日を応援するよ☺️',
    'post_success': '投稿できたよ！みんなに届くのを待っててね✨',
    'reaction_received': 'やったね！リアクションが届いたよ💕',
    'comment_received': 'わぁ！コメントが届いたよ☺️',
    'loading': 'ちょっと待っててね...',
    'error_general': 'ごめんね、うまくいかなかったみたい😢\nもう一度試してみてね',
    'error_network': 'ネットワークの調子が悪いみたい🌐\n接続を確認してね',
    'logout_confirm': '本当にログアウトする？\nまた会えるのを楽しみにしてるね💫',
    'virtue_up': '徳が上がったよ！素敵な行いだね✨',
    'first_post': '最初の投稿おめでとう！🎉\nこれからたくさん褒められちゃおう！',
  };

  // AI応答の遅延設定（ミリ秒）
  static const int aiMinDelay = 60000; // 最小1分
  static const int aiMaxDelay = 10800000; // 最大3時間

  // バリデーション
  static const int maxPostLength = 500;
  static const int maxCommentLength = 200;
  static const int maxDisplayNameLength = 20;
  static const int maxBioLength = 100;

  // ページネーション
  static const int postsPerPage = 20;
  static const int commentsPerPage = 10;

  // 徳システム
  static const int virtueInitial = 100;
  static const int virtueMaxDaily = 50;
  static const int virtueBanThreshold = 0;
  static const int virtueGainPerPraise = 5;
  static const int virtueLossPerReport = 20;
}

/// 投稿の公開モード
enum PostMode {
  ai('ai', 'AIモード', 'AIからのみ反応が届くよ'),
  mix('mix', 'ミックスモード', 'AIと人間の両方から反応が届くよ'),
  human('human', '人間モード', '実際の人間からのみ反応が届くよ');

  const PostMode(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;
}

/// リアクションのカテゴリ
enum ReactionCategory {
  basic('basic', 'おすすめ'),
  symbol('symbol', '記号'),
  emotion('emotion', '表情'),
  nature('nature', '自然・生き物'),
  item('item', '食べ物・アイテム');

  const ReactionCategory(this.value, this.label);
  final String value;
  final String label;
}

/// ??????????
enum ReactionRarity {
  common,
  rare, // ?????
  epic, // ????
}

/// ???????????
enum ReactionUnlockType {
  free,
  virtue, // ???????
  subscription, // ????
}



/// リアクションの種類（7種類のスタンプ）
enum ReactionType {
  heart('heart', '??', '???', 0xFFFF6B6B, ReactionRarity.common),
  praise('praise', '??', '???', 0xFFFFD93D, ReactionRarity.common),
  clap('clap', '??', '??', 0xFFFFDAB9, ReactionRarity.common),
  shine('shine', '?', '????', 0xFF6BCB77, ReactionRarity.rare, virtueCost: 100),
  star('star', '?', '???', 0xFFFFD700, ReactionRarity.rare, virtueCost: 100),
  rainbow('rainbow', '??', '??', 0xFFFFB7C5, ReactionRarity.epic),
  hundred('hundred', '??', '100?', 0xFFFF4500, ReactionRarity.epic);

  const ReactionType(
    this.value,
    this.emoji,
    this.label,
    this.colorValue,
    this.rarity, {
    this.virtueCost,
  });

  final String value;
  final String emoji;
  final String label;
  final int colorValue;
  final ReactionRarity rarity;
  final int? virtueCost; // ?????????rare???

  /// ???????assets/reactions/{value}.png?
  String get assetPath => 'assets/reactions/$value.png';

  String get purchaseKey => 'reaction_$value';

  ReactionUnlockType get unlockType {
    switch (rarity) {
      case ReactionRarity.common:
        return ReactionUnlockType.free;
      case ReactionRarity.rare:
        return ReactionUnlockType.virtue;
      case ReactionRarity.epic:
        return ReactionUnlockType.subscription;
    }
  }

  bool isUnlocked({
    required bool isSubscriber,
    required Set<String> unlockedItems,
    Map<String, RewardedReactionUnlock>? rewardedUnlocks,
    DateTime? now,
  }) {
    switch (unlockType) {
      case ReactionUnlockType.free:
        return true;
      case ReactionUnlockType.virtue:
        return unlockedItems.contains(purchaseKey);
      case ReactionUnlockType.subscription:
        if (isSubscriber) return true;
        final unlock = rewardedUnlocks?[value];
        if (unlock == null) return false;
        final current = now ?? DateTime.now();
        return unlock.remaining > 0 && current.isBefore(unlock.expiresAt);
    }
  }

  Color get rarityColor {
    switch (rarity) {
      case ReactionRarity.common:
        return AppColors.rarityCommon;
      case ReactionRarity.rare:
        return AppColors.rarityRare;
      case ReactionRarity.epic:
        return AppColors.rarityEpic;
    }
  }
}
