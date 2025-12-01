/// AI設定
/// APIキーはCloud Functionsの環境変数で管理（セキュリティ対策）
class AIConfig {
  AIConfig._();

  // AIキャラクターのペルソナ一覧（表示用）
  static const List<AIPersona> personas = [
    AIPersona(
      id: 'ai_yuuki',
      name: 'ゆうき',
      avatarIndex: 0,
      personality: '明るく元気な大学生',
    ),
    AIPersona(
      id: 'ai_sakura',
      name: 'さくら',
      avatarIndex: 1,
      personality: '優しくて穏やかな社会人女性',
    ),
    AIPersona(
      id: 'ai_kenta',
      name: 'けんた',
      avatarIndex: 2,
      personality: '熱血で応援好きな社会人男性',
    ),
    AIPersona(
      id: 'ai_mio',
      name: 'みお',
      avatarIndex: 3,
      personality: '知的で落ち着いた大人の女性',
    ),
    AIPersona(
      id: 'ai_souta',
      name: 'そうた',
      avatarIndex: 4,
      personality: '面白くて明るい若者',
    ),
    AIPersona(
      id: 'ai_hana',
      name: 'はな',
      avatarIndex: 5,
      personality: '癒し系で優しいお姉さん',
    ),
  ];
}

/// AIペルソナ
class AIPersona {
  final String id;
  final String name;
  final int avatarIndex;
  final String personality;

  const AIPersona({
    required this.id,
    required this.name,
    required this.avatarIndex,
    required this.personality,
  });
}
