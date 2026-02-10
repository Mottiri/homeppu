import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_messages.dart';
import '../ads/ad_config.dart';
import '../providers/auth_provider.dart';

class NativeFeedAdCard extends ConsumerStatefulWidget {
  const NativeFeedAdCard({super.key});

  @override
  ConsumerState<NativeFeedAdCard> createState() => _NativeFeedAdCardState();
}

class _NativeFeedAdCardState extends ConsumerState<NativeFeedAdCard> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;
  bool _isFailed = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  void _loadAd() {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;
    if (AdConfig.nativeAdUnitId.isEmpty) return;
    if (AdConfig.nativeAdFactoryId.isEmpty) return;

    final ad = NativeAd(
      adUnitId: AdConfig.nativeAdUnitId,
      factoryId: AdConfig.nativeAdFactoryId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _isLoaded = true;
            _isFailed = false;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _isLoaded = false;
            _isFailed = true;
          });
        },
      ),
    );

    _nativeAd = ad;
    ad.load();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isSubscriber = user?.isSubscriber ?? false;
    if (isSubscriber) return const SizedBox.shrink();
    if (!Platform.isAndroid) return const SizedBox.shrink();
    if (_isFailed) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              AppMessages.home.nativeAdLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 280,
              child: _isLoaded && _nativeAd != null
                  ? AdWidget(ad: _nativeAd!)
                  : Container(
                      color: AppColors.backgroundSecondary,
                      alignment: Alignment.center,
                      child: Text(
                        AppMessages.home.nativeAdLoading,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
