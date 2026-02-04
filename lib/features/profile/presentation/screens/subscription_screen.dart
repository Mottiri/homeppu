import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/subscription_service.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() =>
      _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  Package? _package;
  bool _loading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
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
    setState(() => _isProcessing = true);
    try {
      await SubscriptionService.instance.purchasePackage(_package!);
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
        setState(() => _isProcessing = false);
      }
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

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text(AppMessages.profile.premiumTitle),
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: AppColors.warmGradient,
            ),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppMessages.profile.premiumTitle,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppMessages.profile.premiumSubtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            priceLabel,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppMessages.profile.premiumPriceLabel,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      if (_loading) ...[
                        const SizedBox(height: 8),
                        Text(
                          AppMessages.loading.general,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        AppMessages.profile.premiumFeatureTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      _buildFeatureRow(
                        context,
                        AppMessages.profile.premiumFeatureEpic,
                        isReady: true,
                      ),
                      _buildFeatureRow(
                        context,
                        AppMessages.profile.premiumFeatureAds,
                        isReady: false,
                      ),
                      _buildFeatureRow(
                        context,
                        AppMessages.profile.premiumFeatureCircles,
                        isReady: false,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppMessages.profile.premiumNotice,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (!isSubscriber && !_isProcessing)
                              ? _purchase
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                          ),
                          child: Text(
                            isSubscriber
                                ? AppMessages.profile.premiumSubscribed
                                : AppMessages.label.purchase,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isProcessing)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.35),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: Colors.white,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppMessages.profile.premiumProcessing,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFeatureRow(
    BuildContext context,
    String text, {
    required bool isReady,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            isReady ? Icons.check_circle : Icons.schedule,
            color: isReady ? AppColors.success : AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (!isReady)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                AppMessages.profile.premiumComingSoon,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
