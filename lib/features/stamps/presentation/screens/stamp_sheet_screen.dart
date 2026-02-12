import 'dart:async';
import 'dart:ui';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/moderation_provider.dart';
import '../../../../shared/providers/virtue_shop_provider.dart';
import '../../../../shared/services/stamp_sheet_service.dart';
import '../../../../shared/services/virtue_shop_service.dart';

class StampSheetScreen extends ConsumerStatefulWidget {
  const StampSheetScreen({super.key});

  @override
  ConsumerState<StampSheetScreen> createState() => _StampSheetScreenState();
}

class _RuntimeState {
  String? selectedSheetId;
  String? pendingNextSheetFrom;
  int localCredits = 0;
  int baseVersion = 0;
  bool initialized = false;
  bool isDirty = false;
  bool isSending = false;
  int mutationSeq = 0;
  bool awaitingServerEcho = false;
  String? awaitingSheetId;
  int awaitingStartedAtMs = 0;
  final Map<String, String> localBySlot = <String, String>{};
  final Map<String, String> awaitingBySlot = <String, String>{};
}

class _StampSheetScreenState extends ConsumerState<StampSheetScreen>
    with WidgetsBindingObserver {
  static final Map<String, _RuntimeState> _runtimeByUserId = {};

  final _sheetService = StampSheetService();
  final _virtueShopService = VirtueShopService();
  final _confettiController = ConfettiController(
    duration: const Duration(seconds: 2),
  );

  Future<List<StampSheetDefinition>>? _catalogFuture;
  Future<Map<String, StampSheetLayout>>? _layoutsFuture;
  Timer? _flushDebounce;
  bool _showStampBar = false;
  bool _isShowingSelectDialog = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _catalogFuture = _sheetService.fetchCatalog();
    _layoutsFuture = _loadLayouts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushDebounce?.cancel();
    _confettiController.dispose();
    unawaited(_flushSnapshotNow());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushSnapshotNow());
    }
  }

  Future<Map<String, StampSheetLayout>> _loadLayouts() async {
    final sheets = await _catalogFuture!;
    final map = <String, StampSheetLayout>{};
    for (final sheet in sheets) {
      map[sheet.id] = await _sheetService.loadLayout(sheet);
    }
    return map;
  }

  _RuntimeState _runtime(String userId) {
    return _runtimeByUserId.putIfAbsent(userId, () => _RuntimeState());
  }

  String _firstSheetRequiredKey(String userId) =>
      'stamp_first_sheet_required_$userId';
  String _nextSheetPendingKey(String userId) =>
      'stamp_next_sheet_pending_$userId';

  Future<void> _setFirstSheetRequired(String userId, bool required) async {
    final prefs = await SharedPreferences.getInstance();
    if (required) {
      await prefs.setBool(_firstSheetRequiredKey(userId), true);
    } else {
      await prefs.remove(_firstSheetRequiredKey(userId));
    }
  }

  Future<bool> _isFirstSheetRequired(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_firstSheetRequiredKey(userId)) ?? false;
  }

  Future<void> _setPendingNextSheet(String userId, String? sheetId) async {
    final prefs = await SharedPreferences.getInstance();
    if (sheetId == null) {
      await prefs.remove(_nextSheetPendingKey(userId));
    } else {
      await prefs.setString(_nextSheetPendingKey(userId), sheetId);
    }
  }

  Future<String?> _getPendingNextSheet(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nextSheetPendingKey(userId));
  }

  bool _isSheetUnlocked(StampSheetDefinition sheet, UserModel? user) {
    if (sheet.rarity == 'common') return true;
    if (user == null) return false;
    if (sheet.rarity == 'epic' && user.isSubscriber) return true;
    return user.unlockedStampSheets.contains(sheet.unlockKey);
  }

  bool _isReactionUnlocked(ReactionType type, UserModel? user) {
    return type.isUnlocked(
      isSubscriber: user?.isSubscriber ?? false,
      unlockedItems: (user?.unlockedReactionStamps ?? const <String>[]).toSet(),
    );
  }

  StampSheetDefinition _resolveSelectedSheet(
    List<StampSheetDefinition> sheets,
    _RuntimeState state,
    UserModel user,
  ) {
    state.selectedSheetId ??= user.activeStampSheetId ?? sheets.first.id;
    for (final sheet in sheets) {
      if (sheet.id == state.selectedSheetId) return sheet;
    }
    state.selectedSheetId = sheets.first.id;
    return sheets.first;
  }

  Map<String, String> _serverBySlot(
    Map<int, List<StampSheetPlacement>> byPage,
    String sheetId,
  ) {
    final page0 = byPage[0] ?? const <StampSheetPlacement>[];
    return <String, String>{
      for (final p in page0)
        if (p.sheetId == sheetId && p.slotId.isNotEmpty && p.stampId.isNotEmpty)
          p.slotId: p.stampId,
    };
  }

  bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _scheduleFlush() {
    _flushDebounce?.cancel();
    _flushDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_flushSnapshotNow());
    });
  }

  List<StampSnapshotEntry> _entriesFrom(
    String sheetId,
    Map<String, String> map,
  ) {
    final entries = <StampSnapshotEntry>[];
    map.forEach((slotId, stampId) {
      entries.add(
        StampSnapshotEntry(
          pageIndex: 0,
          sheetId: sheetId,
          slotId: slotId,
          stampId: stampId,
        ),
      );
    });
    return entries;
  }

  Future<void> _flushSnapshotNow() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final state = _runtime(user.uid);
    final sheetId = state.selectedSheetId;
    if (!state.isDirty || state.isSending || sheetId == null) return;

    state.isSending = true;
    final seqAtStart = state.mutationSeq;
    final snapshot = Map<String, String>.from(state.localBySlot);
    try {
      final result = await _sheetService.syncSnapshot(
        baseVersion: state.baseVersion,
        entries: _entriesFrom(sheetId, snapshot),
      );
      state.baseVersion = result.version;
      if (state.mutationSeq == seqAtStart) {
        state.isDirty = false;
        state.localCredits = result.credits;
        state.awaitingServerEcho = true;
        state.awaitingSheetId = sheetId;
        state.awaitingStartedAtMs = DateTime.now().millisecondsSinceEpoch;
        state.awaitingBySlot
          ..clear()
          ..addAll(snapshot);
      }
    } catch (e) {
      if (e is FirebaseFunctionsException && e.code == 'failed-precondition') {
        // Server is authoritative on version conflicts; stop retry loop and refetch.
        state.isDirty = false;
        state.awaitingServerEcho = false;
        state.awaitingBySlot.clear();
        ref.invalidate(currentUserProvider);
        _toast(AppMessages.error.general, error: true);
      } else {
        _toast(AppMessages.error.network, error: true);
      }
    } finally {
      state.isSending = false;
      if (mounted) setState(() {});
      if (state.isDirty) _scheduleFlush();
    }
  }

  String? _nextEmptySlotId(StampSheetLayout layout, Map<String, String> map) {
    for (final slot in layout.slots) {
      final v = map[slot.slotId];
      if (v == null || v.isEmpty) return slot.slotId;
    }
    return null;
  }

  String? _latestFilledSlotId(
    StampSheetLayout layout,
    Map<String, String> map,
  ) {
    for (var i = layout.slots.length - 1; i >= 0; i--) {
      final slot = layout.slots[i];
      if ((map[slot.slotId] ?? '').isNotEmpty) return slot.slotId;
    }
    return null;
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

  Future<void> _openCatalog({
    required UserModel user,
    required List<StampSheetDefinition> sheets,
  }) async {
    bool isSelectingSheet = false;
    String? selectingSheetId;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: Text(
                            AppMessages.stamp.designCatalogTitle,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: sheets.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1, indent: 84, endIndent: 16),
                            itemBuilder: (context, index) {
                              final sheet = sheets[index];
                              final unlocked = _isSheetUnlocked(sheet, user);
                              final isThisSelecting =
                                  isSelectingSheet && selectingSheetId == sheet.id;
                              Future<void> handleUnlockedSelection() async {
                                if (isSelectingSheet) return;
                                setModalState(() {
                                  isSelectingSheet = true;
                                  selectingSheetId = sheet.id;
                                });
                                final state = _runtime(user.uid);
                                try {
                                  if (state.pendingNextSheetFrom != null) {
                                    await _chooseNextSheet(sheet, user);
                                  } else {
                                    await _selectFirstSheet(sheet, user);
                                  }
                                  if (context.mounted) Navigator.of(context).pop();
                                } catch (_) {
                                  _toast(AppMessages.error.general, error: true);
                                  if (context.mounted) {
                                    setModalState(() {
                                      isSelectingSheet = false;
                                      selectingSheetId = null;
                                    });
                                  }
                                }
                              }

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 6,
                                ),
                                onTap: (unlocked && !isSelectingSheet)
                                    ? handleUnlockedSelection
                                    : null,
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 64,
                                    height: 64,
                                    child: Image.asset(
                                      sheet.assetPath,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  sheet.id,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                subtitle: Text(
                                  AppMessages.stamp.sheetRarityLabel(sheet.rarity),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.textSecondary),
                                ),
                                trailing: isThisSelecting
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2.5),
                                      )
                                    : unlocked
                                        ? FilledButton.tonal(
                                            onPressed: isSelectingSheet
                                                ? null
                                                : handleUnlockedSelection,
                                            child: Text(AppMessages.stamp.owned),
                                          )
                                        : FilledButton(
                                            onPressed: isSelectingSheet
                                                ? null
                                                : () async {
                                                    await _virtueShopService.purchaseVirtueItem(
                                                      itemType: 'stamp_sheet',
                                                      itemId: sheet.id,
                                                    );
                                                    ref.invalidate(currentUserProvider);
                                                    ref.invalidate(virtueStatusProvider);
                                                    ref.invalidate(virtueHistoryProvider);
                                                    ref.invalidate(virtueShopConfigProvider);
                                                    if (context.mounted) {
                                                      Navigator.of(context).pop();
                                                    }
                                                  },
                                            child: Text(AppMessages.label.purchase),
                                          ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    if (isSelectingSheet)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.20),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  AppMessages.loading.general,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
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

  Future<void> _selectFirstSheet(
    StampSheetDefinition sheet,
    UserModel user,
  ) async {
    if (!_isSheetUnlocked(sheet, user)) {
      _toast(AppMessages.stamp.sheetLocked, error: true);
      return;
    }
    final state = _runtime(user.uid);
    state.selectedSheetId = sheet.id;
    state.localBySlot.clear();
    state.isDirty = true;
    state.mutationSeq += 1;
    state.awaitingServerEcho = false;
    state.awaitingBySlot.clear();
    await _sheetService.setActiveSheet(sheet.id);
    await _setFirstSheetRequired(user.uid, false);
    _scheduleFlush();
  }

  Future<void> _chooseNextSheet(
    StampSheetDefinition sheet,
    UserModel user,
  ) async {
    final state = _runtime(user.uid);
    final currentSheet = state.pendingNextSheetFrom;
    if (currentSheet == null) return;
    await _flushSnapshotNow();
    await _sheetService.archiveAndStartNextSheet(
      currentSheetId: currentSheet,
      nextSheetId: sheet.id,
    );
    state.selectedSheetId = sheet.id;
    state.pendingNextSheetFrom = null;
    state.localBySlot.clear();
    state.isDirty = false;
    state.awaitingServerEcho = false;
    state.awaitingBySlot.clear();
    await _setPendingNextSheet(user.uid, null);
  }

  Future<void> _showSelectionDialog({
    required UserModel user,
    required List<StampSheetDefinition> sheets,
    required bool first,
  }) async {
    if (_isShowingSelectDialog) return;
    _isShowingSelectDialog = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(
          first
              ? AppMessages.stamp.chooseFirstSheetTitle
              : AppMessages.stamp.chooseNextSheetTitle,
        ),
        content: Text(
          first
              ? AppMessages.stamp.firstSheetPrompt
              : AppMessages.stamp.chooseNextSheetBody,
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              if (Navigator.of(context, rootNavigator: true).canPop()) {
                Navigator.of(context, rootNavigator: true).pop();
              }
              if (!mounted) return;
              await _openCatalog(
                user: user,
                sheets: sheets,
              );
              if (!mounted) return;
              final state = _runtime(user.uid);
              final latestUser =
                  ref.read(currentUserProvider).valueOrNull ?? user;
              final firstRequired = await _isFirstSheetRequired(user.uid);
              final needsFirst =
                  first &&
                  (latestUser.activeStampSheetId == null || firstRequired) &&
                  state.pendingNextSheetFrom == null;
              final needsNext = !first && state.pendingNextSheetFrom != null;
              if (needsFirst || needsNext) {
                await _showSelectionDialog(
                  user: latestUser,
                  sheets: sheets,
                  first: first,
                );
              }
            },
            child: Text(AppMessages.stamp.designSelect),
          ),
        ],
      ),
    );
    _isShowingSelectDialog = false;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppMessages.stamp.title)),
        body: Center(child: Text(AppMessages.error.loginRequired)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppMessages.stamp.title),
        actions: [
          IconButton(
            onPressed: () => context.push('/stamps/catalog'),
            icon: const Icon(Icons.palette_outlined),
            tooltip: AppMessages.stamp.designCatalogTitle,
          ),
          IconButton(
            onPressed: () => context.push('/stamps/archives'),
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: AppMessages.stamp.archiveTitle,
          ),
          IconButton(
            onPressed: () => _toast(AppMessages.stamp.helpBody),
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _showStampBar
          ? null
          : FloatingActionButton(
              onPressed: () => setState(() => _showStampBar = true),
              tooltip: AppMessages.stamp.selectStamp,
              child: const Icon(Icons.auto_awesome_outlined),
            ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: FutureBuilder<List<StampSheetDefinition>>(
          future: _catalogFuture,
          builder: (context, catalogSnapshot) {
            if (!catalogSnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }
            final sheets = catalogSnapshot.data!;
            return FutureBuilder<Map<String, StampSheetLayout>>(
              future: _layoutsFuture,
              builder: (context, layoutSnapshot) {
                if (!layoutSnapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }
                final layouts = layoutSnapshot.data!;
                return StreamBuilder<Map<int, List<StampSheetPlacement>>>(
                  stream: _sheetService.watchAllPlacementsByPage(user.uid),
                  builder: (context, placementSnapshot) {
                    final hasPlacementData = placementSnapshot.hasData;
                    final pageMap =
                        placementSnapshot.data ??
                        const <int, List<StampSheetPlacement>>{};
                    final state = _runtime(user.uid);
                    final selected = _resolveSelectedSheet(sheets, state, user);
                    final serverBySlot = _serverBySlot(pageMap, selected.id);
                    if (!state.initialized) {
                      state.initialized = true;
                      state.localCredits = user.thanksStampCredits;
                      state.baseVersion = user.stampSheetVersion;
                      state.localBySlot
                        ..clear()
                        ..addAll(serverBySlot);
                      unawaited(() async {
                        state.pendingNextSheetFrom = await _getPendingNextSheet(
                          user.uid,
                        );
                        final firstRequired = await _isFirstSheetRequired(
                          user.uid,
                        );
                        if (!mounted) return;
                        if ((user.activeStampSheetId == null ||
                                firstRequired) &&
                            state.pendingNextSheetFrom == null) {
                          await _showSelectionDialog(
                            user: user,
                            sheets: sheets,
                            first: true,
                          );
                        } else if (state.pendingNextSheetFrom != null) {
                          await _showSelectionDialog(
                            user: user,
                            sheets: sheets,
                            first: false,
                          );
                        }
                      }());
                    } else if (!state.isDirty &&
                        !state.isSending &&
                        hasPlacementData) {
                      final awaitingCurrentSheet =
                          state.awaitingServerEcho &&
                          state.awaitingSheetId == selected.id;
                      final echoMatched =
                          awaitingCurrentSheet &&
                          _mapEquals(serverBySlot, state.awaitingBySlot);
                      final echoExpired =
                          awaitingCurrentSheet &&
                          (DateTime.now().millisecondsSinceEpoch -
                                  state.awaitingStartedAtMs) >
                              5000;
                      if (!awaitingCurrentSheet || echoMatched || echoExpired) {
                        state.awaitingServerEcho = false;
                        state.awaitingBySlot.clear();
                        state.localBySlot
                          ..clear()
                          ..addAll(serverBySlot);
                        state.localCredits = user.thanksStampCredits;
                        state.baseVersion = user.stampSheetVersion;
                      }
                    }

                    final layout = layouts[selected.id]!;
                    final canUndo =
                        _latestFilledSlotId(layout, state.localBySlot) != null;

                    return Stack(
                      children: [
                        Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    color: AppColors.accent,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      AppMessages.stamp.creditsLabel(
                                        state.localCredits < 0
                                            ? 0
                                            : state.localCredits,
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: canUndo
                                        ? () {
                                            final slotId = _latestFilledSlotId(
                                              layout,
                                              state.localBySlot,
                                            );
                                            if (slotId == null) return;
                                            setState(() {
                                              state.localBySlot.remove(slotId);
                                              state.localCredits += 1;
                                              state.isDirty = true;
                                              state.mutationSeq += 1;
                                            });
                                            _scheduleFlush();
                                          }
                                        : null,
                                    icon: const Icon(Icons.undo, size: 18),
                                    tooltip: AppMessages.stamp.undoAction,
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  110,
                                ),
                                child: _SheetCanvas(
                                  sheetAssetPath: selected.assetPath,
                                  layout: layout,
                                  bySlot: state.localBySlot,
                                  onLongPress: () {
                                    setState(() => _showStampBar = true);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConfettiWidget(
                            confettiController: _confettiController,
                            blastDirectionality: BlastDirectionality.explosive,
                            numberOfParticles: 20,
                          ),
                        ),
                        if (_showStampBar)
                          _StampBar(
                            isUnlocked: (type) =>
                                _isReactionUnlocked(type, user),
                            onClose: () =>
                                setState(() => _showStampBar = false),
                            onTap: (type) async {
                              if (!_isReactionUnlocked(type, user)) {
                                _toast(
                                  AppMessages.stamp.stampLocked,
                                  error: true,
                                );
                                return;
                              }
                              if (state.localCredits <= 0) {
                                _toast(
                                  AppMessages.stamp.creditNotEnough,
                                  error: true,
                                );
                                return;
                              }
                              final slotId = _nextEmptySlotId(
                                layout,
                                state.localBySlot,
                              );
                              if (slotId == null) {
                                _toast(
                                  AppMessages.stamp.sheetFull,
                                  error: true,
                                );
                                return;
                              }
                              setState(() {
                                state.localBySlot[slotId] = type.value;
                                state.localCredits -= 1;
                                state.isDirty = true;
                                state.mutationSeq += 1;
                              });
                              _scheduleFlush();
                              if (state.localBySlot.length >=
                                      layout.slots.length &&
                                  state.pendingNextSheetFrom == null) {
                                _confettiController.play();
                                state.pendingNextSheetFrom = selected.id;
                                await _setPendingNextSheet(
                                  user.uid,
                                  selected.id,
                                );
                                if (mounted) {
                                  await _showSelectionDialog(
                                    user: user,
                                    sheets: sheets,
                                    first: false,
                                  );
                                }
                              }
                            },
                          ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SheetCanvas extends StatelessWidget {
  final String sheetAssetPath;
  final StampSheetLayout layout;
  final Map<String, String> bySlot;
  final VoidCallback? onLongPress;

  const _SheetCanvas({
    required this.sheetAssetPath,
    required this.layout,
    required this.bySlot,
    this.onLongPress,
  });

  ReactionType? _reactionById(String id) {
    for (final type in ReactionType.values) {
      if (type.value == id) return type;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final areaW = constraints.maxWidth;
        final areaH = constraints.maxHeight;
        final ratio = layout.aspectRatio > 0 ? layout.aspectRatio : (2 / 3);
        var sheetW = areaW;
        var sheetH = sheetW / ratio;
        if (sheetH > areaH) {
          sheetH = areaH;
          sheetW = sheetH * ratio;
        }
        final left = (areaW - sheetW) / 2;
        final centeredTop = (areaH - sheetH) / 2;
        final upwardOffset = areaH * 0.05;
        final top = (centeredTop - upwardOffset).clamp(0.0, areaH - sheetH);
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: sheetW,
              height: sheetH,
              child: GestureDetector(
                onLongPress: onLongPress,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.18),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: AppColors.secondary.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(sheetAssetPath, fit: BoxFit.fill),
                  ),
                ),
              ),
            ),
            for (final slot in layout.slots)
              if (bySlot[slot.slotId] != null)
                Positioned(
                  left: left + (slot.x * sheetW),
                  top: top + (slot.y * sheetH),
                  width: slot.w * sheetW,
                  height: slot.h * sheetH,
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Image.asset(
                        _reactionById(bySlot[slot.slotId]!)?.assetPath ?? '',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox(),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _StampBar extends StatelessWidget {
  final bool Function(ReactionType type) isUnlocked;
  final Future<void> Function(ReactionType type) onTap;
  final VoidCallback onClose;

  const _StampBar({
    required this.isUnlocked,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.primaryLight.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppMessages.stamp.selectStamp,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: onClose,
                        icon: Icon(
                          Icons.close_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: ReactionType.values.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final type = ReactionType.values[index];
                        final unlocked = isUnlocked(type);
                        return GestureDetector(
                          onTap: unlocked ? () => onTap(type) : null,
                          child: Opacity(
                            opacity: unlocked ? 1 : 0.4,
                            child: Stack(
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: unlocked
                                          ? AppColors.primaryLight.withValues(
                                              alpha: 0.5,
                                            )
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Image.asset(type.assetPath),
                                ),
                                if (!unlocked)
                                  Positioned(
                                    right: 2,
                                    bottom: 2,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.lock_rounded,
                                        size: 12,
                                        color: AppColors.textHint,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
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
