/// 名前パーツモデル
class NamePartModel {
  final String id;
  final String text;
  final String category;
  final String rarity;  // 'normal', 'rare', 'super_rare', 'ultra_rare'
  final String type;    // 'prefix', 'suffix'
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
    return NamePartModel(
      id: map['id'] ?? '',
      text: map['text'] ?? '',
      category: map['category'] ?? '',
      rarity: map['rarity'] ?? 'normal',
      type: map['type'] ?? 'prefix',
      order: map['order'] ?? 0,
      unlocked: map['unlocked'] ?? false,
    );
  }

  /// レア度に応じた色を取得
  int get rarityColor {
    switch (rarity) {
      case 'rare':
        return 0xFF4FC3F7;  // 水色
      case 'super_rare':
        return 0xFFFFD54F;  // 金色
      case 'ultra_rare':
        return 0xFFE040FB;  // 紫
      default:
        return 0xFF9E9E9E;  // グレー
    }
  }

  /// レア度の表示名を取得
  String get rarityDisplayName {
    switch (rarity) {
      case 'rare':
        return 'レア';
      case 'super_rare':
        return 'スーパーレア';
      case 'ultra_rare':
        return 'ウルトラレア';
      default:
        return 'ノーマル';
    }
  }

  /// カテゴリの表示名を取得
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
        return category;
    }
  }
}

