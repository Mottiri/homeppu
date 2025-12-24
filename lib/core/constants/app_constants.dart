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

/// リアクションの種類
enum ReactionType {
  // おすすめ
  love('love', '❤️', 'いいね', 0xFFFF6B6B, ReactionCategory.basic),
  praise('praise', '✨', 'すごい', 0xFFFFD93D, ReactionCategory.basic),
  cheer('cheer', '💪', 'がんばれ', 0xFF6BCB77, ReactionCategory.basic),
  empathy('empathy', '🤝', 'わかる', 0xFF4D96FF, ReactionCategory.basic),
  balloon('balloon', '🎈', 'おいわい', 0xFFFF9800, ReactionCategory.basic),
  warm('warm', '☺️', 'ほっこり', 0xFFFFC1E3, ReactionCategory.basic),
  banana('banana', '🍌', 'バナナ', 0xFFFFE135, ReactionCategory.basic),

  // 記号 (LINE風)
  star('star', '⭐', 'スター', 0xFFFFD700, ReactionCategory.symbol),
  heartRed('heart_red', '❤️', '赤ハート', 0xFFFF0000, ReactionCategory.symbol),
  heartPink('heart_pink', '💗', 'ピンクハート', 0xFFFF69B4, ReactionCategory.symbol),
  heartBlue('heart_blue', '💙', '水色ハート', 0xFF87CEEB, ReactionCategory.symbol),
  sparkles('sparkles', '✨', 'キラキラ', 0xFFFFE4B5, ReactionCategory.symbol),
  fire('fire', '🔥', '情熱', 0xFFFF4500, ReactionCategory.symbol),
  thumbsup('thumbsup', '👍', 'グッド', 0xFFFFA500, ReactionCategory.symbol),
  ok('ok', '🙆', 'OK', 0xFF32CD32, ReactionCategory.symbol),
  clap('clap', '👏', '拍手', 0xFFFFDAB9, ReactionCategory.symbol),
  flower('flower', '🌸', '花', 0xFFFFB7C5, ReactionCategory.nature),

  // 表情
  smile('smile', '😊', 'ニコニコ', 0xFFFFE4B5, ReactionCategory.emotion),
  laugh('laugh', '😆', '大笑い', 0xFFFFE4B5, ReactionCategory.emotion),
  cryHappy('cry_happy', '😂', '嬉し泣き', 0xFFFFE4B5, ReactionCategory.emotion),
  wink('wink', '😉', 'ウィンク', 0xFFFFE4B5, ReactionCategory.emotion),
  kiss('kiss', '😘', 'キス', 0xFFFFE4B5, ReactionCategory.emotion),
  loveEyes('love_eyes', '😍', 'メロメロ', 0xFFFFE4B5, ReactionCategory.emotion),
  relief('relief', '😌', '安心', 0xFFFFE4B5, ReactionCategory.emotion),
  party('party', '🥳', 'パーティー', 0xFFFFE4B5, ReactionCategory.emotion),
  sunglasses('sunglasses', '😎', 'クール', 0xFFFFE4B5, ReactionCategory.emotion),

  // 自然・生き物
  cat('cat', '🐱', 'ネコ', 0xFFD3D3D3, ReactionCategory.nature),
  dog('dog', '🐶', 'イヌ', 0xFFD2B48C, ReactionCategory.nature),
  bear('bear', '🐻', 'クマ', 0xFF8B4513, ReactionCategory.nature),
  rabbit('rabbit', '🐰', 'ウサギ', 0xFFFFC0CB, ReactionCategory.nature),
  panda('panda', '🐼', 'パンダ', 0xFFFFFFFF, ReactionCategory.nature),
  sun('sun', '☀️', '太陽', 0xFFFFA500, ReactionCategory.nature),
  moon('moon', '🌙', '月', 0xFFFFFF00, ReactionCategory.nature),
  rainbow('rainbow', '🌈', '虹', 0xFF87CEEB, ReactionCategory.nature),

  // 食べ物・アイテム
  gift('gift', '🎁', 'プレゼント', 0xFFFF0000, ReactionCategory.item),
  trophy('trophy', '🏆', 'トロフィー', 0xFFFFD700, ReactionCategory.item),
  medal('medal', '🥇', 'メダル', 0xFFFFD700, ReactionCategory.item),
  music('music', '🎵', '音楽', 0xFF000000, ReactionCategory.item),
  coffee('coffee', '☕', 'コーヒー', 0xFF8B4513, ReactionCategory.item),
  beer('beer', '🍺', 'ビール', 0xFFFFD700, ReactionCategory.item),
  cake('cake', '🍰', 'ケーキ', 0xFFFFC0CB, ReactionCategory.item),
  sushi('sushi', '🍣', '寿司', 0xFFFF4500, ReactionCategory.item),
  rocket('rocket', '🚀', 'ロケット', 0xFF808080, ReactionCategory.item),
  onigiri('onigiri', '🍙', 'おにぎり', 0xFFFFFFFF, ReactionCategory.item);

  const ReactionType(
    this.value,
    this.emoji,
    this.label,
    this.colorValue,
    this.category,
  );

  final String value;
  final String emoji;
  final String label;
  final int colorValue;
  final ReactionCategory category;
}
