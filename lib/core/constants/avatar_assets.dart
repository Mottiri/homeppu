import '../../shared/models/avatar_parts_model.dart';

class AvatarAssets {
  static const String baseId = 'base_01';
  static const String basePath = 'assets/avatars/base/base_01.png';

  static const List<String> hairIds = ['hair_01', 'hair_02'];
  static const List<String> eyesIds = ['eyes_01', 'eyes_02'];
  static const List<String> mouthIds = ['mouth_01', 'mouth_02'];
  static const List<String> eyebrowsIds = ['eyebrows_01', 'eyebrows_02'];

  static String hairPath(String id) => 'assets/avatars/hair/$id.png';
  static String eyesPath(String id) => 'assets/avatars/eyes/$id.png';
  static String mouthPath(String id) => 'assets/avatars/mouth/$id.png';
  static String eyebrowsPath(String id) => 'assets/avatars/eyebrows/$id.png';

  static AvatarParts defaultParts() {
    return AvatarParts(
      hairId: hairIds.first,
      eyesId: eyesIds.first,
      mouthId: mouthIds.first,
      eyebrowsId: eyebrowsIds.first,
    );
  }
}
