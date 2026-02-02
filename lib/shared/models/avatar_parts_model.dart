class AvatarParts {
  final String hairId;
  final String eyebrowsId;
  final String eyesId;
  final String mouthId;
  static const String defaultEyebrowsId = 'eyebrows_01';

  const AvatarParts({
    required this.hairId,
    required this.eyebrowsId,
    required this.eyesId,
    required this.mouthId,
  });

  AvatarParts copyWith({
    String? hairId,
    String? eyebrowsId,
    String? eyesId,
    String? mouthId,
  }) {
    return AvatarParts(
      hairId: hairId ?? this.hairId,
      eyebrowsId: eyebrowsId ?? this.eyebrowsId,
      eyesId: eyesId ?? this.eyesId,
      mouthId: mouthId ?? this.mouthId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hairId': hairId,
      'eyebrowsId': eyebrowsId,
      'eyesId': eyesId,
      'mouthId': mouthId,
    };
  }

  static AvatarParts? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final hairId = raw['hairId'] as String?;
    final eyebrowsId =
        raw['eyebrowsId'] as String? ?? AvatarParts.defaultEyebrowsId;
    final eyesId = raw['eyesId'] as String?;
    final mouthId = raw['mouthId'] as String?;
    if (hairId == null || eyesId == null || mouthId == null) {
      return null;
    }
    return AvatarParts(
      hairId: hairId,
      eyebrowsId: eyebrowsId,
      eyesId: eyesId,
      mouthId: mouthId,
    );
  }
}
