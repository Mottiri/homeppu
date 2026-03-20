import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/constants/app_constants.dart';

class SubscriptionService {
  SubscriptionService._();

  static final SubscriptionService instance = SubscriptionService._();

  bool _configured = false;
  bool _listenerAttached = false;
  DateTime? _lastSyncAt;
  static const _minSyncInterval = Duration(seconds: 30);

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

  /// Cloud Functionを呼び出してサブスクリプション状態を同期。
  /// [force] trueで30秒debounceをバイパス（購入直後など）。
  Future<bool> syncSubscriptionStatus({bool force = false}) async {
    if (!force && _lastSyncAt != null) {
      final elapsed = DateTime.now().difference(_lastSyncAt!);
      if (elapsed < _minSyncInterval) {
        if (kDebugMode) {
          debugPrint(
            'syncSubscriptionStatus skipped (debounce: ${elapsed.inSeconds}s)',
          );
        }
        return false;
      }
    }

    try {
      final functions = FirebaseFunctions.instanceFor(
        region: AppConstants.functionsRegion,
      );
      final callable = functions.httpsCallable(
        'syncSubscriptionStatus',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final result = await callable.call();
      _lastSyncAt = DateTime.now();
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['isSubscriber'] == true;
    } catch (e) {
      debugPrint('syncSubscriptionStatus failed: $e');
      return false;
    }
  }

  /// CustomerInfoリスナーを登録（エンタイトルメント変更時に自動sync）。
  Future<void> attachCustomerInfoListener() async {
    if (_listenerAttached) return;
    await _configureIfNeeded();
    if (!_configured) return;
    _listenerAttached = true;

    Purchases.addCustomerInfoUpdateListener((_) {
      syncSubscriptionStatus();
    });

    if (kDebugMode) {
      debugPrint('RevenueCat CustomerInfo listener attached.');
    }
  }
}
