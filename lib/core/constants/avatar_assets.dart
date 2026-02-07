import '../../shared/models/avatar_parts_model.dart';

class AvatarAssets {
  static const String baseId = 'base_01';
  static const String basePath = 'assets/avatars/base/base_01.png';

  static const List<String> hairIds = ['hair_01', 'hair_02', 'hair_03', 'hair_04', 'hair_05'];
  static const List<String> eyesIds = ['eyes_01', 'eyes_02', 'eyes_03', 'eyes_04', 'eyes_05'];
  static const List<String> mouthIds = ['mouth_01', 'mouth_02', 'mouth_03', 'mouth_04', 'mouth_05'];
  static const List<String> eyebrowsIds = ['eyebrows_01', 'eyebrows_02', 'eyebrows_03', 'eyebrows_04', 'eyebrows_05', 'eyebrows_06'];
  static const Map<String, String> partRarity = {
    // hair
    'hair_01': 'common',
    'hair_02': 'common',
    'hair_03': 'epic',
    'hair_04': 'rare',
    'hair_05': 'rare',
    // eyebrows
    'eyebrows_01': 'common',
    'eyebrows_02': 'common',
    'eyebrows_03': 'common',
    'eyebrows_04': 'epic',
    'eyebrows_05': 'rare',
    'eyebrows_06': 'rare',
    // eyes
    'eyes_01': 'common',
    'eyes_02': 'common',
    'eyes_03': 'epic',
    'eyes_04': 'rare',
    'eyes_05': 'rare',
    // mouth
    'mouth_01': 'common',
    'mouth_02': 'common',
    'mouth_03': 'epic',
    'mouth_04': 'rare',
    'mouth_05': 'rare',
  };
  static const Map<String, String> partAssetNameById = {
    // hair
    'hair_01': 'hair_01',
    'hair_02': 'hair_02',
    'hair_03': 'hair_03',
    'hair_04': 'hair_04',
    'hair_05': 'hair_05_rare',
    // eyebrows
    'eyebrows_01': 'eyebrows_01',
    'eyebrows_02': 'eyebrows_02',
    'eyebrows_03': 'eyebrows_03',
    'eyebrows_04': 'eyebrows_04',
    'eyebrows_05': 'eyebrows_05',
    'eyebrows_06': 'eyebrows_06',
    // eyes
    'eyes_01': 'eyes_01',
    'eyes_02': 'eyes_02',
    'eyes_03': 'eyes_03',
    'eyes_04': 'eyes_04',
    'eyes_05': 'eyes_05',
    // mouth
    'mouth_01': 'mouth_01',
    'mouth_02': 'mouth_02',
    'mouth_03': 'mouth_03',
    'mouth_04': 'mouth_04',
    'mouth_05': 'mouth_05',
  };

  static String hairPath(String id) => 'assets/avatars/hair/${partAssetNameById[id] ?? id}.png';
  static String eyesPath(String id) => 'assets/avatars/eyes/${partAssetNameById[id] ?? id}.png';
  static String mouthPath(String id) => 'assets/avatars/mouth/${partAssetNameById[id] ?? id}.png';
  static String eyebrowsPath(String id) => 'assets/avatars/eyebrows/${partAssetNameById[id] ?? id}.png';

  static AvatarParts defaultParts() {
    return AvatarParts(
      hairId: hairIds.first,
      eyesId: eyesIds.first,
      mouthId: mouthIds.first,
      eyebrowsId: eyebrowsIds.first,
    );
  }
}
