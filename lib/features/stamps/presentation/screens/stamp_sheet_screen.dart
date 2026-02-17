import 'dart:async';
import 'dart:math' as math;
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
import '../../../../shared/providers/tutorial_phase3_provider.dart';
import '../../../../shared/providers/virtue_shop_provider.dart';
import '../../../../shared/widgets/ad_banner.dart';
import '../../../../shared/widgets/tutorial_overlay.dart';
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
  GoRouterDelegate? _routerDelegate;
  String _lastFlowDebugSignature = '';
  String _lastTutorialDebugSignature = '';
  bool _phase3Initialized = false;
  bool _phase3Navigating = false;
  final GlobalKey _tutorialOverlayStackKey = GlobalKey();
  final GlobalKey _initialSheetSelectButtonKey = GlobalKey();
  final GlobalKey _sheetLongPressTargetKey = GlobalKey();
  final GlobalKey _catalogActionKey = GlobalKey();
  final GlobalKey _collectionActionKey = GlobalKey();
  final GlobalKey _undoActionKey = GlobalKey();
  Rect? _tutorialSpotlightRect;
  TutorialPhase3Step? _lastTutorialStep;

  void _debugStampFlow(String event, [Map<String, Object?> extra = const {}]) {
    final buffer = StringBuffer('[STAMP_FLOW] $event');
    if (extra.isNotEmpty) {
      buffer.write(' ');
      buffer.write(extra.entries.map((e) => '${e.key}=${e.value}').join(', '));
    }
    debugPrint(buffer.toString());
  }

  void _debugPhase3(String event, [Map<String, Object?> extra = const {}]) {
    final buffer = StringBuffer('[TUTORIAL_PHASE3] $event');
    if (extra.isNotEmpty) {
      buffer.write(' ');
      buffer.write(extra.entries.map((e) => '${e.key}=${e.value}').join(', '));
    }
    debugPrint(buffer.toString());
  }

  bool _isRectNearlyEqual(Rect? a, Rect? b, {double tolerance = 0.5}) {
    if (a == null || b == null) return a == b;
    return (a.left - b.left).abs() <= tolerance &&
        (a.top - b.top).abs() <= tolerance &&
        (a.width - b.width).abs() <= tolerance &&
        (a.height - b.height).abs() <= tolerance;
  }

  Future<Rect?> _resolveRectInOverlayCoords(GlobalKey targetKey) async {
    final targetGlobalRect = await resolveRectWithRetry(targetKey);
    if (targetGlobalRect == null) return null;
    final overlayBox =
        _tutorialOverlayStackKey.currentContext?.findRenderObject()
            as RenderBox?;
    if (overlayBox == null || !overlayBox.hasSize) return null;
    final overlayGlobalOffset = overlayBox.localToGlobal(Offset.zero);
    return targetGlobalRect.shift(
      Offset(-overlayGlobalOffset.dx, -overlayGlobalOffset.dy),
    );
  }

  Future<void> _resolveSpotlightForStep(
    TutorialPhase3Step step, {
    bool needsInitialSheetSelection = false,
  }) async {
    GlobalKey? targetKey;
    switch (step) {
      case TutorialPhase3Step.overview:
        targetKey = needsInitialSheetSelection
            ? _initialSheetSelectButtonKey
            : null;
        break;
      case TutorialPhase3Step.longPressSheet:
        targetKey = _sheetLongPressTargetKey;
        break;
      case TutorialPhase3Step.catalog:
        targetKey = _catalogActionKey;
        break;
      case TutorialPhase3Step.collection:
        targetKey = _collectionActionKey;
        break;
      case TutorialPhase3Step.undo:
        targetKey = _undoActionKey;
        break;
      case TutorialPhase3Step.inactive:
        targetKey = null;
        break;
    }
    if (targetKey == null) {
      if (_tutorialSpotlightRect != null && mounted) {
        setState(() => _tutorialSpotlightRect = null);
      }
      return;
    }
    final rect = await _resolveRectInOverlayCoords(targetKey);
    if (!mounted) return;
    if (_isRectNearlyEqual(rect, _tutorialSpotlightRect)) return;
    setState(() => _tutorialSpotlightRect = rect);
  }

  Future<void> _openCatalogDuringTutorial() async {
    if (_phase3Navigating || !mounted) return;
    if (ref.read(tutorialPhase3Provider) != TutorialPhase3Step.catalog) return;
    _phase3Navigating = true;
    if (mounted) setState(() {});
    try {
      await context.push('/stamps/catalog');
      if (!mounted) return;
      if (ref.read(tutorialPhase3Provider) == TutorialPhase3Step.catalog) {
        await ref.read(tutorialPhase3Provider.notifier).advance();
      }
      final currentStep = ref.read(tutorialPhase3Provider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _resolveSpotlightForStep(currentStep);
      });
    } finally {
      _phase3Navigating = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _openCollectionDuringTutorial() async {
    if (_phase3Navigating || !mounted) return;
    if (ref.read(tutorialPhase3Provider) != TutorialPhase3Step.collection) {
      return;
    }
    _phase3Navigating = true;
    if (mounted) setState(() {});
    try {
      await context.push('/stamps/archives');
      if (!mounted) return;
      if (ref.read(tutorialPhase3Provider) == TutorialPhase3Step.collection) {
        await ref.read(tutorialPhase3Provider.notifier).advance();
      }
      final currentStep = ref.read(tutorialPhase3Provider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _resolveSpotlightForStep(currentStep);
      });
    } finally {
      _phase3Navigating = false;
      if (mounted) setState(() {});
    }
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

  StampSheetDefinition? _resolveSelectedSheet(
    List<StampSheetDefinition> sheets,
    _RuntimeState state,
    UserModel user,
  ) {
    final before = state.selectedSheetId;
    state.selectedSheetId ??= user.activeStampSheetId;
    if (before != state.selectedSheetId) {
      _debugPhase3('resolve_selected_sheet', {
        'user': user.uid,
        'before': before,
        'active': user.activeStampSheetId,
        'after': state.selectedSheetId,
      });
    }
    for (final sheet in sheets) {
      if (sheet.id == state.selectedSheetId) return sheet;
    }
    return null;
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

    final sortedSheets = [...sheets]
      ..sort((a, b) {
        final aUnlocked = _isSheetUnlocked(a, user);
        final bUnlocked = _isSheetUnlocked(b, user);
        if (aUnlocked != bUnlocked) return aUnlocked ? -1 : 1;

        final rarityCompare = rarityRank(
          a.rarity,
        ).compareTo(rarityRank(b.rarity));
        if (rarityCompare != 0) return rarityCompare;

        return a.id.compareTo(b.id);
      });
    final visibleSheets = sortedSheets
        .where((sheet) => _isSheetUnlocked(sheet, user))
        .toList();

    bool isSelectingSheet = false;
    String? selectingSheetId;

    _isShowingCatalogSheet = true;
    _debugStampFlow('open_catalog_start', {
      'visibleSheets': visibleSheets.length,
    });
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
                                  const Divider(
                                    height: 1,
                                    indent: 84,
                                    endIndent: 16,
                                  ),
                              itemBuilder: (context, index) {
                                final sheet = visibleSheets[index];
                                final unlocked = _isSheetUnlocked(sheet, user);
                                final isThisSelecting =
                                    isSelectingSheet &&
                                    selectingSheetId == sheet.id;
                                Future<void> applySheetSelection() async {
                                  if (isSelectingSheet) return;
                                  setModalState(() {
                                    isSelectingSheet = true;
                                    selectingSheetId = sheet.id;
                                  });
                                  final state = _runtime(user.uid);
                                  try {
                                    _debugPhase3('catalog_select_start', {
                                      'user': user.uid,
                                      'sheet': sheet.id,
                                      'pendingNext': state.pendingNextSheetFrom,
                                      'selected': state.selectedSheetId,
                                    });
                                    if (state.pendingNextSheetFrom != null) {
                                      await _chooseNextSheet(sheet, user);
                                    } else {
                                      await _selectFirstSheet(sheet, user);
                                    }
                                    _debugPhase3('catalog_select_done', {
                                      'user': user.uid,
                                      'sheet': sheet.id,
                                      'pendingNext': state.pendingNextSheetFrom,
                                      'selected': state.selectedSheetId,
                                    });
                                    if (context.mounted)
                                      Navigator.of(context).pop();
                                  } catch (_) {
                                    _toast(
                                      AppMessages.error.general,
                                      error: true,
                                    );
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
                                        insetPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 24,
                                            ),
                                        child: AspectRatio(
                                          aspectRatio: 2 / 3,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  subtitle: Text(
                                    AppMessages.stamp.sheetRarityLabel(
                                      sheet.rarity,
                                    ),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                  trailing: isThisSelecting
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : unlocked
                                      ? FilledButton(
                                          onPressed: isSelectingSheet
                                              ? null
                                              : applySheetSelection,
                                          child: Text(
                                            AppMessages.stamp.selectAction,
                                          ),
                                        )
                                      : FilledButton(
                                          onPressed: isSelectingSheet
                                              ? null
                                              : () async {
                                                  await _virtueShopService
                                                      .purchaseVirtueItem(
                                                        itemType: 'stamp_sheet',
                                                        itemId: sheet.id,
                                                      );
                                                  ref.invalidate(
                                                    currentUserProvider,
                                                  );
                                                  ref.invalidate(
                                                    virtueStatusProvider,
                                                  );
                                                  ref.invalidate(
                                                    virtueHistoryProvider,
                                                  );
                                                  ref.invalidate(
                                                    virtueShopConfigProvider,
                                                  );
                                                  if (context.mounted) {
                                                    Navigator.of(context).pop();
                                                  }
                                                },
                                          child: Text(
                                            AppMessages.label.purchase,
                                          ),
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
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
    _debugPhase3('select_first_sheet_start', {
      'user': user.uid,
      'sheet': sheet.id,
      'activeBefore': user.activeStampSheetId,
      'stateBefore': state.selectedSheetId,
    });
    state.selectedSheetId = sheet.id;
    state.localBySlot.clear();
    state.isDirty = true;
    state.mutationSeq += 1;
    state.awaitingServerEcho = false;
    state.awaitingBySlot.clear();
    await _sheetService.setActiveSheet(sheet.id);
    await _setFirstSheetRequired(user.uid, false);
    if (ref.read(tutorialPhase3Provider) == TutorialPhase3Step.overview) {
      await ref.read(tutorialPhase3Provider.notifier).advance();
    }
    _debugPhase3('select_first_sheet_done', {
      'user': user.uid,
      'sheet': sheet.id,
      'stateAfter': state.selectedSheetId,
    });
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
    // Wait for server echo of the new (empty) active sheet.
    // This avoids briefly applying stale full placements right after switching.
    state.awaitingServerEcho = true;
    state.awaitingSheetId = sheet.id;
    state.awaitingStartedAtMs = DateTime.now().millisecondsSinceEpoch;
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
    _debugPhase3('show_selection_dialog', {
      'user': user.uid,
      'first': first,
      'active': user.activeStampSheetId,
      'tutorialStep': ref.read(tutorialPhase3Provider).name,
    });
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
              await _openCatalog(user: user, sheets: sheets);
              if (!mounted) return;
              final state = _runtime(user.uid);
              final latestUser =
                  ref.read(currentUserProvider).valueOrNull ?? user;
              final firstRequired = await _isFirstSheetRequired(user.uid);
              final needsFirst =
                  first &&
                  !(state.selectedSheetId?.isNotEmpty ?? false) &&
                  (latestUser.activeStampSheetId == null || firstRequired) &&
                  state.pendingNextSheetFrom == null;
              final needsNext = !first && state.pendingNextSheetFrom != null;
              _debugPhase3('selection_dialog_post_catalog', {
                'user': user.uid,
                'first': first,
                'activeLatest': latestUser.activeStampSheetId,
                'firstRequired': firstRequired,
                'pendingNext': state.pendingNextSheetFrom,
                'stateSelected': state.selectedSheetId,
                'needsFirst': needsFirst,
                'needsNext': needsNext,
              });
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
    final tutorialStep = ref.watch(tutorialPhase3Provider);
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppMessages.stamp.title)),
        body: Center(child: Text(AppMessages.error.loginRequired)),
      );
    }

    if (!_phase3Initialized) {
      _phase3Initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(tutorialPhase3Provider.notifier).restoreOrStart(user);
      });
    }
    if (_lastTutorialStep != tutorialStep) {
      _lastTutorialStep = tutorialStep;
      if (tutorialStep != TutorialPhase3Step.longPressSheet && _showStampBar) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_showStampBar) return;
          setState(() => _showStampBar = false);
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _resolveSpotlightForStep(tutorialStep);
      });
    }

    final primaryColor = user.headerPrimaryColor != null
        ? Color(user.headerPrimaryColor!)
        : AppColors.primary;
    final secondaryColor = user.headerSecondaryColor != null
        ? Color(user.headerSecondaryColor!)
        : AppColors.secondary;
    final isSubscriber = user.isSubscriber;
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
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final appBarReservedHeight =
        topInset + kToolbarHeight + (isSubscriber ? 0 : 58);
    final tutorialBottomExtension = kBottomNavigationBarHeight + bottomInset;
    final tutorialBubbleBottomOffset =
        bottomInset + 16 + tutorialBottomExtension;

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(AppMessages.stamp.title),
        bottom: isSubscriber
            ? null
            : const PreferredSize(
                preferredSize: Size.fromHeight(58),
                child: AdBanner(padding: EdgeInsets.fromLTRB(16, 0, 16, 8)),
              ),
        actions: [
          IconButton(
            key: _catalogActionKey,
            onPressed: () {
              if (tutorialStep == TutorialPhase3Step.inactive) {
                context.push('/stamps/catalog');
                return;
              }
              if (tutorialStep == TutorialPhase3Step.catalog) {
                unawaited(_openCatalogDuringTutorial());
              }
            },
            icon: const Icon(Icons.palette_outlined),
            tooltip: AppMessages.stamp.designCatalogTitle,
          ),
          IconButton(
            key: _collectionActionKey,
            onPressed: () {
              if (tutorialStep == TutorialPhase3Step.inactive) {
                context.push('/stamps/archives');
                return;
              }
              if (tutorialStep == TutorialPhase3Step.collection) {
                unawaited(_openCollectionDuringTutorial());
              }
            },
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: AppMessages.stamp.archiveTitle,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: userGradient),
        child: Padding(
          padding: EdgeInsets.only(top: appBarReservedHeight),
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
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
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
                      final selected = _resolveSelectedSheet(
                        sheets,
                        state,
                        user,
                      );
                      final needsInitialSheetSelection =
                          selected == null &&
                          state.pendingNextSheetFrom == null;
                      final tutorialSig =
                          'u=${user.uid}|a=${user.activeStampSheetId}|s=${state.selectedSheetId}|t=${tutorialStep.name}|p=${state.pendingNextSheetFrom}|n=$_phase3Navigating';
                      if (_lastTutorialDebugSignature != tutorialSig) {
                        _lastTutorialDebugSignature = tutorialSig;
                        _debugPhase3('build_state', {
                          'user': user.uid,
                          'active': user.activeStampSheetId,
                          'selected': state.selectedSheetId,
                          'tutorialStep': tutorialStep.name,
                          'pendingNext': state.pendingNextSheetFrom,
                          'navigating': _phase3Navigating,
                        });
                      }
                      if (tutorialStep == TutorialPhase3Step.overview &&
                          needsInitialSheetSelection) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _resolveSpotlightForStep(
                            tutorialStep,
                            needsInitialSheetSelection: true,
                          );
                        });
                      }
                      final serverBySlot = selected == null
                          ? const <String, String>{}
                          : _serverBySlot(pageMap, selected.id);
                      if (!state.initialized) {
                        state.initialized = true;
                        state.localCredits = user.thanksStampCredits;
                        state.baseVersion = user.stampSheetVersion;
                        state.localBySlot
                          ..clear()
                          ..addAll(serverBySlot);
                        unawaited(() async {
                          state.pendingNextSheetFrom =
                              await _getPendingNextSheet(user.uid);
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
                          _debugPhase3('initial_selection_check', {
                            'user': user.uid,
                            'active': user.activeStampSheetId,
                            'firstRequired': firstRequired,
                            'pendingNext': state.pendingNextSheetFrom,
                            'selected': state.selectedSheetId,
                          });
                          if (!mounted) return;
                          if (state.pendingNextSheetFrom != null) {
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
                            selected != null &&
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
                        if (!awaitingCurrentSheet ||
                            echoMatched ||
                            echoExpired) {
                          state.awaitingServerEcho = false;
                          state.awaitingBySlot.clear();
                          state.localBySlot
                            ..clear()
                            ..addAll(serverBySlot);
                          state.localCredits = user.thanksStampCredits;
                          state.baseVersion = user.stampSheetVersion;
                        }
                      }

                      if (selected == null) {
                        return Stack(
                          key: _tutorialOverlayStackKey,
                          clipBehavior: Clip.none,
                          children: [
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  24,
                                ),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 420,
                                  ),
                                  child: Card(
                                    elevation: 2,
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            AppMessages
                                                .stamp
                                                .chooseFirstSheetTitle,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleLarge,
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            AppMessages
                                                .tutorial
                                                .stampInitialSheetSelection,
                                            textAlign: TextAlign.center,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium,
                                          ),
                                          const SizedBox(height: 16),
                                          FilledButton(
                                            key: _initialSheetSelectButtonKey,
                                            onPressed: () async {
                                              await _openCatalog(
                                                user: user,
                                                sheets: sheets,
                                              );
                                            },
                                            child: Text(
                                              AppMessages.stamp.designSelect,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (!_phase3Navigating &&
                                tutorialStep == TutorialPhase3Step.overview &&
                                _tutorialSpotlightRect != null)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: -appBarReservedHeight,
                                bottom: -tutorialBottomExtension,
                                child: TutorialOverlay(
                                  message: AppMessages
                                      .tutorial
                                      .stampInitialSheetSelectionGuide,
                                  spotlightRect: _tutorialSpotlightRect!.shift(
                                    Offset(0, appBarReservedHeight),
                                  ),
                                  passThroughSpotlight: true,
                                  bubbleBottomOffset:
                                      tutorialBubbleBottomOffset,
                                  onMaskTap: () {},
                                  onSpotlightTap: () async {
                                    await _openCatalog(
                                      user: user,
                                      sheets: sheets,
                                    );
                                  },
                                ),
                              ),
                          ],
                        );
                      }

                      final layout = layouts[selected.id]!;
                      final hasPendingFromState =
                          state.pendingNextSheetFrom != null;
                      final canUndo =
                          !hasPendingFromState &&
                          _latestFilledSlotId(layout, state.localBySlot) !=
                              null;
                      Future<void> handleUndo() async {
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
                        if (tutorialStep == TutorialPhase3Step.undo) {
                          await ref
                              .read(tutorialPhase3Provider.notifier)
                              .markCompleted();
                        }
                      }

                      if (hasPendingFromState && _showStampBar) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() => _showStampBar = false);
                          }
                        });
                      }
                      final hasPendingSelection =
                          state.pendingNextSheetFrom != null;
                      final signature =
                          'pending=${state.pendingNextSheetFrom}|showBar=$_showStampBar|hasPending=$hasPendingSelection';
                      if (_lastFlowDebugSignature != signature) {
                        _lastFlowDebugSignature = signature;
                        _debugStampFlow('fab_state', {
                          'pending': state.pendingNextSheetFrom,
                          'fabFlag': false,
                          'showStampBar': _showStampBar,
                          'hasPendingSelection': hasPendingSelection,
                        });
                      }

                      return Stack(
                        key: _tutorialOverlayStackKey,
                        clipBehavior: Clip.none,
                        children: [
                          Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  4,
                                ),
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
                                      key: _undoActionKey,
                                      onPressed:
                                          (tutorialStep ==
                                                      TutorialPhase3Step
                                                          .inactive ||
                                                  tutorialStep ==
                                                      TutorialPhase3Step
                                                          .undo) &&
                                              canUndo
                                          ? () => unawaited(handleUndo())
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
                                    tutorialTargetKey: _sheetLongPressTargetKey,
                                    onLongPress: () {
                                      if (state.pendingNextSheetFrom != null) {
                                        _toast(
                                          AppMessages
                                              .stamp
                                              .chooseNextSheetRequired,
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
                              blastDirectionality:
                                  BlastDirectionality.explosive,
                              numberOfParticles: 20,
                            ),
                          ),
                          if (_showStampBar &&
                              state.pendingNextSheetFrom == null)
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
                                    _debugStampFlow(
                                      'set_pending_on_sheet_full',
                                      {'sheet': selected.id},
                                    );
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
                                if (tutorialStep ==
                                    TutorialPhase3Step.longPressSheet) {
                                  await ref
                                      .read(tutorialPhase3Provider.notifier)
                                      .advance();
                                }
                                if (state.localBySlot.length >=
                                        layout.slots.length &&
                                    state.pendingNextSheetFrom == null) {
                                  _confettiController.play();
                                  state.pendingNextSheetFrom = selected.id;
                                  _debugStampFlow(
                                    'sheet_completed_set_pending',
                                    {
                                      'sheet': selected.id,
                                      'filled': state.localBySlot.length,
                                      'slots': layout.slots.length,
                                    },
                                  );
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
                                          AppMessages
                                              .stamp
                                              .chooseNextSheetFabLabel,
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
                                  : const SizedBox.shrink(),
                            ),
                          ),
                          if (!_phase3Navigating &&
                              tutorialStep == TutorialPhase3Step.overview)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: -appBarReservedHeight,
                              bottom: -tutorialBottomExtension,
                              child: TutorialOverlay(
                                message: AppMessages.tutorial.stampOverview,
                                onMaskTap: () async {
                                  await ref
                                      .read(tutorialPhase3Provider.notifier)
                                      .advance();
                                },
                                bubbleBottomOffset: tutorialBubbleBottomOffset,
                              ),
                            ),
                          if (!_phase3Navigating &&
                              tutorialStep ==
                                  TutorialPhase3Step.longPressSheet &&
                              !_showStampBar &&
                              _tutorialSpotlightRect != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: -appBarReservedHeight,
                              bottom: -tutorialBottomExtension,
                              child: TutorialOverlay(
                                message:
                                    AppMessages.tutorial.stampLongPressSheet,
                                spotlightRect: _tutorialSpotlightRect!.shift(
                                  Offset(0, appBarReservedHeight),
                                ),
                                passThroughSpotlight: true,
                                bubbleBottomOffset: tutorialBubbleBottomOffset,
                                onMaskTap: () {},
                              ),
                            ),
                          if (!_phase3Navigating &&
                              tutorialStep == TutorialPhase3Step.catalog &&
                              _tutorialSpotlightRect != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: -appBarReservedHeight,
                              bottom: -tutorialBottomExtension,
                              child: TutorialOverlay(
                                message: AppMessages.tutorial.stampCatalogGuide,
                                spotlightRect: _tutorialSpotlightRect!.shift(
                                  Offset(0, appBarReservedHeight),
                                ),
                                bubbleBottomOffset: tutorialBubbleBottomOffset,
                                onMaskTap: () {},
                                onSpotlightTap: () {
                                  unawaited(_openCatalogDuringTutorial());
                                },
                              ),
                            ),
                          if (!_phase3Navigating &&
                              tutorialStep == TutorialPhase3Step.collection &&
                              _tutorialSpotlightRect != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: -appBarReservedHeight,
                              bottom: -tutorialBottomExtension,
                              child: TutorialOverlay(
                                message:
                                    AppMessages.tutorial.stampCollectionGuide,
                                spotlightRect: _tutorialSpotlightRect!.shift(
                                  Offset(0, appBarReservedHeight),
                                ),
                                bubbleBottomOffset: tutorialBubbleBottomOffset,
                                onMaskTap: () {},
                                onSpotlightTap: () {
                                  unawaited(_openCollectionDuringTutorial());
                                },
                              ),
                            ),
                          if (!_phase3Navigating &&
                              tutorialStep == TutorialPhase3Step.undo &&
                              _tutorialSpotlightRect != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: -appBarReservedHeight,
                              bottom: -tutorialBottomExtension,
                              child: TutorialOverlay(
                                message: AppMessages.tutorial.stampUndoGuide,
                                spotlightRect: _tutorialSpotlightRect!.shift(
                                  Offset(0, appBarReservedHeight),
                                ),
                                passThroughSpotlight: true,
                                bubbleBottomOffset: tutorialBubbleBottomOffset,
                                onMaskTap: () {},
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
      ),
    );
  }
}

class _SheetCanvas extends StatelessWidget {
  final String sheetAssetPath;
  final StampSheetLayout layout;
  final Map<String, String> bySlot;
  final VoidCallback? onLongPress;
  final Key? tutorialTargetKey;

  const _SheetCanvas({
    required this.sheetAssetPath,
    required this.layout,
    required this.bySlot,
    this.onLongPress,
    this.tutorialTargetKey,
  });

  ReactionType? _reactionById(String id) {
    for (final type in ReactionType.values) {
      if (type.value == id) return type;
    }
    return null;
  }

  // Visual alignment tweak:
  // Apply step-wise nudge to right-side columns:
  // 3rd from right < 2nd from right < rightmost.
  double _adjustSlotX(double x) {
    if (x >= 0.74) {
      return (x + 0.010).clamp(0.0, 1.0);
    }
    if (x >= 0.56) {
      return (x + 0.007).clamp(0.0, 1.0);
    }
    if (x >= 0.39) {
      return (x + 0.004).clamp(0.0, 1.0);
    }
    return x;
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
                key: tutorialTargetKey,
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
                  key: ValueKey('${slot.slotId}_${bySlot[slot.slotId]}'),
                  left: left + (_adjustSlotX(slot.x) * sheetW),
                  top: top + (slot.y * sheetH),
                  width: slot.w * sheetW,
                  height: slot.h * sheetH,
                  child: IgnorePointer(
                    child: _PlacedStamp(
                      assetPath:
                          _reactionById(bySlot[slot.slotId]!)?.assetPath ?? '',
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

// ── Stamp animation mode ──
// Change this constant and hot-reload to compare patterns.
//   original    : current pop-in → settle
//   sparklePop  : pop-in + radiating sparkle particles
//   jellySquish : elastic jelly bounce
//   jellySparkle: jelly squish + sparkle particles (combined)
enum _StampAnimMode { original, sparklePop, jellySquish, jellySparkle }

const _kStampAnimMode = _StampAnimMode.jellySparkle;

class _PlacedStamp extends StatelessWidget {
  final String assetPath;

  const _PlacedStamp({required this.assetPath});

  @override
  Widget build(BuildContext context) {
    return switch (_kStampAnimMode) {
      _StampAnimMode.original => _OriginalStampAnim(assetPath: assetPath),
      _StampAnimMode.sparklePop => _SparklePopStampAnim(assetPath: assetPath),
      _StampAnimMode.jellySquish => _JellySquishStampAnim(assetPath: assetPath),
      _StampAnimMode.jellySparkle => _JellySparkleStampAnim(
        assetPath: assetPath,
      ),
    };
  }
}

// ── Pattern 0: Original (pop-in → settle) ──
class _OriginalStampAnim extends StatelessWidget {
  final String assetPath;
  const _OriginalStampAnim({required this.assetPath});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final scale = t < 0.68
            ? (0.5 + (t / 0.68) * 0.72)
            : (1.22 - ((t - 0.68) / 0.32) * 0.22);
        final translateY = (1 - t) * -8;
        final opacity = (t * 1.4).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, translateY),
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(scale: scale.clamp(0.5, 1.22), child: child),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const SizedBox(),
        ),
      ),
    );
  }
}

// ── Pattern 3: Sparkle Pop ──
// Pop-in with small star particles radiating outward.
class _SparklePopStampAnim extends StatefulWidget {
  final String assetPath;
  const _SparklePopStampAnim({required this.assetPath});

  @override
  State<_SparklePopStampAnim> createState() => _SparklePopStampAnimState();
}

class _SparklePopStampAnimState extends State<_SparklePopStampAnim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _stampScale;
  late final Animation<double> _stampOpacity;
  late final Animation<double> _particleProgress;

  // 6 particles with pre-computed directions.
  static const _particleCount = 6;
  static const _particleAngles = [
    -0.52, // ≈ -30°
    0.26, // ≈  15°
    1.05, // ≈  60°
    2.09, // ≈ 120°
    3.14, // ≈ 180°
    4.19, // ≈ 240°
  ];
  static const _particleIcons = ['✦', '✧', '♡', '✦', '✧', '♡'];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

    // Stamp: pop in (0→60%) then settle (60→100%).
    _stampScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.3,
          end: 1.25,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.25,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 45,
      ),
    ]).animate(_ctrl);

    _stampOpacity = Tween(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.35)));

    // Particles: start at 30% and run to 100%.
    _particleProgress = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.25, 1.0, curve: Curves.easeOut),
      ),
    );

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Stamp body.
            Opacity(
              opacity: _stampOpacity.value,
              child: Transform.scale(scale: _stampScale.value, child: child),
            ),
            // Sparkle particles.
            for (var i = 0; i < _particleCount; i++)
              Positioned.fill(child: _buildParticle(i)),
          ],
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Image.asset(
          widget.assetPath,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const SizedBox(),
        ),
      ),
    );
  }

  Widget _buildParticle(int index) {
    final t = _particleProgress.value;
    if (t <= 0) return const SizedBox();
    final angle = _particleAngles[index];
    final distance = 18.0 + (t * 22.0); // pixels from center
    final dx = distance * math.cos(angle);
    final dy = distance * math.sin(angle);
    final opacity = (1.0 - t).clamp(0.0, 1.0);
    final size = 10.0 + (1 - t) * 4.0;
    return Center(
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Opacity(
          opacity: opacity,
          child: Text(
            _particleIcons[index],
            style: TextStyle(
              fontSize: size,
              color: const Color(0xFFFFB347),
              shadows: const [Shadow(color: Color(0x66FF8C00), blurRadius: 4)],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pattern 5: Jelly Squish ──
// Elastic bounce with X/Y scale oscillation for a squishy feel.
class _JellySquishStampAnim extends StatefulWidget {
  final String assetPath;
  const _JellySquishStampAnim({required this.assetPath});

  @override
  State<_JellySquishStampAnim> createState() => _JellySquishStampAnimState();
}

class _JellySquishStampAnimState extends State<_JellySquishStampAnim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleX;
  late final Animation<double> _scaleY;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    // Jelly X: 0 → 1.18 → 0.92 → 1.06 → 1.0
    _scaleX = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.18,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.18,
          end: 0.92,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.92,
          end: 1.06,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.06,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
    ]).animate(_ctrl);

    // Jelly Y: opposite phase → 0 → 0.92 → 1.16 → 0.96 → 1.0
    _scaleY = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 0.88,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.88,
          end: 1.14,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.14,
          end: 0.96,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.96,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
    ]).animate(_ctrl);

    _opacity = Tween(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.25)));

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..scale(_scaleX.value, _scaleY.value),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Image.asset(
          widget.assetPath,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const SizedBox(),
        ),
      ),
    );
  }
}

// ── Pattern 3+5: Jelly Squish + Sparkle Pop combined ──
class _JellySparkleStampAnim extends StatefulWidget {
  final String assetPath;
  const _JellySparkleStampAnim({required this.assetPath});

  @override
  State<_JellySparkleStampAnim> createState() => _JellySparkleStampAnimState();
}

class _JellySparkleStampAnimState extends State<_JellySparkleStampAnim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleX;
  late final Animation<double> _scaleY;
  late final Animation<double> _opacity;
  late final Animation<double> _particleProgress;

  static const _particleCount = 12;
  static const _particleAngles = [
    0.0, 0.52, 1.05, 1.57, 2.09, 2.62, // 0°〜150° (30°刻み)
    3.14, 3.67, 4.19, 4.71, 5.24, 5.76, // 180°〜330°
  ];
  static const _particleIcons = [
    '✦',
    '♡',
    '✧',
    '✦',
    '⋆',
    '♡',
    '✧',
    '✦',
    '♡',
    '⋆',
    '✧',
    '✦',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );

    // Jelly X: 0 → 1.18 → 0.92 → 1.06 → 1.0
    _scaleX = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.18,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.18,
          end: 0.92,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.92,
          end: 1.06,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.06,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
    ]).animate(_ctrl);

    // Jelly Y: opposite phase
    _scaleY = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 0.88,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.88,
          end: 1.14,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.14,
          end: 0.96,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.96,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
    ]).animate(_ctrl);

    _opacity = Tween(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.25)));

    // Particles: start after the initial squish.
    _particleProgress = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.20, 1.0, curve: Curves.easeOut),
      ),
    );

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Jelly squish stamp body.
            Opacity(
              opacity: _opacity.value,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..scale(_scaleX.value, _scaleY.value),
                child: child,
              ),
            ),
            // Sparkle particles.
            for (var i = 0; i < _particleCount; i++)
              Positioned.fill(child: _buildParticle(i)),
          ],
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Image.asset(
          widget.assetPath,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const SizedBox(),
        ),
      ),
    );
  }

  Widget _buildParticle(int index) {
    final t = _particleProgress.value;
    if (t <= 0) return const SizedBox();
    final angle = _particleAngles[index];
    final distance = 16.0 + (t * 28.0);
    final dx = distance * math.cos(angle);
    final dy = distance * math.sin(angle);
    final opacity = (1.0 - t).clamp(0.0, 1.0);
    final size = 9.0 + (1 - t) * 5.0;
    const particleColors = [
      Color(0xFFFF6B9D), // pink
      Color(0xFFFFD93D), // gold
      Color(0xFFFF8C42), // coral
      Color(0xFF6EC6FF), // cyan
      Color(0xFFC77DFF), // purple
      Color(0xFFA8E063), // lime
      Color(0xFFFF6B9D), // pink
      Color(0xFFFFD93D), // gold
      Color(0xFFFF8C42), // coral
      Color(0xFF6EC6FF), // cyan
      Color(0xFFC77DFF), // purple
      Color(0xFFA8E063), // lime
    ];
    const particleShadows = [
      Color(0x88FF6B9D),
      Color(0x88FFD93D),
      Color(0x88FF8C42),
      Color(0x886EC6FF),
      Color(0x88C77DFF),
      Color(0x88A8E063),
      Color(0x88FF6B9D),
      Color(0x88FFD93D),
      Color(0x88FF8C42),
      Color(0x886EC6FF),
      Color(0x88C77DFF),
      Color(0x88A8E063),
    ];
    return Center(
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Opacity(
          opacity: opacity,
          child: Text(
            _particleIcons[index],
            style: TextStyle(
              fontSize: size,
              color: particleColors[index],
              shadows: [Shadow(color: particleShadows[index], blurRadius: 6)],
            ),
          ),
        ),
      ),
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
