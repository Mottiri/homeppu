import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/ad_config.dart';

class InterstitialAdService {
  InterstitialAdService._();

  static final InterstitialAdService instance = InterstitialAdService._();

  InterstitialAd? _interstitialAd;
  bool _isLoading = false;

  Future<void> preload() async {
    if (_isLoading) return;
    if (_interstitialAd != null) return;
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (AdConfig.interstitialAdUnitId.isEmpty) return;

    _isLoading = true;
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          _isLoading = false;
        },
      ),
    );
  }

  Future<bool> showIfAvailable() async {
    final ad = _interstitialAd;
    if (ad == null) {
      unawaited(preload());
      return false;
    }

    _interstitialAd = null;
    final completer = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(true);
        unawaited(preload());
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(false);
        unawaited(preload());
      },
    );

    ad.show();
    return completer.future;
  }
}
