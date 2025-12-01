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
  static const String reactionLove = 'love';        // いいね
  static const String reactionPraise = 'praise';    // すごい
  static const String reactionCheer = 'cheer';      // がんばれ
  static const String reactionEmpathy = 'empathy';  // わかる

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
  static const int aiMinDelay = 60000;     // 最小1分
  static const int aiMaxDelay = 10800000;  // 最大3時間

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

/// リアクションの種類
enum ReactionType {
  love('love', '❤️', 'いいね', 0xFFFF6B6B),
  praise('praise', '✨', 'すごい', 0xFFFFD93D),
  cheer('cheer', '💪', 'がんばれ', 0xFF6BCB77),
  empathy('empathy', '🤝', 'わかる', 0xFF4D96FF);

  const ReactionType(this.value, this.emoji, this.label, this.colorValue);
  
  final String value;
  final String emoji;
  final String label;
  final int colorValue;
}


