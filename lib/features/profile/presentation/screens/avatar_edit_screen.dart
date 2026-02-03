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

  const AvatarEditScreen({
    super.key,
    required this.initialParts,
  });

  @override
  ConsumerState<AvatarEditScreen> createState() => _AvatarEditScreenState();
}

class _AvatarEditScreenState extends ConsumerState<AvatarEditScreen> {
  late AvatarParts _parts;
  _AvatarPartCategory _category = _AvatarPartCategory.hair;
  final _virtueShopService = VirtueShopService();

  @override
  void initState() {
    super.initState();
    _parts = widget.initialParts;
  }

  List<String> get _currentIds {
    switch (_category) {
      case _AvatarPartCategory.hair:
        return AvatarAssets.hairIds;
      case _AvatarPartCategory.eyebrows:
        return AvatarAssets.eyebrowsIds;
      case _AvatarPartCategory.eyes:
        return AvatarAssets.eyesIds;
      case _AvatarPartCategory.mouth:
        return AvatarAssets.mouthIds;
    }
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

  Future<void> _showLockedDialog({
    required String id,
    required String rarity,
  }) async {
    if (!mounted) return;
    if (rarity == 'rare') {
      final config = ref.read(virtueShopConfigProvider).valueOrNull;
      final cost = config?.costForAvatarPart(rarity);
      if (cost == null || cost <= 0) {
        SnackBarHelper.showError(
          context,
          AppMessages.error.loadFailed('価格情報'),
        );
        return;
      }

      bool isProcessing = false;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(AppMessages.confirm.purchaseVirtueTitle),
                content: Text(AppMessages.confirm.purchaseVirtueMessage(cost)),
                actions: [
                  SizedBox(
                    width: double.infinity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isProcessing
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: Text(AppMessages.label.cancel),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: isProcessing
                              ? null
                              : () async {
                                  setDialogState(() => isProcessing = true);
                                  final success = await _purchaseAvatarPart(id);
                                  if (mounted && success) {
                                    Navigator.of(context).pop();
                                    setState(() {
                                      _parts = _withPart(id);
                                    });
                                  }
                                  if (mounted) {
                                    setDialogState(() => isProcessing = false);
                                  }
                                },
                          child: isProcessing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(AppMessages.label.purchase),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
      return;
    }

    if (rarity == 'epic') {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(AppMessages.confirm.subscriptionOnlyTitle),
            content: Text(AppMessages.confirm.subscriptionOnlyMessage()),
            actions: [
              SizedBox(
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(AppMessages.label.cancel),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(AppMessages.label.subscribe),
                    ),
                  ],
                ),
              ),
            ],
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
        SnackBarHelper.showSuccess(context, AppMessages.success.purchaseCompleted);
      }
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        final message = e.message == AppMessages.error.notEnoughVirtue
            ? AppMessages.error.notEnoughVirtue
            : AppMessages.error.general;
        SnackBarHelper.showError(context, message);
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
    final ids = _currentIds;
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
                _showLockedDialog(id: id, rarity: rarity);
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
                    AvatarPartsWidget(
                      parts: _withPart(id),
                      size: 72,
                      backgroundColor: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
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
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _AvatarPartCategory.values.map((category) {
          final isSelected = category == _category;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: GestureDetector(
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
            ),
          );
        }).toList(),
      ),
    );
  }
}
