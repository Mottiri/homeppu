import 'package:cloud_functions/cloud_functions.dart';

class VirtueShopConfig {
  final Map<String, int> namePartCostsByRarity;
  final Map<String, int> avatarPartCostsByRarity;
  final Map<String, int> reactionCostsById;

  const VirtueShopConfig({
    required this.namePartCostsByRarity,
    required this.avatarPartCostsByRarity,
    required this.reactionCostsById,
  });

  factory VirtueShopConfig.fromMap(Map<String, dynamic> map) {
    Map<String, int> toIntMap(dynamic value) {
      if (value is! Map) return {};
      return value.map(
        (key, v) => MapEntry(
          key.toString(),
          v is num ? v.toInt() : 0,
        ),
      )..removeWhere((key, value) => value <= 0);
    }

    final namePartCostsByRarity = toIntMap(map['namePartCostsByRarity']);
    final avatarPartCostsByRarity = map['avatarPartCostsByRarity'] != null
        ? toIntMap(map['avatarPartCostsByRarity'])
        : namePartCostsByRarity;
    return VirtueShopConfig(
      namePartCostsByRarity: namePartCostsByRarity,
      avatarPartCostsByRarity: avatarPartCostsByRarity,
      reactionCostsById: toIntMap(map['reactionCostsById']),
    );
  }

  int? costForNamePart(String rarity) => namePartCostsByRarity[rarity];
  int? costForAvatarPart(String rarity) => avatarPartCostsByRarity[rarity];
  int? costForReaction(String reactionId) => reactionCostsById[reactionId];
}

class VirtueShopService {
  final FirebaseFunctions _functions;

  VirtueShopService()
    : _functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  Future<VirtueShopConfig> getConfig() async {
    final callable = _functions.httpsCallable('getVirtueShopConfig');
    final result = await callable.call();
    final data = Map<String, dynamic>.from(result.data as Map);
    return VirtueShopConfig.fromMap(data);
  }

  Future<void> purchaseVirtueItem({
    required String itemType,
    required String itemId,
  }) async {
    final callable = _functions.httpsCallable('purchaseVirtueItem');
    try {
      await callable.call({
        'itemType': itemType,
        'itemId': itemId,
      });
    } on FirebaseFunctionsException catch (e) {
      // Keep UI message generic, but expose structured details for diagnosis.
      // ignore: avoid_print
      print(
        '[VirtueShopService] purchaseVirtueItem failed: '
        'itemType=$itemType itemId=$itemId '
        'code=${e.code} message=${e.message} details=${e.details}',
      );
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print(
        '[VirtueShopService] purchaseVirtueItem unexpected error: '
        'itemType=$itemType itemId=$itemId error=$e',
      );
      rethrow;
    }
  }
}
