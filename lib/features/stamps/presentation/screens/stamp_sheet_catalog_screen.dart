import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/moderation_provider.dart';
import '../../../../shared/providers/virtue_shop_provider.dart';
import '../../../../shared/services/stamp_sheet_service.dart';
import '../../../../shared/services/virtue_shop_service.dart';

class StampSheetCatalogScreen extends ConsumerStatefulWidget {
  const StampSheetCatalogScreen({super.key});

  @override
  ConsumerState<StampSheetCatalogScreen> createState() =>
      _StampSheetCatalogScreenState();
}

class _StampSheetCatalogScreenState extends ConsumerState<StampSheetCatalogScreen> {
  final _sheetService = StampSheetService();
  final _virtueShopService = VirtueShopService();
  Future<List<StampSheetDefinition>>? _catalogFuture;

  @override
  void initState() {
    super.initState();
    _catalogFuture = _sheetService.fetchCatalog();
    Future.microtask(() => ref.invalidate(virtueShopConfigProvider));
  }

  bool _isSheetUnlocked(StampSheetDefinition sheet, UserModel? user) {
    if (sheet.rarity == 'common') return true;
    if (user == null) return false;
    if (sheet.rarity == 'epic' && user.isSubscriber) return true;
    return user.unlockedStampSheets.contains(sheet.unlockKey);
  }

  int _rarityRank(String rarity) {
    switch (rarity) {
      case 'common':
        return 0;
      case 'rare':
        return 1;
      case 'epic':
        return 2;
      default:
        return 99;
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  Future<void> _showSheetPreview({
    required StampSheetDefinition sheet,
    required bool unlocked,
    required UserModel user,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(sheet.displayName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppMessages.stamp.sheetRarityLabel(sheet.rarity),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(sheet.assetPath, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
        actions: [
          if (!unlocked && sheet.rarity == 'rare')
            FilledButton(
              onPressed: () async {
                final config = ref.read(virtueShopConfigProvider).valueOrNull;
                final cost = config?.costForStampSheet('rare');
                if (cost == null || cost <= 0) {
                  _toast(AppMessages.stamp.sheetConfigNotReady, error: true);
                  return;
                }
                final confirmed = await showDialog<bool>(
                  context: dialogContext,
                  builder: (_) => AlertDialog(
                    title: Text(AppMessages.confirm.purchaseVirtueTitle),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppMessages.confirm.purchaseVirtueMessage(cost)),
                        const SizedBox(height: 8),
                        Text(AppMessages.confirm.virtueCostLabel(cost)),
                        const SizedBox(height: 4),
                        Text(
                          user.virtue >= cost
                              ? AppMessages.confirm.virtueBalanceAfterPurchase(
                                  user.virtue,
                                  cost,
                                )
                              : AppMessages.confirm.virtueBalanceShortage(
                                  user.virtue,
                                  cost,
                                ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: Text(AppMessages.label.cancel),
                      ),
                      FilledButton(
                        onPressed: user.virtue >= cost
                            ? () => Navigator.of(dialogContext).pop(true)
                            : null,
                        child: Text(AppMessages.label.purchase),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                try {
                  await _virtueShopService.purchaseVirtueItem(
                    itemType: 'stamp_sheet',
                    itemId: sheet.id,
                  );
                  ref.invalidate(currentUserProvider);
                  ref.invalidate(virtueStatusProvider);
                  ref.invalidate(virtueHistoryProvider);
                  ref.invalidate(virtueShopConfigProvider);
                  if (!context.mounted) return;
                  final navigator = Navigator.of(dialogContext);
                  if (navigator.canPop()) {
                    navigator.pop();
                  }
                  _toast(AppMessages.success.purchaseCompleted);
                } on FirebaseFunctionsException catch (e) {
                  final reason = (e.details is Map) ? e.details['reason'] : null;
                  if (reason == AppMessages.reasonItemNotPurchasable) {
                    _toast(AppMessages.error.itemNotPurchasable, error: true);
                    ref.invalidate(virtueShopConfigProvider);
                  } else {
                    _toast(AppMessages.error.purchaseFailedTitle, error: true);
                  }
                } catch (_) {
                  _toast(AppMessages.error.purchaseFailedTitle, error: true);
                }
              },
              child: Text(AppMessages.label.purchase),
            ),
          if (!unlocked && sheet.rarity == 'epic')
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.push('/premium');
              },
              child: Text(AppMessages.confirm.premiumSubscribeTitle),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppMessages.label.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppMessages.stamp.designCatalogTitle)),
        body: Center(child: Text(AppMessages.error.loginRequired)),
      );
    }

    final primaryColor = user.headerPrimaryColor != null
        ? Color(user.headerPrimaryColor!)
        : AppColors.primary;
    final secondaryColor = user.headerSecondaryColor != null
        ? Color(user.headerSecondaryColor!)
        : AppColors.secondary;
    final userGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        primaryColor.withValues(alpha: 0.25),
        secondaryColor.withValues(alpha: 0.15),
        const Color(0xFFFDF8F3),
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    final topInset = MediaQuery.paddingOf(context).top;
    final appBarReservedHeight = topInset + kToolbarHeight;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(AppMessages.stamp.designCatalogTitle),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: userGradient),
        child: Padding(
          padding: EdgeInsets.only(top: appBarReservedHeight),
          child: FutureBuilder<List<StampSheetDefinition>>(
            future: _catalogFuture,
            builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }
            final allSheets = snapshot.data!;
            final configAsync = ref.watch(virtueShopConfigProvider);
            if (configAsync.isLoading && !configAsync.hasValue) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }
            final shopConfig = configAsync.valueOrNull;
            final sheets = allSheets.where((sheet) {
              if (_isSheetUnlocked(sheet, user)) return true;
              return !(shopConfig?.isNonPurchasable('stamp_sheet', sheet.id) ?? false);
            }).toList();
            final sortedSheets = [...sheets]..sort((a, b) {
              final rarityCompare =
                  _rarityRank(a.rarity).compareTo(_rarityRank(b.rarity));
              if (rarityCompare != 0) return rarityCompare;

              final aUnlocked = _isSheetUnlocked(a, user);
              final bUnlocked = _isSheetUnlocked(b, user);
              if (aUnlocked != bUnlocked) return aUnlocked ? -1 : 1;

              return a.id.compareTo(b.id);
            });
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              itemCount: sortedSheets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 18,
                mainAxisSpacing: 18,
                childAspectRatio: 0.78,
              ),
              itemBuilder: (context, index) {
                final sheet = sortedSheets[index];
                final unlocked = _isSheetUnlocked(sheet, user);
                return GestureDetector(
                  onTap: () =>
                      _showSheetPreview(sheet: sheet, unlocked: unlocked, user: user),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(sheet.assetPath, fit: BoxFit.contain),
                            if (!unlocked)
                              Container(
                                color: Colors.black.withValues(alpha: 0.18),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: unlocked ? AppColors.success : AppColors.textSecondary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Icon(
                            unlocked ? Icons.check : Icons.lock_outline,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
            },
          ),
        ),
      ),
    );
  }
}
