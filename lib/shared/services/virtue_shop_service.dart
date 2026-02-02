import 'package:cloud_functions/cloud_functions.dart';

class VirtueShopConfig {
  final Map<String, int> namePartCostsByRarity;
  final Map<String, int> reactionCostsById;

  const VirtueShopConfig({
    required this.namePartCostsByRarity,
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

    return VirtueShopConfig(
      namePartCostsByRarity: toIntMap(map['namePartCostsByRarity']),
      reactionCostsById: toIntMap(map['reactionCostsById']),
    );
  }

  int? costForNamePart(String rarity) => namePartCostsByRarity[rarity];
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
    await callable.call({
      'itemType': itemType,
      'itemId': itemId,
    });
  }
}
