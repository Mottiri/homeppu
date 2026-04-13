import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

class AppCheckService {
  AppCheckService._();

  static Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kReleaseMode
            ? const AndroidPlayIntegrityProvider()
            : const AndroidDebugProvider(),
      );
    } catch (error, stackTrace) {
      debugPrint('[AppCheck] Init failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
