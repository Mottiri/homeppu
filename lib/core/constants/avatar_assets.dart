import '../../shared/models/avatar_parts_model.dart';

class AvatarAssets {
  static const String baseId = 'base_01';
  static const String basePath = 'assets/avatars/base/base_01.webp';

  static const List<String> hairIds = ['hair_01', 'hair_02', 'hair_03', 'hair_04', 'hair_05', 'hair_06', 'hair_07', 'hair_08', 'hair_09', 'hair_10', 'hair_11', 'hair_12', 'hair_13', 'hair_14', 'hair_15'];
  static const List<String> eyesIds = ['eyes_01', 'eyes_02', 'eyes_03', 'eyes_04', 'eyes_05', 'eyes_06', 'eyes_07', 'eyes_08', 'eyes_09', 'eyes_10', 'eyes_11', 'eyes_12', 'eyes_13', 'eyes_14', 'eyes_15', 'eyes_16'];
  static const List<String> mouthIds = ['mouth_01', 'mouth_02', 'mouth_03', 'mouth_04', 'mouth_05', 'mouth_06', 'mouth_07'];
  static const List<String> eyebrowsIds = ['eyebrows_01', 'eyebrows_02', 'eyebrows_03', 'eyebrows_04', 'eyebrows_05', 'eyebrows_06', 'eyebrows_07', 'eyebrows_08', 'eyebrows_09', 'eyebrows_10', 'eyebrows_11', 'eyebrows_12', 'eyebrows_13', 'eyebrows_14', 'eyebrows_15', 'eyebrows_16', 'eyebrows_17', 'eyebrows_18', 'eyebrows_19', 'eyebrows_20', 'eyebrows_21'];
  static const Map<String, String> partRarity = {
    // hair
    'hair_01': 'common',
    'hair_02': 'common',
    'hair_03': 'epic',
    'hair_04': 'rare',
    'hair_05': 'common',
    'hair_06': 'common',
    'hair_07': 'rare',
    'hair_08': 'rare',
    'hair_09': 'rare',
    'hair_10': 'epic',
    'hair_11': 'epic',
    'hair_12': 'epic',
    'hair_13': 'epic',
    'hair_14': 'epic',
    'hair_15': 'epic',
    // eyebrows
    'eyebrows_01': 'common',
    'eyebrows_02': 'common',
    'eyebrows_03': 'common',
    'eyebrows_04': 'epic',
    'eyebrows_05': 'rare',
    'eyebrows_06': 'rare',
    'eyebrows_07': 'epic',
    'eyebrows_08': 'epic',
    'eyebrows_09': 'epic',
    'eyebrows_10': 'epic',
    'eyebrows_11': 'epic',
    'eyebrows_12': 'epic',
    'eyebrows_13': 'epic',
    'eyebrows_14': 'rare',
    'eyebrows_15': 'rare',
    'eyebrows_16': 'epic',
    'eyebrows_17': 'epic',
    'eyebrows_18': 'rare',
    'eyebrows_19': 'rare',
    'eyebrows_20': 'rare',
    'eyebrows_21': 'rare',
    // eyes
    'eyes_01': 'common',
    'eyes_02': 'common',
    'eyes_03': 'epic',
    'eyes_04': 'rare',
    'eyes_05': 'rare',
    'eyes_06': 'rare',
    'eyes_07': 'rare',
    'eyes_08': 'common',
    'eyes_09': 'common',
    'eyes_10': 'common',
    'eyes_11': 'rare',
    'eyes_12': 'epic',
    'eyes_13': 'epic',
    'eyes_14': 'epic',
    'eyes_15': 'epic',
    'eyes_16': 'epic',
    // mouth
    'mouth_01': 'common',
    'mouth_02': 'common',
    'mouth_03': 'epic',
    'mouth_04': 'rare',
    'mouth_05': 'rare',
    'mouth_06': 'common',
    'mouth_07': 'rare',
  };
  static const Map<String, String> partAssetNameById = {
    // hair
    'hair_01': 'hair_01',
    'hair_02': 'hair_02',
    'hair_03': 'hair_03',
    'hair_04': 'hair_04',
    'hair_05': 'hair_05_common',
    'hair_06': 'hair_06_common',
    'hair_07': 'hair_07_rare',
    'hair_08': 'hair_08_rare',
    'hair_09': 'hair_09_rare',
    'hair_10': 'hair_10_epic',
    'hair_11': 'hair_11_epic',
    'hair_12': 'hair_12_epic',
    'hair_13': 'hair_13_epic',
    'hair_14': 'hair_14_epic',
    'hair_15': 'hair_15_epic',
    // eyebrows
    'eyebrows_01': 'eyebrows_01',
    'eyebrows_02': 'eyebrows_02',
    'eyebrows_03': 'eyebrows_03',
    'eyebrows_04': 'eyebrows_04',
    'eyebrows_05': 'eyebrows_05',
    'eyebrows_06': 'eyebrows_06',
    'eyebrows_07': 'eyebrows_07_epic',
    'eyebrows_08': 'eyebrows_08_epic',
    'eyebrows_09': 'eyebrows_09_epic',
    'eyebrows_10': 'eyebrows_10_epic',
    'eyebrows_11': 'eyebrows_11_epic',
    'eyebrows_12': 'eyebrows_12_epic',
    'eyebrows_13': 'eyebrows_13_epic',
    'eyebrows_14': 'eyebrows_14_rare',
    'eyebrows_15': 'eyebrows_15_rare',
    'eyebrows_16': 'eyebrows_16_epic',
    'eyebrows_17': 'eyebrows_17_epic',
    'eyebrows_18': 'eyebrows_18_rare',
    'eyebrows_19': 'eyebrows_19_rare',
    'eyebrows_20': 'eyebrows_20_rare',
    'eyebrows_21': 'eyebrows_21_rare',
    // eyes
    'eyes_01': 'eyes_01',
    'eyes_02': 'eyes_02',
    'eyes_03': 'eyes_03',
    'eyes_04': 'eyes_04',
    'eyes_05': 'eyes_05',
    'eyes_06': 'eyes_06_rare',
    'eyes_07': 'eyes_07_rare',
    'eyes_08': 'eyes_08_common',
    'eyes_09': 'eyes_09_common',
    'eyes_10': 'eyes_10_common',
    'eyes_11': 'eyes_11_rare',
    'eyes_12': 'eyes_12_epic',
    'eyes_13': 'eyes_13_epic',
    'eyes_14': 'eyes_14_epic',
    'eyes_15': 'eyes_15_epic',
    'eyes_16': 'eyes_16_epic',
    // mouth
    'mouth_01': 'mouth_01_common',
    'mouth_02': 'mouth_02_common',
    'mouth_03': 'mouth_03',
    'mouth_04': 'mouth_04',
    'mouth_05': 'mouth_05',
    'mouth_06': 'mouth_06_common',
    'mouth_07': 'mouth_07_rare',
  };

  static String hairPath(String id) => 'assets/avatars/hair/${partAssetNameById[id] ?? id}.webp';
  static String eyesPath(String id) => 'assets/avatars/eyes/${partAssetNameById[id] ?? id}.webp';
  static String mouthPath(String id) => 'assets/avatars/mouth/${partAssetNameById[id] ?? id}.webp';
  static String eyebrowsPath(String id) => 'assets/avatars/eyebrows/${partAssetNameById[id] ?? id}.webp';

  static AvatarParts defaultParts() {
    return AvatarParts(
      hairId: hairIds.first,
      eyesId: eyesIds.first,
      mouthId: mouthIds.first,
      eyebrowsId: eyebrowsIds.first,
    );
  }
}
