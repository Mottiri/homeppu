import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final virtueShopConfig = ref.watch(virtueShopConfigProvider).valueOrNull;
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
                              _buildPartsList(_prefixes, true, virtueShopConfig),
                              _buildPartsList(_suffixes, false, virtueShopConfig),
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
    VirtueShopConfig? config,
  ) {
    // カテゴリでグループ化
    final Map<String, List<NamePartModel>> grouped = {};
    for (final part in parts) {
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
                  config,
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
    VirtueShopConfig? config,
  ) {
    return GestureDetector(
      onTap: isLocked
          ? () {
              _showPurchaseDialog(part, config);
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

  Future<void> _showPurchaseDialog(
    NamePartModel part,
    VirtueShopConfig? config,
  ) async {
    if (config == null) {
      SnackBarHelper.showError(
        context,
        AppMessages.error.loadFailed('価格情報'),
      );
      return;
    }

    final cost = config.costForNamePart(part.rarity);
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
                                final success = await _purchaseNamePart(part);
                                if (mounted && success) {
                                  Navigator.of(context).pop();
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
}
