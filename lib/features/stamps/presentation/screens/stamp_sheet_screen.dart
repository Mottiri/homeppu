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
  bool _isShowingCatalogSheet = false;
  bool _routeListenerAttached = false;
  bool _showNextSheetSelectionFab = false;
  GoRouterDelegate? _routerDelegate;
  String _lastFlowDebugSignature = '';

  void _debugStampFlow(String event, [Map<String, Object?> extra = const {}]) {
    final buffer = StringBuffer('[STAMP_FLOW] $event');
    if (extra.isNotEmpty) {
      buffer.write(' ');
      buffer.write(extra.entries.map((e) => '${e.key}=${e.value}').join(', '));
    }
    debugPrint(buffer.toString());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _catalogFuture = _sheetService.fetchCatalog();
    _layoutsFuture = _loadLayouts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeListenerAttached) return;
    _routerDelegate = GoRouter.of(context).routerDelegate;
    _routeListenerAttached = true;
    _routerDelegate?.addListener(_handleRouteChanged);
  }

  @override
  void dispose() {
    if (_routeListenerAttached) {
      _routerDelegate?.removeListener(_handleRouteChanged);
    }
    WidgetsBinding.instance.removeObserver(this);
    _flushDebounce?.cancel();
    _confettiController.dispose();
    unawaited(_flushSnapshotNow());
    super.dispose();
  }

  void _handleRouteChanged() {
    if (!mounted) return;
    final location = GoRouterState.of(context).uri.toString();
    _debugStampFlow('route_changed', {
      'location': location,
      'selectDialog': _isShowingSelectDialog,
      'catalogSheet': _isShowingCatalogSheet,
    });
    if (location.startsWith('/stamps')) return;
    if (_isShowingSelectDialog || _isShowingCatalogSheet) {
      _debugStampFlow('route_left_stamps_try_close_modals');
      unawaited(Navigator.of(context, rootNavigator: true).maybePop());
      unawaited(Navigator.of(context).maybePop());
    }
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
    int rarityRank(String rarity) {
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

    final sortedSheets = [...sheets]..sort((a, b) {
      final aUnlocked = _isSheetUnlocked(a, user);
      final bUnlocked = _isSheetUnlocked(b, user);
      if (aUnlocked != bUnlocked) return aUnlocked ? -1 : 1;

      final rarityCompare = rarityRank(a.rarity).compareTo(rarityRank(b.rarity));
      if (rarityCompare != 0) return rarityCompare;

      return a.id.compareTo(b.id);
    });
    final visibleSheets = sortedSheets
        .where((sheet) => _isSheetUnlocked(sheet, user))
        .toList();

    bool isSelectingSheet = false;
    String? selectingSheetId;

    _isShowingCatalogSheet = true;
    _debugStampFlow('open_catalog_start', {'visibleSheets': visibleSheets.length});
    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useRootNavigator: false,
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
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            itemCount: visibleSheets.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1, indent: 84, endIndent: 16),
                            itemBuilder: (context, index) {
                              final sheet = visibleSheets[index];
                              final unlocked = _isSheetUnlocked(sheet, user);
                              final isThisSelecting =
                                  isSelectingSheet && selectingSheetId == sheet.id;
                              Future<void> applySheetSelection() async {
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

                              Future<void> showSheetPreviewDialog() async {
                                await showDialog<void>(
                                  context: context,
                                  useRootNavigator: false,
                                  barrierDismissible: true,
                                  builder: (_) {
                                    return Dialog(
                                      backgroundColor: Colors.transparent,
                                      insetPadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 24,
                                      ),
                                      child: AspectRatio(
                                        aspectRatio: 2 / 3,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(16),
                                          child: Image.asset(
                                            sheet.assetPath,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              }

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 6,
                                ),
                                onTap: (unlocked && !isSelectingSheet)
                                    ? showSheetPreviewDialog
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
                                        ? FilledButton(
                                            onPressed: isSelectingSheet
                                                ? null
                                                : applySheetSelection,
                                            child: Text(AppMessages.stamp.selectAction),
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
    } finally {
      _isShowingCatalogSheet = false;
      _debugStampFlow('open_catalog_end');
    }
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
    _debugStampFlow('show_selection_dialog', {'first': first});
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
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
              Navigator.of(dialogContext).pop();
              _debugStampFlow('selection_dialog_tap_design_select');
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
    _debugStampFlow('selection_dialog_closed');
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
                        _debugStampFlow('load_pending_next_sheet', {
                          'user': user.uid,
                          'pending': state.pendingNextSheetFrom,
                        });
                        if (mounted) {
                          setState(() {});
                        }
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
                    final hasPendingFromState =
                        state.pendingNextSheetFrom != null;
                    final canUndo =
                        !hasPendingFromState &&
                        _latestFilledSlotId(layout, state.localBySlot) != null;
                    final isSheetComplete =
                        state.localBySlot.length >= layout.slots.length;
                    if (isSheetComplete && state.pendingNextSheetFrom == null) {
                      state.pendingNextSheetFrom = selected.id;
                      _debugStampFlow('auto_set_pending_from_complete_sheet', {
                        'sheet': selected.id,
                      });
                      unawaited(_setPendingNextSheet(user.uid, selected.id));
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() {});
                      });
                    }
                    if (hasPendingFromState && _showStampBar) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() => _showStampBar = false);
                        }
                      });
                    }
                    final shouldShowNextSheetFab =
                        state.pendingNextSheetFrom != null || isSheetComplete;
                    if (_showNextSheetSelectionFab != shouldShowNextSheetFab) {
                      _debugStampFlow('toggle_next_sheet_fab_flag', {
                        'before': _showNextSheetSelectionFab,
                        'after': shouldShowNextSheetFab,
                        'pending': state.pendingNextSheetFrom,
                        'isComplete': isSheetComplete,
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _showNextSheetSelectionFab = shouldShowNextSheetFab;
                          });
                        }
                      });
                    }
                    final hasPendingSelection =
                        state.pendingNextSheetFrom != null ||
                        _showNextSheetSelectionFab;
                    final signature =
                        'pending=${state.pendingNextSheetFrom}|fabFlag=$_showNextSheetSelectionFab|showBar=$_showStampBar|hasPending=$hasPendingSelection';
                    if (_lastFlowDebugSignature != signature) {
                      _lastFlowDebugSignature = signature;
                      _debugStampFlow('fab_state', {
                        'pending': state.pendingNextSheetFrom,
                        'fabFlag': _showNextSheetSelectionFab,
                        'showStampBar': _showStampBar,
                        'hasPendingSelection': hasPendingSelection,
                      });
                    }

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
                                    if (state.pendingNextSheetFrom != null) {
                                      _toast(
                                        AppMessages.stamp.chooseNextSheetRequired,
                                        error: true,
                                      );
                                      return;
                                    }
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
                        if (_showStampBar && state.pendingNextSheetFrom == null)
                          _StampBar(
                            isUnlocked: (type) =>
                                _isReactionUnlocked(type, user),
                            onClose: () =>
                                setState(() => _showStampBar = false),
                            onTap: (type) async {
                              if (state.pendingNextSheetFrom != null) {
                                _toast(
                                  AppMessages.stamp.chooseNextSheetRequired,
                                  error: true,
                                );
                                return;
                              }
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
                                if (state.pendingNextSheetFrom == null) {
                                  state.pendingNextSheetFrom = selected.id;
                                  _debugStampFlow('set_pending_on_sheet_full', {
                                    'sheet': selected.id,
                                  });
                                  await _setPendingNextSheet(
                                    user.uid,
                                    selected.id,
                                  );
                                  if (mounted) {
                                    setState(() {});
                                  }
                                }
                                _toast(
                                  AppMessages.stamp.chooseNextSheetRequired,
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
                                _debugStampFlow('sheet_completed_set_pending', {
                                  'sheet': selected.id,
                                  'filled': state.localBySlot.length,
                                  'slots': layout.slots.length,
                                });
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
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: SafeArea(
                            top: false,
                            child: hasPendingSelection
                                ? SizedBox(
                                    width: 172,
                                    height: 56,
                                    child: ElevatedButton.icon(
                                      onPressed: () async {
                                        _debugStampFlow('tap_next_sheet_fab');
                                        final latestSheets =
                                            await (_catalogFuture ??=
                                                _sheetService.fetchCatalog());
                                        if (!mounted) return;
                                        await _openCatalog(
                                          user: user,
                                          sheets: latestSheets,
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.collections_bookmark_outlined,
                                      ),
                                      label: Text(
                                        AppMessages.stamp.chooseNextSheetFabLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        shape: const StadiumBorder(),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                      ),
                                    ),
                                  )
                                : _showStampBar
                                ? const SizedBox.shrink()
                                : FloatingActionButton(
                                    onPressed: () {
                                      _debugStampFlow('tap_open_stamp_bar_fab');
                                      setState(() => _showStampBar = true);
                                    },
                                    tooltip: AppMessages.stamp.selectStamp,
                                    child: const Icon(
                                      Icons.auto_awesome_outlined,
                                    ),
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
