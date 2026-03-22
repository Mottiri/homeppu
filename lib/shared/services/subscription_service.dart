import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class SubscriptionService {
  SubscriptionService._();

  static final SubscriptionService instance = SubscriptionService._();

  bool _configured = false;

  Future<void> _configureIfNeeded() async {
    if (_configured) return;

    const apiKey = String.fromEnvironment('REVENUECAT_API_KEY');
    if (apiKey.isEmpty) {
      debugPrint('RevenueCat API key is not set. Skipping configuration.');
      return;
    }

    try {
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }
      await Purchases.configure(PurchasesConfiguration(apiKey));
      _configured = true;
      if (kDebugMode) {
        debugPrint('RevenueCat configured.');
      }
    } catch (e) {
      debugPrint('RevenueCat configure failed: $e');
    }
  }

  Future<void> logIn(String uid) async {
    await _configureIfNeeded();
    if (!_configured) return;
    try {
      await Purchases.logIn(uid);
      if (kDebugMode) {
        debugPrint('RevenueCat logIn success: $uid');
      }
    } catch (e) {
      debugPrint('RevenueCat logIn failed: $e');
    }
  }

  Future<Offerings?> getOfferings() async {
    await _configureIfNeeded();
    if (!_configured) return null;
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      debugPrint('RevenueCat getOfferings failed: $e');
      return null;
    }
  }

  Future<CustomerInfo?> getCustomerInfo() async {
    await _configureIfNeeded();
    if (!_configured) return null;
    try {
      return await Purchases.getCustomerInfo();
    } catch (e) {
      debugPrint('RevenueCat getCustomerInfo failed: $e');
      return null;
    }
  }

  Future<void> purchasePackage(Package package) async {
    await _configureIfNeeded();
    if (!_configured) {
      throw StateError('RevenueCat is not configured.');
    }
    await Purchases.purchase(PurchaseParams.package(package));
  }

  Future<void> restorePurchases() async {
    await _configureIfNeeded();
    if (!_configured) {
      throw StateError('RevenueCat is not configured.');
    }
    await Purchases.restorePurchases();
  }

  Future<void> logOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
      if (kDebugMode) {
        debugPrint('RevenueCat logOut success');
      }
    } catch (e) {
      debugPrint('RevenueCat logOut failed: $e');
    }
  }
}
