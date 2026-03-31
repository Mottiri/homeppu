import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/constants/avatar_assets.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/models/avatar_parts_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/moderation_provider.dart';
import '../../../../shared/providers/virtue_shop_provider.dart';
import '../../../../shared/services/virtue_shop_service.dart';
import '../../../../shared/widgets/avatar_parts_widget.dart';

enum _AvatarPartCategory { hair, eyebrows, eyes, mouth }

class AvatarEditScreen extends ConsumerStatefulWidget {
  final AvatarParts initialParts;
  final Set<String>? allowedRarities;

  const AvatarEditScreen({
    super.key,
    required this.initialParts,
    this.allowedRarities,
  });

  @override
  ConsumerState<AvatarEditScreen> createState() => _AvatarEditScreenState();
}

class _AvatarEditScreenState extends ConsumerState<AvatarEditScreen> {
  late AvatarParts _parts;
  _AvatarPartCategory _category = _AvatarPartCategory.hair;
  final _virtueShopService = VirtueShopService();
  bool _isOpeningLockedDialog = false;
  bool _isRefreshingVirtueConfig = false;

  @override
  void initState() {
    super.initState();
    _parts = _normalizePartsForAllowedRarities(widget.initialParts);
    Future.microtask(() => ref.invalidate(virtueShopConfigProvider));
  }

  List<String> get _currentIds {
    List<String> ids;
    switch (_category) {
      case _AvatarPartCategory.hair:
        ids = AvatarAssets.hairIds;
        break;
      case _AvatarPartCategory.eyebrows:
        ids = AvatarAssets.eyebrowsIds;
        break;
      case _AvatarPartCategory.eyes:
        ids = AvatarAssets.eyesIds;
        break;
      case _AvatarPartCategory.mouth:
        ids = AvatarAssets.mouthIds;
        break;
    }
    if (widget.allowedRarities == null || widget.allowedRarities!.isEmpty) {
      return _groupIdsByRarity(ids);
    }
    final filteredIds =
        ids
            .where((id) => widget.allowedRarities!.contains(_rarityForId(id)))
            .toList();
    return _groupIdsByRarity(filteredIds);
  }

  String get _selectedId {
    switch (_category) {
      case _AvatarPartCategory.hair:
        return _parts.hairId;
      case _AvatarPartCategory.eyebrows:
        return _parts.eyebrowsId;
      case _AvatarPartCategory.eyes:
        return _parts.eyesId;
      case _AvatarPartCategory.mouth:
        return _parts.mouthId;
    }
  }

  AvatarParts _withPart(String id) {
    switch (_category) {
      case _AvatarPartCategory.hair:
        return _parts.copyWith(hairId: id);
      case _AvatarPartCategory.eyebrows:
        return _parts.copyWith(eyebrowsId: id);
      case _AvatarPartCategory.eyes:
        return _parts.copyWith(eyesId: id);
      case _AvatarPartCategory.mouth:
        return _parts.copyWith(mouthId: id);
    }
  }

  String _categoryLabel(_AvatarPartCategory category) {
    switch (category) {
      case _AvatarPartCategory.hair:
        return '髪';
      case _AvatarPartCategory.eyebrows:
        return '眉';
      case _AvatarPartCategory.eyes:
        return '目';
      case _AvatarPartCategory.mouth:
        return '口';
    }
  }

  String _categoryAssetPath(_AvatarPartCategory category) {
    switch (category) {
      case _AvatarPartCategory.hair:
        return AvatarAssets.hairPath(_parts.hairId);
      case _AvatarPartCategory.eyebrows:
        return AvatarAssets.eyebrowsPath(_parts.eyebrowsId);
      case _AvatarPartCategory.eyes:
        return AvatarAssets.eyesPath(_parts.eyesId);
      case _AvatarPartCategory.mouth:
        return AvatarAssets.mouthPath(_parts.mouthId);
    }
  }

  String _rarityForId(String id) {
    return AvatarAssets.partRarity[id] ?? 'common';
  }

  List<String> _groupIdsByRarity(List<String> ids) {
    final common = <String>[];
    final rare = <String>[];
    final epic = <String>[];
    final others = <String>[];

    for (final id in ids) {
      switch (_rarityForId(id)) {
        case 'common':
          common.add(id);
          break;
        case 'rare':
          rare.add(id);
          break;
        case 'epic':
          epic.add(id);
          break;
        default:
          others.add(id);
      }
    }

    return [...common, ...rare, ...epic, ...others];
  }

  AvatarParts _normalizePartsForAllowedRarities(AvatarParts parts) {
    if (widget.allowedRarities == null || widget.allowedRarities!.isEmpty) {
      return parts;
    }

    String normalize({required String currentId, required List<String> ids}) {
      if (widget.allowedRarities!.contains(_rarityForId(currentId))) {
        return currentId;
      }
      for (final id in ids) {
        if (widget.allowedRarities!.contains(_rarityForId(id))) {
          return id;
        }
      }
      return currentId;
    }

    return parts.copyWith(
      hairId: normalize(currentId: parts.hairId, ids: AvatarAssets.hairIds),
      eyebrowsId: normalize(
        currentId: parts.eyebrowsId,
        ids: AvatarAssets.eyebrowsIds,
      ),
      eyesId: normalize(currentId: parts.eyesId, ids: AvatarAssets.eyesIds),
      mouthId: normalize(currentId: parts.mouthId, ids: AvatarAssets.mouthIds),
    );
  }

  String _assetPathForPartId(String id) {
    if (AvatarAssets.hairIds.contains(id)) {
      return AvatarAssets.hairPath(id);
    }
    if (AvatarAssets.eyebrowsIds.contains(id)) {
      return AvatarAssets.eyebrowsPath(id);
    }
    if (AvatarAssets.eyesIds.contains(id)) {
      return AvatarAssets.eyesPath(id);
    }
    if (AvatarAssets.mouthIds.contains(id)) {
      return AvatarAssets.mouthPath(id);
    }
    return AvatarAssets.hairPath(AvatarAssets.hairIds.first);
  }

  bool _isUnlocked({
    required String id,
    required String rarity,
    required bool isAdmin,
    required bool isSubscriber,
    required List<String> unlockedAvatarParts,
  }) {
    if (isAdmin) return true;
    if (rarity == 'common') return true;
    if (rarity == 'epic') return isSubscriber;
    return unlockedAvatarParts.contains(id);
  }

  Color _rarityBorderColor(String rarity, bool isSelected) {
    if (rarity == 'rare') return AppColors.rarityRare;
    if (rarity == 'epic') return AppColors.rarityEpic;
    return isSelected ? AppColors.primary : AppColors.surfaceVariant;
  }

  void _onLockedPartTap({required String id, required String rarity}) {
    if (_isOpeningLockedDialog) return;
    _isOpeningLockedDialog = true;
    _showLockedDialog(id: id, rarity: rarity).whenComplete(() {
      _isOpeningLockedDialog = false;
    });
  }

  Future<void> _refreshVirtueConfigInBackground() async {
    if (_isRefreshingVirtueConfig) return;
    _isRefreshingVirtueConfig = true;
    try {
      ref.invalidate(virtueShopConfigProvider);
      await ref.read(virtueShopConfigProvider.future);
    } catch (e) {
      debugPrint('[AvatarVirtueDialog] Background config refresh failed: $e');
    } finally {
      _isRefreshingVirtueConfig = false;
    }
  }

  Future<int?> _loadAvatarPartCost(String rarity) async {
    int? parseCost(VirtueShopConfig? config) {
      final cost = config?.costForAvatarPart(rarity);
      if (cost == null || cost <= 0) return null;
      return cost;
    }

    final cachedCost = parseCost(
      ref.read(virtueShopConfigProvider).valueOrNull,
    );
    if (cachedCost != null) {
      // Use cached value for fast UX and refresh in background to reduce staleness.
      unawaited(_refreshVirtueConfigInBackground());
      return cachedCost;
    }

    try {
      final config = await ref.read(virtueShopConfigProvider.future);
      final cost = parseCost(config);
      if (cost != null) return cost;
    } catch (e) {
      debugPrint('[AvatarVirtueDialog] Config read failed: $e');
    }

    try {
      final config = await ref.refresh(virtueShopConfigProvider.future);
      final cost = parseCost(config);
      if (cost != null) return cost;
    } catch (e) {
      debugPrint('[AvatarVirtueDialog] Config refresh failed: $e');
    }

    return null;
  }

  Future<int?> _loadCurrentVirtue() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser != null) {
      debugPrint(
        '[AvatarVirtueDialog] Using currentUserProvider virtue=${currentUser.virtue}',
      );
      return currentUser.virtue;
    }

    debugPrint(
      '[AvatarVirtueDialog] currentUser unavailable. Fetching callable virtue status',
    );
    try {
      final virtueStatus = await ref.refresh(virtueStatusProvider.future);
      debugPrint(
        '[AvatarVirtueDialog] Fetched callable virtue=${virtueStatus.virtue}',
      );
      return virtueStatus.virtue;
    } catch (e) {
      debugPrint('[AvatarVirtueDialog] Fetch virtue status failed: $e');
      return null;
    }
  }

  Future<void> _showLockedDialog({
    required String id,
    required String rarity,
  }) async {
    if (!mounted) return;
    if (rarity == 'rare') {
      final cost = await _loadAvatarPartCost(rarity);
      if (!mounted) return;
      if (cost == null || cost <= 0) {
        SnackBarHelper.showError(context, AppMessages.error.loadFailed('価格情報'));
        return;
      }

      final currentVirtue = await _loadCurrentVirtue();
      if (!mounted) return;
      if (currentVirtue == null) {
        SnackBarHelper.showError(context, AppMessages.error.network);
        return;
      }

      final hasEnough = currentVirtue >= cost;
      bool isProcessing = false;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.5),
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.rarityRare.withValues(alpha: 0.2),
                              AppColors.rarityRare.withValues(alpha: 0.1),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.rarityRare.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 16,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          _assetPathForPartId(id),
                          width: 78,
                          height: 78,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.face_retouching_natural,
                              size: 48,
                              color: AppColors.textSecondary,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppMessages.confirm.purchaseVirtueTitle,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppMessages.confirm.purchaseVirtueMessage(cost),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.virtue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              color: AppColors.virtue,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppMessages.confirm.virtueCostLabel(cost),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.virtue,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        hasEnough
                            ? AppMessages.confirm.virtueBalanceAfterPurchase(
                                currentVirtue,
                                cost,
                              )
                            : AppMessages.confirm.virtueBalanceShortage(
                                currentVirtue,
                                cost,
                              ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: hasEnough
                              ? AppColors.textSecondary
                              : AppColors.error,
                          fontWeight: hasEnough ? null : FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isProcessing || !hasEnough
                              ? null
                              : () async {
                                  setDialogState(() => isProcessing = true);
                                  final success = await _purchaseAvatarPart(id);
                                  if (!mounted || !dialogContext.mounted) {
                                    return;
                                  }
                                  if (success) {
                                    Navigator.of(dialogContext).pop();
                                    setState(() {
                                      _parts = _withPart(id);
                                    });
                                    return;
                                  }
                                  setDialogState(() => isProcessing = false);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.virtue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: isProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  AppMessages.label.purchase,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: isProcessing
                            ? null
                            : () => Navigator.of(dialogContext).pop(),
                        child: Text(
                          AppMessages.label.cancel,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
      return;
    }

    if (rarity == 'epic') {
      final rootContext = context;
      bool isProcessing = false;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.5),
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.rarityEpic.withValues(alpha: 0.2),
                              AppColors.rarityEpic.withValues(alpha: 0.1),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.rarityEpic.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 16,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          _assetPathForPartId(id),
                          width: 78,
                          height: 78,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.workspace_premium,
                              size: 48,
                              color: AppColors.textSecondary,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppMessages.confirm.subscriptionOnlyTitle,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppMessages.confirm.subscriptionOnlyMessage(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      _AvatarPremiumOptionCard(
                        isLoading: isProcessing,
                        onTap: isProcessing
                            ? null
                            : () {
                                setDialogState(() => isProcessing = true);
                                Navigator.of(dialogContext).pop();
                                Future.microtask(() {
                                  if (!rootContext.mounted) return;
                                  rootContext.push('/premium');
                                });
                              },
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: isProcessing
                            ? null
                            : () => Navigator.of(dialogContext).pop(),
                        child: Text(
                          AppMessages.label.cancel,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    }
  }

  Future<bool> _purchaseAvatarPart(String id) async {
    try {
      await _virtueShopService.purchaseVirtueItem(
        itemType: 'avatar_part',
        itemId: id,
      );
      ref.invalidate(currentUserProvider);
      ref.invalidate(virtueStatusProvider);
      ref.invalidate(virtueHistoryProvider);
      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          AppMessages.success.purchaseCompleted,
        );
      }
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[AvatarVirtueDialog] purchaseAvatarPart failed: '
        'itemId=$id code=${e.code} message=${e.message} details=${e.details}',
      );
      if (mounted) {
        final reason = (e.details is Map) ? e.details['reason'] : null;
        if (reason == AppMessages.reasonItemNotPurchasable) {
          SnackBarHelper.showError(context, AppMessages.error.itemNotPurchasable);
          ref.invalidate(virtueShopConfigProvider);
        } else {
          final message = e.message == AppMessages.error.notEnoughVirtue
              ? AppMessages.error.notEnoughVirtue
              : AppMessages.error.general;
          SnackBarHelper.showError(context, message);
        }
      }
      return false;
    } catch (_) {
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 価格情報を事前に読み込む（ロックタップ時のnull回避）
    ref.watch(virtueShopConfigProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('アバター編集'),
        actions: [
          TextButton(
            onPressed: () => context.pop(_parts),
            child: const Text('完了'),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildPreview(),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildPartsGrid()),
                      const SizedBox(width: 12),
                      _buildCategoryColumn(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
      child: Center(
        child: AvatarPartsWidget(
          parts: _parts,
          size: 180,
          backgroundColor: AppColors.primaryLight.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(28),
        ),
      ),
    );
  }

  Widget _buildPartsGrid() {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    final isSubscriber = user?.isSubscriber ?? false;
    final unlockedAvatarParts = user?.unlockedAvatarParts ?? const <String>[];
    final configAsync = ref.watch(virtueShopConfigProvider);
    if (configAsync.isLoading && !configAsync.hasValue) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    final shopConfig = configAsync.valueOrNull;
    final ids = _currentIds.where((id) {
      if (isAdmin) return true;
      final rarity = _rarityForId(id);
      final isOwned = _isUnlocked(
        id: id,
        rarity: rarity,
        isAdmin: isAdmin,
        isSubscriber: isSubscriber,
        unlockedAvatarParts: unlockedAvatarParts,
      );
      if (isOwned) return true;
      return !(shopConfig?.isNonPurchasable('avatar_part', id) ?? false);
    }).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemCount: ids.length,
        itemBuilder: (context, index) {
          final id = ids[index];
          final isSelected = id == _selectedId;
          final rarity = _rarityForId(id);
          final isLocked = !_isUnlocked(
            id: id,
            rarity: rarity,
            isAdmin: isAdmin,
            isSubscriber: isSubscriber,
            unlockedAvatarParts: unlockedAvatarParts,
          );
          final borderColor = _rarityBorderColor(rarity, isSelected);
          return GestureDetector(
            onTap: () {
              if (isLocked) {
                _onLockedPartTap(id: id, rarity: rarity);
                return;
              }
              setState(() => _parts = _withPart(id));
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryLight
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: borderColor,
                  width: isSelected || rarity != 'common' ? 2 : 1,
                ),
              ),
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final iconSize =
                            (constraints.biggest.shortestSide * 0.62).clamp(
                              48.0,
                              180.0,
                            );
                        return Image.asset(
                          _assetPathForPartId(id),
                          width: iconSize,
                          height: iconSize,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return SizedBox(width: iconSize, height: iconSize);
                          },
                        );
                      },
                    ),
                    if (isLocked)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock,
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryColumn() {
    return SizedBox(
      width: 80,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
        child: ListView.separated(
          itemCount: _AvatarPartCategory.values.length,
          padding: EdgeInsets.zero,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final category = _AvatarPartCategory.values[index];
            final isSelected = category == _category;
            return GestureDetector(
              onTap: () => setState(() => _category = category),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 64,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryLight
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                  border: isSelected
                      ? Border.all(color: AppColors.primary, width: 2)
                      : null,
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Image.asset(
                      _categoryAssetPath(category),
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const SizedBox(width: 36, height: 36);
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _categoryLabel(category),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AvatarPremiumOptionCard extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isLoading;

  const _AvatarPremiumOptionCard({
    required this.onTap,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.praise.withValues(alpha: 0.35)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.praise.withValues(alpha: 0.14),
                AppColors.rarityEpic.withValues(alpha: 0.08),
              ],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.praise.withValues(alpha: 0.15),
                ),
                alignment: Alignment.center,
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.workspace_premium,
                        color: AppColors.praise,
                        size: 22,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppMessages.confirm.premiumSubscribeTitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppMessages.confirm.premiumUnlockEpicSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
