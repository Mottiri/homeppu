import 'dart:io';

import 'package:flutter/foundation.dart';

class AdConfig {
  AdConfig._();

  // Test App IDs (AdMob)
  static const String _testAppIdAndroid =
      'ca-app-pub-3940256099942544~3347511713';
  static const String _testAppIdIos =
      'ca-app-pub-3940256099942544~1458002511';

  // Production App IDs (AdMob)
  static const String _prodAppIdAndroid =
      'ca-app-pub-1657519829320845~8617369574';

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
  static const String _testNativeAndroid =
      'ca-app-pub-3940256099942544/2247696110';
  static const String _testNativeIos =
      'ca-app-pub-3940256099942544/3986624511';

  // Production Ad Unit IDs (AdMob)
  static const String _prodBannerAndroid =
      'ca-app-pub-1657519829320845/9506124421';
  static const String _prodRewardedAndroid =
      'ca-app-pub-1657519829320845/9723401836';
  static const String _prodInterstitialAndroid =
      'ca-app-pub-1657519829320845/7809899376';
  static const String _prodNativeAndroid =
      'ca-app-pub-1657519829320845/8354479844';

  static bool get _isAndroidRelease => !kIsWeb && Platform.isAndroid && kReleaseMode;

  static String get appId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) {
      return _isAndroidRelease ? _prodAppIdAndroid : _testAppIdAndroid;
    }
    if (Platform.isIOS) return _testAppIdIos;
    return '';
  }

  static String get bannerAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) {
      return _isAndroidRelease ? _prodBannerAndroid : _testBannerAndroid;
    }
    if (Platform.isIOS) return _testBannerIos;
    return '';
  }

  static String get rewardedAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) {
      return _isAndroidRelease ? _prodRewardedAndroid : _testRewardedAndroid;
    }
    if (Platform.isIOS) return _testRewardedIos;
    return '';
  }

  static String get interstitialAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) {
      return _isAndroidRelease
          ? _prodInterstitialAndroid
          : _testInterstitialAndroid;
    }
    if (Platform.isIOS) return _testInterstitialIos;
    return '';
  }

  static String get nativeAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) {
      return _isAndroidRelease ? _prodNativeAndroid : _testNativeAndroid;
    }
    if (Platform.isIOS) return _testNativeIos;
    return '';
  }

  static String get nativeAdFactoryId {
    if (Platform.isAndroid) return 'homeNative';
    if (Platform.isIOS) return '';
    return '';
  }
}
