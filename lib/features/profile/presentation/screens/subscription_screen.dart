import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/subscription_service.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen>
    with SingleTickerProviderStateMixin {
  Package? _package;
  bool _loading = true;
  bool _isProcessing = false;
  bool _isAwaitingSubscriptionSync = false;
  static const String _androidManageUrl =
      'https://play.google.com/store/account/subscriptions?package=com.homeppu.homeppu';

  // ヒーローアイコンのアニメーション
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _loadOfferings();

    // グローアニメーション初期化
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.15, end: 0.45).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _loadOfferings() async {
    final offerings = await SubscriptionService.instance.getOfferings();
    final current = offerings?.current;
    Package? package;
    if (current?.monthly != null) {
      package = current!.monthly;
    } else if (current?.availablePackages.isNotEmpty ?? false) {
      package = current!.availablePackages.first;
    }
    if (mounted) {
      setState(() {
        _package = package;
        _loading = false;
      });
    }
  }

  Future<void> _purchase() async {
    if (_package == null) {
      _showPurchaseFailedDialog();
      return;
    }
    var purchaseSucceeded = false;
    setState(() => _isProcessing = true);
    try {
      await SubscriptionService.instance.purchasePackage(_package!);
      purchaseSucceeded = true;
      ref.invalidate(currentUserProvider);
      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          AppMessages.success.purchaseCompleted,
        );
      }
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode != PurchasesErrorCode.purchaseCancelledError && mounted) {
        _showPurchaseFailedDialog();
      }
    } catch (_) {
      if (mounted) {
        _showPurchaseFailedDialog();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          if (purchaseSucceeded) {
            _isAwaitingSubscriptionSync = true;
          }
        });
      }
    }
  }

  Future<void> _openManageSubscription() async {
    final info = await SubscriptionService.instance.getCustomerInfo();
    final urlString = info?.managementURL;
    final uri = Uri.parse(
      urlString?.isNotEmpty == true ? urlString! : _androidManageUrl,
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      SnackBarHelper.showError(context, AppMessages.error.general);
    }
  }

  void _showPurchaseFailedDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(AppMessages.error.purchaseFailedTitle),
          content: Text(AppMessages.error.purchaseFailedSupport),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppMessages.label.close),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (mounted) {
                  context.push('/inquiry');
                }
              },
              child: Text(AppMessages.profile.inquiryTitle),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isSubscriber = user?.isSubscriber ?? false;
    final priceLabel = _package?.storeProduct.priceString ?? '¥500';
    final isAwaitingSync = _isAwaitingSubscriptionSync && !isSubscriber;

    if (_isAwaitingSubscriptionSync && isSubscriber) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _isAwaitingSubscriptionSync = false);
      });
    }

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(AppMessages.profile.premiumTitle),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          extendBodyBehindAppBar: true,
          body: Container(
            decoration: const BoxDecoration(gradient: AppColors.warmGradient),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  const SizedBox(height: 16),

                  // ヒーローアイコン（アニメーション付き）
                  _buildHeroIcon(),
                  const SizedBox(height: 24),

                  // 価格表示（大きく強調）
                  _buildPriceDisplay(priceLabel),
                  const SizedBox(height: 24),

                  // 機能リストカード（ガラスモーフィズム風）
                  _buildFeatureCard(),
                  const SizedBox(height: 24),

                  // 購入ボタン
                  _buildPurchaseButton(
                    isSubscriber: isSubscriber,
                    isAwaitingSync: isAwaitingSync,
                  ),
                  const SizedBox(height: 16),

                  // 注意書き
                  Text(
                    AppMessages.profile.premiumNotice,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),

        // 購入処理中オーバーレイ（ブラー + カード）
        if (_isProcessing) _buildProcessingOverlay(),
      ],
    );
  }

  Widget _buildHeroIcon() {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(
                    alpha: _glowAnimation.value,
                  ),
                  blurRadius: 30,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.accent, AppColors.secondary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                size: 56,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPriceDisplay(String priceLabel) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              priceLabel,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                AppMessages.profile.premiumPriceLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (_loading) ...[
          const SizedBox(height: 8),
          Text(
            AppMessages.loading.general,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _buildFeatureCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppMessages.profile.premiumFeatureTitle,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildFeatureRow(
            AppMessages.profile.premiumFeatureEpic,
            isReady: true,
          ),
          _buildFeatureRow(
            AppMessages.profile.premiumFeatureAds,
            isReady: true,
          ),
          _buildFeatureRow(
            AppMessages.profile.premiumFeatureCircles,
            isReady: true,
          ),
          _buildFeatureRow(
            AppMessages.profile.premiumFeatureProfileImage,
            isReady: true,
          ),
          _buildFeatureRow(
            AppMessages.profile.premiumFeatureHeaderImage,
            isReady: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(String text, {required bool isReady}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isReady
                  ? AppColors.success.withValues(alpha: 0.15)
                  : AppColors.warning.withValues(alpha: 0.15),
            ),
            child: Icon(
              isReady ? Icons.check_rounded : Icons.schedule_rounded,
              color: isReady ? AppColors.success : AppColors.warning,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (!isReady)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                AppMessages.profile.premiumComingSoon,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPurchaseButton({
    required bool isSubscriber,
    required bool isAwaitingSync,
  }) {
    final disableButton = _isProcessing || isAwaitingSync;
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: disableButton
            ? null
            : isSubscriber
            ? _openManageSubscription
            : _purchase,
        child: isAwaitingSync
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    AppMessages.profile.premiumActivationInProgress,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            : Text(
                isSubscriber
                    ? AppMessages.profile.premiumManage
                    : AppMessages.label.purchase,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          color: Colors.black.withValues(alpha: 0.2),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    AppMessages.profile.premiumProcessing,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppMessages.profile.premiumProcessingWait,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
