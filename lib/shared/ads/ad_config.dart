import 'dart:io';

import 'package:flutter/foundation.dart';

class AdConfig {
  AdConfig._();

  // Test App IDs (AdMob)
  static const String _testAppIdAndroid =
      'ca-app-pub-3940256099942544~3347511713';
  static const String _testAppIdIos =
      'ca-app-pub-3940256099942544~1458002511';

  // Test Ad Unit IDs (AdMob)
  static const String _testBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testBannerIos =
      'ca-app-pub-3940256099942544/2934735716';
  static const String _testRewardedAndroid =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _testRewardedIos =
      'ca-app-pub-3940256099942544/1712485313';
  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';

  static String get appId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) return _testAppIdAndroid;
    if (Platform.isIOS) return _testAppIdIos;
    return '';
  }

  static String get bannerAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) return _testBannerAndroid;
    if (Platform.isIOS) return _testBannerIos;
    return '';
  }

  static String get rewardedAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) return _testRewardedAndroid;
    if (Platform.isIOS) return _testRewardedIos;
    return '';
  }

  static String get interstitialAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) return _testInterstitialAndroid;
    if (Platform.isIOS) return _testInterstitialIos;
    return '';
  }
}
