import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/stamp_sheet_service.dart';

class StampSheetScreen extends ConsumerStatefulWidget {
  const StampSheetScreen({super.key});

  @override
  ConsumerState<StampSheetScreen> createState() => _StampSheetScreenState();
}

class _StampSheetScreenState extends ConsumerState<StampSheetScreen>
    with WidgetsBindingObserver {
  final _service = StampSheetService();
  Future<List<StampSheetDefinition>>? _catalogFuture;
  String? _selectedSheetId;
  final Map<String, Map<String, String>> _optimisticBySheet = {};
  final List<_PendingStampAction> _pendingActions = [];
  bool _isFlushing = false;
  bool _syncErrorShown = false;
  String? _currentQueueUserId;
  static const _queueTtlMs = 24 * 60 * 60 * 1000;
  static const _queueMaxItems = 200;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _catalogFuture = _service.fetchCatalog();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushPendingActions();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _flushPendingActions();
    }
  }

  bool _isSheetUnlocked(StampSheetDefinition sheet, UserModel? user) {
    if (sheet.rarity == 'common') return true;
    if (user == null) return false;
    if (sheet.rarity == 'epic' && user.isSubscriber) return true;
    return user.unlockedStampSheets.contains(sheet.unlockKey);
  }

  bool _isReactionUnlocked(ReactionType type, UserModel? user) {
    switch (type.unlockType) {
      case ReactionUnlockType.free:
        return true;
      case ReactionUnlockType.virtue:
        return user?.unlockedReactionStamps.contains(type.purchaseKey) == true;
      case ReactionUnlockType.subscription:
        return user?.isSubscriber == true;
    }
  }

  Future<void> _selectSheet(StampSheetDefinition sheet, UserModel? user) async {
    if (!_isSheetUnlocked(sheet, user)) {
      _showToast(AppMessages.stamp.sheetLocked, isError: true);
      return;
    }
    setState(() => _selectedSheetId = sheet.id);
    try {
      await _service.setActiveSheet(sheet.id);
    } catch (_) {
      // Keep optimistic selection in UI even when persisting active sheet fails.
    }
  }

  Future<void> _openStampPicker({
    required StampSheetDefinition sheet,
    required String slotId,
    required UserModel? user,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppMessages.stamp.selectStamp,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    itemCount: ReactionType.values.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                        ),
                    itemBuilder: (context, index) {
                      final type = ReactionType.values[index];
                      final isUnlocked = _isReactionUnlocked(type, user);
                      return GestureDetector(
                        onTap: () async {
                          if (!isUnlocked) {
                            _showToast(
                              AppMessages.stamp.stampLocked,
                              isError: true,
                            );
                            return;
                          }
                          Navigator.of(context).pop();
                          await _applyStamp(
                            sheetId: sheet.id,
                            slotId: slotId,
                            stampId: type.value,
                          );
                        },
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: type.rarityColor.withValues(alpha: 0.4),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Opacity(
                                opacity: isUnlocked ? 1 : 0.45,
                                child: Image.asset(
                                  type.assetPath,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            if (!isUnlocked)
                              const Positioned(
                                right: 4,
                                bottom: 4,
                                child: Icon(
                                  Icons.lock_rounded,
                                  size: 14,
                                  color: Colors.black54,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _applyStamp({
    required String sheetId,
    required String slotId,
    required String stampId,
  }) async {
    final optimisticSheet =
        _optimisticBySheet.putIfAbsent(sheetId, () => <String, String>{});
    setState(() {
      optimisticSheet[slotId] = stampId;
      _pendingActions.add(
        _PendingStampAction(
          sheetId: sheetId,
          slotId: slotId,
          stampId: stampId,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
    await _persistPendingActions();
  }

  String? _nextEmptySlotId(
    StampSheetLayout layout,
    Map<String, String> bySlot,
  ) {
    for (final slot in layout.slots) {
      final current = bySlot[slot.slotId];
      if (current == null || current.isEmpty) {
        return slot.slotId;
      }
    }
    return null;
  }

  ReactionType? _reactionTypeById(String stampId) {
    for (final type in ReactionType.values) {
      if (type.value == stampId) return type;
    }
    return null;
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final userId = user?.uid;
    if (userId != null && userId != _currentQueueUserId) {
      _currentQueueUserId = userId;
      _initializePendingQueue(userId);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppMessages.stamp.title),
      ),
      body: userId == null
          ? Center(child: Text(AppMessages.error.loginRequired))
          : FutureBuilder<List<StampSheetDefinition>>(
              future: _catalogFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }
                if (snapshot.hasError) {
                  return Center(child: Text(AppMessages.error.general));
                }

                final sheets = snapshot.data ?? const <StampSheetDefinition>[];
                if (sheets.isEmpty) {
                  return Center(child: Text(AppMessages.stamp.noSheets));
                }

                _selectedSheetId ??=
                    (user?.activeStampSheetId != null &&
                        sheets.any((s) => s.id == user!.activeStampSheetId))
                    ? user!.activeStampSheetId
                    : sheets.first.id;
                final selected = sheets.firstWhere(
                  (sheet) => sheet.id == _selectedSheetId,
                  orElse: () => sheets.first,
                );

                return FutureBuilder<StampSheetLayout>(
                  future: _service.loadLayout(selected),
                  builder: (context, layoutSnapshot) {
                    if (!layoutSnapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      );
                    }
                    final layout = layoutSnapshot.data!;

                    return StreamBuilder<List<StampSheetPlacement>>(
                      stream: _service.watchPlacements(userId, selected.id),
                      builder: (context, placementSnapshot) {
                        final placements = placementSnapshot.data ?? const [];
                        final bySlot = <String, String>{
                          for (final item in placements) item.slotId: item.stampId,
                        };
                        final optimisticForSheet =
                            _optimisticBySheet[selected.id] ?? const {};
                        final effectiveBySlot = <String, String>{
                          ...bySlot,
                          ...optimisticForSheet,
                        };
                        final displayedCredits = (user?.thanksStampCredits ?? 0) -
                            _pendingActions.length;
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: sheets.map((sheet) {
                                          final isActive =
                                              sheet.id == selected.id;
                                          final unlocked =
                                              _isSheetUnlocked(sheet, user);
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: ChoiceChip(
                                              label: Text(sheet.id),
                                              selected: isActive,
                                              onSelected: (_) => _selectSheet(
                                                sheet,
                                                user,
                                              ),
                                              avatar: unlocked
                                                  ? null
                                                  : const Icon(
                                                      Icons.lock_rounded,
                                                      size: 16,
                                                    ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppMessages.stamp.creditsLabel(
                                        displayedCredits < 0
                                            ? 0
                                            : displayedCredits,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      AppMessages.stamp.slotTapHint,
                                      style: Theme.of(context).textTheme.bodySmall
                                          ?.copyWith(color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final areaW = constraints.maxWidth;
                                    final areaH = constraints.maxHeight;
                                    final ratio = layout.aspectRatio > 0
                                        ? layout.aspectRatio
                                        : (2 / 3);
                                    var sheetW = areaW;
                                    var sheetH = sheetW / ratio;
                                    if (sheetH > areaH) {
                                      sheetH = areaH;
                                      sheetW = sheetH * ratio;
                                    }
                                    final sheetLeft = (areaW - sheetW) / 2;
                                    final sheetTop = (areaH - sheetH) / 2;
                                    return Stack(
                                      children: [
                                        Positioned(
                                          left: sheetLeft,
                                          top: sheetTop,
                                          width: sheetW,
                                          height: sheetH,
                                          child: GestureDetector(
                                            onLongPress: () {
                                              if (_isFlushing) return;
                                              if (displayedCredits <= 0) {
                                                _showToast(
                                                  AppMessages.stamp.creditNotEnough,
                                                  isError: true,
                                                );
                                                return;
                                              }
                                              final slotId = _nextEmptySlotId(
                                                layout,
                                                effectiveBySlot,
                                              );
                                              if (slotId == null) {
                                                _showToast(
                                                  AppMessages.stamp.sheetFull,
                                                  isError: true,
                                                );
                                                return;
                                              }
                                              _openStampPicker(
                                                sheet: selected,
                                                slotId: slotId,
                                                user: user,
                                              );
                                            },
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(
                                                20,
                                              ),
                                              child: Container(
                                                color: AppColors.surfaceVariant,
                                                child: Image.asset(
                                                  selected.assetPath,
                                                  fit: BoxFit.fill,
                                                  errorBuilder: (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) {
                                                    return Center(
                                                      child: Text(
                                                        AppMessages.stamp
                                                            .slotTapHint,
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        for (final slot in layout.slots)
                                          if (effectiveBySlot[slot.slotId] != null)
                                            Positioned(
                                              left: sheetLeft + (slot.x * sheetW),
                                              top: sheetTop + (slot.y * sheetH),
                                              width: slot.w * sheetW,
                                              height: slot.h * sheetH,
                                              child: IgnorePointer(
                                                child: Builder(
                                                  builder: (_) {
                                                    final stampId =
                                                        effectiveBySlot[slot.slotId]!;
                                                    final type = _reactionTypeById(
                                                      stampId,
                                                    );
                                                    if (type == null) {
                                                      return const SizedBox
                                                          .shrink();
                                                    }
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            2,
                                                          ),
                                                      child: Image.asset(
                                                        type.assetPath,
                                                        fit: BoxFit.contain,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> _initializePendingQueue(String userId) async {
    await _restorePendingActions(userId);
    if (!mounted) return;
    _rebuildOptimisticByQueue();
    _flushPendingActions();
  }

  String _queueKey(String userId) => 'stamp_pending_actions_v1_$userId';

  Future<void> _restorePendingActions(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_queueKey(userId)) ?? const [];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final restored = <_PendingStampAction>[];
    for (final raw in rawList) {
      final action = _PendingStampAction.tryParse(raw);
      if (action == null) continue;
      if (nowMs - action.createdAtMs > _queueTtlMs) continue;
      restored.add(action);
    }
    if (!mounted) return;
    setState(() {
      _pendingActions
        ..clear()
        ..addAll(restored.take(_queueMaxItems));
    });
  }

  Future<void> _persistPendingActions() async {
    final userId = _currentQueueUserId;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final limited = _pendingActions.length > _queueMaxItems
        ? _pendingActions.sublist(_pendingActions.length - _queueMaxItems)
        : _pendingActions;
    await prefs.setStringList(
      _queueKey(userId),
      limited.map((e) => e.serialize()).toList(),
    );
  }

  void _rebuildOptimisticByQueue() {
    final next = <String, Map<String, String>>{};
    for (final action in _pendingActions) {
      final map = next.putIfAbsent(action.sheetId, () => <String, String>{});
      map[action.slotId] = action.stampId;
    }
    if (!mounted) return;
    setState(() {
      _optimisticBySheet
        ..clear()
        ..addAll(next);
    });
  }

  Future<void> _flushPendingActions() async {
    if (_isFlushing || _pendingActions.isEmpty) return;
    setState(() => _isFlushing = true);
    var sentCount = 0;
    try {
      while (sentCount < _pendingActions.length) {
        final action = _pendingActions[sentCount];
        await _service.applyStampToSlot(
          sheetId: action.sheetId,
          slotId: action.slotId,
          stampId: action.stampId,
        );
        sentCount += 1;
      }
      if (sentCount > 0) {
        setState(() {
          _pendingActions.removeRange(0, sentCount);
        });
        await _persistPendingActions();
        _rebuildOptimisticByQueue();
      }
      _syncErrorShown = false;
    } catch (_) {
      if (sentCount > 0) {
        setState(() {
          _pendingActions.removeRange(0, sentCount);
        });
        await _persistPendingActions();
        _rebuildOptimisticByQueue();
      }
      if (!_syncErrorShown) {
        _showToast(AppMessages.error.general, isError: true);
        _syncErrorShown = true;
      }
    } finally {
      if (mounted) {
        setState(() => _isFlushing = false);
      }
    }
  }
}

class _PendingStampAction {
  final String sheetId;
  final String slotId;
  final String stampId;
  final int createdAtMs;

  const _PendingStampAction({
    required this.sheetId,
    required this.slotId,
    required this.stampId,
    required this.createdAtMs,
  });

  String serialize() => '$sheetId|$slotId|$stampId|$createdAtMs';

  static _PendingStampAction? tryParse(String raw) {
    final parts = raw.split('|');
    if (parts.length != 4) return null;
    final createdAt = int.tryParse(parts[3]);
    if (createdAt == null) return null;
    return _PendingStampAction(
      sheetId: parts[0],
      slotId: parts[1],
      stampId: parts[2],
      createdAtMs: createdAt,
    );
  }
}
