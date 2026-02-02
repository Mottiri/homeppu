import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/virtue_shop_service.dart';

final virtueShopConfigProvider = FutureProvider.autoDispose<VirtueShopConfig>((
  ref,
) async {
  return VirtueShopService().getConfig();
});
