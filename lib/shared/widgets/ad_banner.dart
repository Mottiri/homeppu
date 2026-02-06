import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ads/ad_config.dart';
import '../providers/auth_provider.dart';

class AdBanner extends ConsumerStatefulWidget {
  final EdgeInsetsGeometry padding;
  final bool reserveSpace;

  const AdBanner({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.reserveSpace = true,
  });

  @override
  ConsumerState<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends ConsumerState<AdBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAdIfNeeded();
  }

  void _loadAdIfNeeded() {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (AdConfig.bannerAdUnitId.isEmpty) return;

    _bannerAd = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() => _isLoaded = false);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isSubscriber = user?.isSubscriber ?? false;
    if (isSubscriber) return const SizedBox.shrink();

    final height = AdSize.banner.height.toDouble();
    if (!_isLoaded || _bannerAd == null) {
      return widget.reserveSpace
          ? SizedBox(height: height)
          : const SizedBox.shrink();
    }

    return Padding(
      padding: widget.padding,
      child: SizedBox(
        height: height,
        child: AdWidget(ad: _bannerAd!),
      ),
    );
  }
}
