// Name part model
class NamePartModel {
  final String id;
  final String text;
  final String category;
  final String rarity; // 'common', 'rare', 'epic'
  final String type; // 'prefix', 'suffix'
  final int order;
  final bool unlocked;

  NamePartModel({
    required this.id,
    required this.text,
    required this.category,
    required this.rarity,
    required this.type,
    required this.order,
    this.unlocked = false,
  });

  factory NamePartModel.fromMap(Map<String, dynamic> map) {
    final rawRarity = map['rarity'] ?? 'common';
    final rarity = (rawRarity == 'common' || rawRarity == 'rare' || rawRarity == 'epic')
        ? rawRarity
        : 'common';
    return NamePartModel(
      id: map['id'] ?? '',
      text: map['text'] ?? '',
      category: map['category'] ?? '',
      rarity: rarity,
      type: map['type'] ?? 'prefix',
      order: map['order'] ?? 0,
      unlocked: map['unlocked'] ?? false,
    );
  }

  bool get isCommon => rarity == 'common';

  int get rarityColor {
    switch (rarity) {
      case 'common':
        return 0xFFB0BEC5;
      case 'rare':
        return 0xFF64B5F6;
      case 'epic':
        return 0xFF9575CD;
      default:
        return 0xFFB0BEC5;
    }
  }

  String get rarityDisplayName {
    switch (rarity) {
      case 'rare':
        return 'レア';
      case 'epic':
        return 'エピック';
      default:
        return '一般';
    }
  }

  String get categoryDisplayName {
    switch (category) {
      case 'positive':
        return 'ポジティブ系';
      case 'relaxed':
        return 'ゆるい系';
      case 'effort':
        return '努力系';
      case 'animal':
        return '動物系';
      case 'funny':
        return 'おもしろ系';
      case 'legendary':
        return '伝説級';
      case 'nature':
        return '自然系';
      case 'food':
        return '食べ物系';
      case 'occupation':
        return '職業風';
      default:
        return 'その他';
    }
  }
}
