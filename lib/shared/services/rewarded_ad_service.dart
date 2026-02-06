import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/ad_config.dart';

class RewardedAdService {
  RewardedAdService._();

  static final RewardedAdService instance = RewardedAdService._();

  RewardedAd? _rewardedAd;
  bool _isLoading = false;

  Future<bool> _load() async {
    if (_isLoading) return false;
    if (kIsWeb) return false;
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    if (AdConfig.rewardedAdUnitId.isEmpty) return false;

    _isLoading = true;
    final completer = Completer<bool>();

    RewardedAd.load(
      adUnitId: AdConfig.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isLoading = false;
          completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
          _isLoading = false;
          completer.complete(false);
        },
      ),
    );

    return completer.future;
  }

  Future<bool> show({required VoidCallback onEarned}) async {
    if (_rewardedAd == null) {
      final loaded = await _load();
      if (!loaded || _rewardedAd == null) return false;
    }

    final completer = Completer<bool>();
    var rewarded = false;

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        if (!completer.isCompleted) completer.complete(rewarded);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        rewarded = true;
        onEarned();
      },
    );

    return completer.future;
  }
}
