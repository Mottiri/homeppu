import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/models/name_part_model.dart';
import '../../../../shared/providers/moderation_provider.dart';
import '../../../../shared/services/name_parts_service.dart';
import '../../../../shared/services/virtue_shop_service.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/virtue_shop_provider.dart';

/// 名前編集画面
class NameEditScreen extends ConsumerStatefulWidget {
  const NameEditScreen({super.key});

  @override
  ConsumerState<NameEditScreen> createState() => _NameEditScreenState();
}

class _NameEditScreenState extends ConsumerState<NameEditScreen> {
  final _namePartsService = NamePartsService();
  final _virtueShopService = VirtueShopService();
  bool _isOpeningLockedDialog = false;
  bool _isRefreshingVirtueConfig = false;

  bool _isLoading = true;
  String? _error;

  List<NamePartModel> _prefixes = [];
  List<NamePartModel> _suffixes = [];

  String? _selectedPrefixId;
  String? _selectedSuffixId;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadNameParts();
    Future.microtask(() => ref.invalidate(virtueShopConfigProvider));
  }

  Future<void> _loadNameParts() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final result = await _namePartsService.getNameParts();

      setState(() {
        _prefixes = result.prefixes;
        _suffixes = result.suffixes;
        _selectedPrefixId = result.currentPrefixId;
        _selectedSuffixId = result.currentSuffixId;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('NameEditScreen load failed: $e');
      setState(() {
        _error = AppMessages.profile.namePartsLoadFailed;
        _isLoading = false;
      });
    }
  }

  String get _previewName {
    final prefix = _prefixes.firstWhere(
      (p) => p.id == _selectedPrefixId,
      orElse: () => NamePartModel(
        id: '',
        text: AppMessages.profile.namePartPlaceholder,
        category: '',
        rarity: 'common',
        type: 'prefix',
        order: 0,
      ),
    );
    final suffix = _suffixes.firstWhere(
      (s) => s.id == _selectedSuffixId,
      orElse: () => NamePartModel(
        id: '',
        text: AppMessages.profile.namePartPlaceholder,
        category: '',
        rarity: 'common',
        type: 'suffix',
        order: 0,
      ),
    );
    return '${prefix.text}${suffix.text}';
  }

  Future<void> _saveName() async {
    if (_selectedPrefixId == null || _selectedSuffixId == null) {
      SnackBarHelper.showError(context, AppMessages.profile.selectParts);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final result = await _namePartsService.updateUserName(
        prefixId: _selectedPrefixId!,
        suffixId: _selectedSuffixId!,
      );

      if (result.success) {
        // ユーザー情報を更新
        ref.invalidate(currentUserProvider);

        if (mounted) {
          SnackBarHelper.showSuccess(context, result.message);
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      debugPrint('NameEditScreen save failed: $e');
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.profile.nameUpdateFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 価格情報を事前に読み込む（ロックタップ時の待ち時間を短くする）
    ref.watch(virtueShopConfigProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppMessages.profile.nameEditTitle),
        actions: [
          if (!_isLoading &&
              _selectedPrefixId != null &&
              _selectedSuffixId != null)
            TextButton(
              onPressed: _isSaving ? null : _saveName,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(AppMessages.label.save),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadNameParts,
                    child: Text(AppMessages.label.retry),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // プレビュー
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Column(
                    children: [
                      Text(
                        AppMessages.profile.previewLabel,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _previewName,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // パーツ選択
                Expanded(
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        TabBar(
                          tabs: [
                            Tab(text: AppMessages.profile.prefixTab),
                            Tab(text: AppMessages.profile.suffixTab),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildPartsList(_prefixes, true),
                              _buildPartsList(_suffixes, false),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPartsList(
    List<NamePartModel> parts,
    bool isPrefix,
  ) {
    final configAsync = ref.watch(virtueShopConfigProvider);
    if (configAsync.isLoading && !configAsync.hasValue) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    final shopConfig = configAsync.valueOrNull;
    final filteredParts = parts.where((part) {
      if (part.unlocked) return true;
      return !(shopConfig?.isNonPurchasable('name_part', part.id) ?? false);
    }).toList();

    // カテゴリでグループ化
    final Map<String, List<NamePartModel>> grouped = {};
    for (final part in filteredParts) {
      grouped.putIfAbsent(part.category, () => []).add(part);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final category = grouped.keys.elementAt(index);
        final categoryParts = grouped[category]!;
        final firstPart = categoryParts.first;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                firstPart.categoryDisplayName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categoryParts.map((part) {
                final isSelected = isPrefix
                    ? _selectedPrefixId == part.id
                    : _selectedSuffixId == part.id;
                final isLocked = !part.unlocked;

                return _buildPartChip(
                  part,
                  isSelected,
                  isLocked,
                  isPrefix,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildPartChip(
    NamePartModel part,
    bool isSelected,
    bool isLocked,
    bool isPrefix,
  ) {
    return GestureDetector(
      onTap: isLocked
          ? () {
              _onLockedPartTap(part);
            }
          : () {
              setState(() {
                if (isPrefix) {
                  _selectedPrefixId = part.id;
                } else {
                  _selectedSuffixId = part.id;
                }
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : isLocked
              ? Colors.grey[200]
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : !part.isCommon
                ? Color(part.rarityColor)
                : Colors.grey[300]!,
            width: !part.isCommon ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLocked) ...[
              Icon(Icons.lock, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
            ],
            Text(
              part.text,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : isLocked
                    ? Colors.grey[500]
                    : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onLockedPartTap(NamePartModel part) {
    if (_isOpeningLockedDialog) return;
    _isOpeningLockedDialog = true;
    _showPurchaseDialog(part).whenComplete(() {
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
      debugPrint('[NameVirtueDialog] Background config refresh failed: $e');
    } finally {
      _isRefreshingVirtueConfig = false;
    }
  }

  Future<int?> _loadNamePartCost(NamePartModel part) async {
    int? parseCost(VirtueShopConfig? config) {
      final cost = config?.costForNamePart(part.rarity);
      if (cost == null || cost <= 0) return null;
      return cost;
    }

    final cachedCost = parseCost(ref.read(virtueShopConfigProvider).valueOrNull);
    if (cachedCost != null) {
      unawaited(_refreshVirtueConfigInBackground());
      return cachedCost;
    }

    try {
      final config = await ref.read(virtueShopConfigProvider.future);
      final cost = parseCost(config);
      if (cost != null) return cost;
    } catch (e) {
      debugPrint('[NameVirtueDialog] Config read failed: $e');
    }

    try {
      final config = await ref.refresh(virtueShopConfigProvider.future);
      final cost = parseCost(config);
      if (cost != null) return cost;
    } catch (e) {
      debugPrint('[NameVirtueDialog] Config refresh failed: $e');
    }

    return null;
  }

  Future<int?> _loadCurrentVirtue() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser != null) {
      return currentUser.virtue;
    }
    try {
      final virtueStatus = await ref.refresh(virtueStatusProvider.future);
      return virtueStatus.virtue;
    } catch (e) {
      debugPrint('[NameVirtueDialog] Fetch virtue status failed: $e');
      return null;
    }
  }

  Future<void> _showPurchaseDialog(NamePartModel part) async {
    if (part.rarity == 'epic') {
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
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
                              color: AppColors.rarityEpic.withValues(alpha: 0.3),
                              blurRadius: 16,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          part.text,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
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
                      _NamePremiumOptionCard(
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
      return;
    }

    final cost = await _loadNamePartCost(part);
    if (!mounted) return;
    if (cost == null || cost <= 0) {
      SnackBarHelper.showError(
        context,
        AppMessages.error.loadFailed('価格情報'),
      );
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
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
                            color: AppColors.rarityRare.withValues(alpha: 0.3),
                            blurRadius: 16,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Text(
                        part.text,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
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
                                final success = await _purchaseNamePart(part);
                                if (!mounted || !dialogContext.mounted) {
                                  return;
                                }
                                if (success) {
                                  Navigator.of(dialogContext).pop();
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
  }

  Future<bool> _purchaseNamePart(NamePartModel part) async {
    try {
      await _virtueShopService.purchaseVirtueItem(
        itemType: 'name_part',
        itemId: part.id,
      );
      ref.invalidate(currentUserProvider);
      ref.invalidate(virtueStatusProvider);
      ref.invalidate(virtueHistoryProvider);
      await _loadNameParts();
      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          AppMessages.success.purchaseCompleted,
        );
      }
      return true;
    } on FirebaseFunctionsException catch (e) {
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
}

class _NamePremiumOptionCard extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isLoading;

  const _NamePremiumOptionCard({
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
            border: Border.all(
              color: AppColors.praise.withValues(alpha: 0.35),
            ),
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
