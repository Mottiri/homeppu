// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/circle_trial_provider.dart';
import '../../../../shared/providers/tutorial_phase1_provider.dart';
import '../../../../shared/providers/tutorial_phase3_provider.dart';
import '../../../../shared/providers/tutorial_phase5_provider.dart';
import '../../../../shared/providers/tutorial_phase6_provider.dart';
import '../../../../shared/providers/ui_overlay_provider.dart';
import '../../../../shared/widgets/tutorial_overlay.dart';
import '../../../../shared/services/circle_service.dart';
import '../../../circle/presentation/screens/circles_screen.dart';
import 'home_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;
  late final Animation<double> _rotationAnimation;
  int _previousIndex = 0;
  bool _isBottomNavVisible = true;
  double _scrollDeltaAccumulator = 0;
  double? _lastScrollPixels;
  int _scrollAccumulatorDirection = 0; // 1: down, -1: up
  static const double _hideThreshold = 24;
  static const double _showThreshold = 72;
  bool _isEndingCircleTrial = false;
  bool _isStartingCircleTrial = false;
  final GlobalKey _tutorialRootStackKey = GlobalKey();
  final GlobalKey _bottomNavContainerKey = GlobalKey();
  final GlobalKey _homeNavKey = GlobalKey();
  final GlobalKey _circleNavKey = GlobalKey();
  final GlobalKey _postNavKey = GlobalKey();
  final GlobalKey _stampNavKey = GlobalKey();
  final GlobalKey _myPageNavKey = GlobalKey();
  Rect? _tutorialSpotlightRect;
  bool _tutorialInitialized = false;
  double _measuredBottomNavHeight = 88;

  bool _isRectNearlyEqual(Rect? a, Rect? b, {double tolerance = 0.5}) {
    if (a == null || b == null) return a == b;
    return (a.left - b.left).abs() <= tolerance &&
        (a.top - b.top).abs() <= tolerance &&
        (a.width - b.width).abs() <= tolerance &&
        (a.height - b.height).abs() <= tolerance;
  }

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  int _getCurrentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/circles') || location.startsWith('/circle/')) {
      return 1;
    }
    if (location.startsWith('/stamps')) {
      return 2;
    }
    if (location.startsWith('/profile') || location.startsWith('/user')) {
      return 3;
    }
    return 0;
  }

  Future<void> _handleCenterButtonTap(
    BuildContext context,
    int currentIndex,
  ) async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.isBanned == true) {
      final message = currentUser?.banStatus == 'permanent'
          ? AppMessages.error.accountSuspended
          : AppMessages.error.banned;
      SnackBarHelper.showError(context, message);
      return;
    }

    if (currentIndex == 1) {
      if (!(currentUser?.isSubscriber ?? false)) {
        await _showCircleSubscriptionDialog(context);
        return;
      }
      context.push('/create-circle');
      return;
    }

    final result = await context.push<bool>('/create-post');
    if (result == true && mounted) {
      ref.read(timelineRefreshProvider.notifier).state++;
    }
  }

  Future<void> _showCircleSubscriptionDialog(BuildContext context) async {
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
                    Text(
                      AppMessages.profile.circleSubscriptionTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppMessages.profile.circleSubscriptionMessage,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isProcessing
                            ? null
                            : () {
                                setDialogState(() => isProcessing = true);
                                Navigator.of(dialogContext).pop();
                                Future.microtask(() {
                                  if (!rootContext.mounted) return;
                                  rootContext.push('/premium');
                                });
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
                                AppMessages.profile.circleUnlockAction,
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

  Future<void> _startCircleTrialAndOpen() async {
    if (_isStartingCircleTrial) return;
    setState(() => _isStartingCircleTrial = true);
    try {
      final allowed = await ref
          .read(circleServiceProvider)
          .startCircleBrowseTrial();
      if (!mounted) return;
      if (!allowed) {
        await _showCircleSubscriptionDialog(context);
        return;
      }
      ref.read(circleTrialSessionProvider.notifier).state = true;
      context.go('/circles');
    } catch (_) {
      if (!mounted) return;
      await _showCircleSubscriptionDialog(context);
    } finally {
      if (mounted) {
        setState(() => _isStartingCircleTrial = false);
      }
    }
  }

  void _clearCircleTrialIfNeeded({
    required bool isSubscriber,
    required int currentIndex,
  }) {
    if (isSubscriber || currentIndex == 1 || _isEndingCircleTrial) return;
    final isTrialSession = ref.read(circleTrialSessionProvider);
    if (!isTrialSession) return;

    _isEndingCircleTrial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _isEndingCircleTrial = false;
        return;
      }
      ref.read(circleTrialSessionProvider.notifier).state = false;
      try {
        await ref.read(circleServiceProvider).endCircleBrowseTrial();
      } catch (_) {
        // best effort
      } finally {
        _isEndingCircleTrial = false;
      }
    });
  }

  /// チュートリアル Step 0: マイページ NavItem の位置を取得
  void _resolveMyPageNavRect() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final rect = await resolveRectWithRetry(
        _myPageNavKey,
        ancestorKey: _tutorialRootStackKey,
      );
      if (mounted && !_isRectNearlyEqual(rect, _tutorialSpotlightRect)) {
        setState(() => _tutorialSpotlightRect = rect);
      }
    });
  }

  void _resolveBottomNavHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box =
          _bottomNavContainerKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final h = box.size.height;
      if ((h - _measuredBottomNavHeight).abs() > 0.5) {
        setState(() => _measuredBottomNavHeight = h);
      }
    });
  }

  bool _isBottomNavGuideStep(TutorialPhase1Step step) {
    return step == TutorialPhase1Step.bottomNavHome ||
        step == TutorialPhase1Step.bottomNavCircle ||
        step == TutorialPhase1Step.bottomNavPost ||
        step == TutorialPhase1Step.bottomNavStamps ||
        step == TutorialPhase1Step.bottomNavMyPage;
  }

  GlobalKey _targetNavKeyForStep(TutorialPhase1Step step) {
    switch (step) {
      case TutorialPhase1Step.bottomNavHome:
        return _homeNavKey;
      case TutorialPhase1Step.bottomNavCircle:
        return _circleNavKey;
      case TutorialPhase1Step.bottomNavPost:
        return _postNavKey;
      case TutorialPhase1Step.bottomNavStamps:
        return _stampNavKey;
      case TutorialPhase1Step.bottomNavMyPage:
        return _myPageNavKey;
      default:
        return _homeNavKey;
    }
  }

  String _bottomNavGuideMessage(TutorialPhase1Step step) {
    switch (step) {
      case TutorialPhase1Step.bottomNavHome:
        return AppMessages.tutorial.bottomNavHomeGuide;
      case TutorialPhase1Step.bottomNavCircle:
        return AppMessages.tutorial.bottomNavCircleGuide;
      case TutorialPhase1Step.bottomNavPost:
        return AppMessages.tutorial.bottomNavPostGuide;
      case TutorialPhase1Step.bottomNavStamps:
        return AppMessages.tutorial.bottomNavStampGuide;
      case TutorialPhase1Step.bottomNavMyPage:
        return AppMessages.tutorial.bottomNavMyPageGuide;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final isSubscriber = currentUser?.isSubscriber ?? false;
    final isCircleTrialSession = ref.watch(circleTrialSessionProvider);
    final tutorialStep = ref.watch(tutorialPhase1Provider);
    final tutorialPhase3Step = ref.watch(tutorialPhase3Provider);
    final tutorialPhase5Step = ref.watch(tutorialPhase5Provider);
    final tutorialPhase6Step = ref.watch(tutorialPhase6Provider);
    final forceHideBottomNav = ref.watch(mainShellBottomNavHiddenProvider);
    final location = GoRouterState.of(context).matchedLocation;

    // チュートリアル初期化（main_shell で一度だけ）
    if (currentUser != null && !_tutorialInitialized) {
      _tutorialInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(tutorialPhase1Provider.notifier).restoreOrStart(currentUser);
      });
    }

    // Step 0
    if (tutorialStep == TutorialPhase1Step.homeWelcome) {
      if (_tutorialSpotlightRect == null) {
        _resolveMyPageNavRect();
      }
      _resolveBottomNavHeight();
    }
    if (_isBottomNavGuideStep(tutorialStep)) {
      _resolveBottomNavHeight();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final rect = await resolveRectWithRetry(
          _targetNavKeyForStep(tutorialStep),
          ancestorKey: _tutorialRootStackKey,
        );
        if (!mounted) return;
        if (!_isRectNearlyEqual(rect, _tutorialSpotlightRect)) {
          setState(() => _tutorialSpotlightRect = rect);
        }
      });
    }
    // チュートリアル中は、必要な画面へ強制遷移して進行を維持する
    final shouldForceProfile =
        tutorialStep == TutorialPhase1Step.profileSettings &&
        !location.startsWith('/profile');
    final shouldForceSettings =
        (tutorialStep == TutorialPhase1Step.settingsScroll ||
            tutorialStep == TutorialPhase1Step.explainAI ||
            tutorialStep == TutorialPhase1Step.explainMix ||
            tutorialStep == TutorialPhase1Step.explainHuman ||
            tutorialStep == TutorialPhase1Step.finished) &&
        location != '/settings';
    final shouldForceHome =
        (tutorialStep == TutorialPhase1Step.homeOverview ||
            tutorialStep == TutorialPhase1Step.homeLongPress ||
            _isBottomNavGuideStep(tutorialStep)) &&
        !location.startsWith('/home');
    if (shouldForceProfile || shouldForceSettings || shouldForceHome) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final latestStep = ref.read(tutorialPhase1Provider);
        if (latestStep == TutorialPhase1Step.profileSettings &&
            !GoRouterState.of(context).matchedLocation.startsWith('/profile')) {
          context.go('/profile');
          return;
        }
        if ((latestStep == TutorialPhase1Step.settingsScroll ||
                latestStep == TutorialPhase1Step.explainAI ||
                latestStep == TutorialPhase1Step.explainMix ||
                latestStep == TutorialPhase1Step.explainHuman ||
                latestStep == TutorialPhase1Step.finished) &&
            GoRouterState.of(context).matchedLocation != '/settings') {
          context.go('/settings');
          return;
        }
        if ((latestStep == TutorialPhase1Step.homeOverview ||
                latestStep == TutorialPhase1Step.homeLongPress ||
                _isBottomNavGuideStep(latestStep)) &&
            !GoRouterState.of(context).matchedLocation.startsWith('/home')) {
          context.go('/home');
        }
      });
    }
    if (tutorialPhase5Step == TutorialPhase5Step.circleFabGuide &&
        location.startsWith('/circles')) {
      _resolveBottomNavHeight();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final rect = await resolveRectWithRetry(
          _postNavKey,
          ancestorKey: _tutorialRootStackKey,
        );
        if (!mounted) return;
        if (!_isRectNearlyEqual(rect, _tutorialSpotlightRect)) {
          setState(() => _tutorialSpotlightRect = rect);
        }
      });
    }

    if (currentUser?.banStatus == 'permanent') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (GoRouterState.of(context).matchedLocation != '/ban-appeal') {
          context.go('/ban-appeal');
        }
      });
    }

    final currentIndex = _getCurrentIndex(context);
    if (!isSubscriber && currentIndex == 1 && !isCircleTrialSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final location = GoRouterState.of(context).matchedLocation;
        if (location.startsWith('/circles') ||
            location.startsWith('/circle/')) {
          context.go('/home');
        }
      });
    }
    _clearCircleTrialIfNeeded(
      isSubscriber: isSubscriber,
      currentIndex: currentIndex,
    );
    final isScrollReactiveScreen =
        currentIndex == 0 || currentIndex == 1 || currentIndex == 3;
    if (!isScrollReactiveScreen && !_isBottomNavVisible) {
      _isBottomNavVisible = true;
    }
    if (currentIndex != _previousIndex) {
      final wasSpecialScreen = _previousIndex == 1;
      final isSpecialScreen = currentIndex == 1;

      if (isSpecialScreen && !wasSpecialScreen) {
        _rotationController.forward();
      } else if (!isSpecialScreen && wasSpecialScreen) {
        _rotationController.reverse();
      } else if (isSpecialScreen && wasSpecialScreen) {
        _rotationController.reverse().then((_) {
          if (mounted) _rotationController.forward();
        });
      }
      _previousIndex = currentIndex;
    }

    final isTutorialActive = tutorialStep != TutorialPhase1Step.inactive;
    final isStampTutorialActive =
        location.startsWith('/stamps') &&
        tutorialPhase3Step != TutorialPhase3Step.inactive;
    final isCircleTutorialActive =
        location.startsWith('/circles') &&
        tutorialPhase5Step != TutorialPhase5Step.inactive;
    final isProfileTutorialActive =
        location.startsWith('/profile') &&
        tutorialPhase6Step != TutorialPhase6Step.inactive;

    final page = Scaffold(
      resizeToAvoidBottomInset: false,
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (!isScrollReactiveScreen) return false;
          if (notification is ScrollStartNotification) {
            _lastScrollPixels = notification.metrics.pixels;
            _scrollDeltaAccumulator = 0;
            _scrollAccumulatorDirection = 0;
            return false;
          }
          if (notification is ScrollUpdateNotification) {
            final delta =
                notification.scrollDelta ??
                (notification.metrics.pixels -
                    (_lastScrollPixels ?? notification.metrics.pixels));
            _lastScrollPixels = notification.metrics.pixels;
            if (delta > 0) {
              if (_scrollAccumulatorDirection != 1) {
                _scrollAccumulatorDirection = 1;
                _scrollDeltaAccumulator = 0;
              }
              _scrollDeltaAccumulator += delta.abs();
              if (_isBottomNavVisible &&
                  _scrollDeltaAccumulator >= _hideThreshold) {
                _scrollDeltaAccumulator = 0;
                setState(() => _isBottomNavVisible = false);
              }
            } else if (delta < 0) {
              if (_scrollAccumulatorDirection != -1) {
                _scrollAccumulatorDirection = -1;
                _scrollDeltaAccumulator = 0;
              }
              _scrollDeltaAccumulator += delta.abs();
              if (!_isBottomNavVisible &&
                  _scrollDeltaAccumulator >= _showThreshold) {
                _scrollDeltaAccumulator = 0;
                setState(() => _isBottomNavVisible = true);
              }
            }
            return false;
          }
          if (notification is ScrollEndNotification) {
            _scrollDeltaAccumulator = 0;
            _lastScrollPixels = null;
            _scrollAccumulatorDirection = 0;
          }
          return false;
        },
        child: widget.child,
      ),
      extendBody: true,
      bottomNavigationBar: ClipRect(
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          heightFactor: (_isBottomNavVisible && !forceHideBottomNav) ? 1 : 0,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: (_isBottomNavVisible && !forceHideBottomNav)
                ? Offset.zero
                : const Offset(0, 1.0),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: (_isBottomNavVisible && !forceHideBottomNav) ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_isBottomNavVisible || forceHideBottomNav,
                child: Container(
                  key: _bottomNavContainerKey,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          IgnorePointer(
                            ignoring:
                                _isStartingCircleTrial ||
                                isTutorialActive ||
                                isStampTutorialActive ||
                                isCircleTutorialActive ||
                                isProfileTutorialActive,
                            child: _NavItem(
                              key: _homeNavKey,
                              icon: Icons.home_outlined,
                              activeIcon: Icons.home_rounded,
                              label: AppMessages.home.navLabel,
                              isActive: currentIndex == 0,
                              onTap: () {
                                if (currentIndex == 0) {
                                  ref
                                      .read(homeScrollToTopProvider.notifier)
                                      .state++;
                                } else {
                                  context.go('/home');
                                }
                              },
                            ),
                          ),
                          IgnorePointer(
                            ignoring:
                                isTutorialActive ||
                                isStampTutorialActive ||
                                isCircleTutorialActive ||
                                isProfileTutorialActive,
                            child: _NavItem(
                              key: _circleNavKey,
                              icon: Icons.groups_outlined,
                              activeIcon: Icons.groups_rounded,
                              label: AppMessages.circle.navLabel,
                              isActive:
                                  currentIndex == 1 &&
                                  (isSubscriber || isCircleTrialSession),
                              isLoading: _isStartingCircleTrial,
                              showLockBadge:
                                  !isSubscriber && !isCircleTrialSession,
                              onTap: () async {
                                if (_isStartingCircleTrial) return;
                                if (!isSubscriber) {
                                  if (isCircleTrialSession) {
                                    if (currentIndex == 1) {
                                      ref
                                          .read(
                                            circleScrollToTopProvider.notifier,
                                          )
                                          .state++;
                                    } else {
                                      context.go('/circles');
                                    }
                                    return;
                                  }
                                  await _startCircleTrialAndOpen();
                                  return;
                                }
                                if (currentIndex == 1) {
                                  ref
                                      .read(circleScrollToTopProvider.notifier)
                                      .state++;
                                } else {
                                  context.go('/circles');
                                }
                              },
                            ),
                          ),
                          IgnorePointer(
                            ignoring:
                                isTutorialActive ||
                                isStampTutorialActive ||
                                isCircleTutorialActive ||
                                isProfileTutorialActive,
                            child: GestureDetector(
                              key: _postNavKey,
                              onTap: () =>
                                  _handleCenterButtonTap(context, currentIndex),
                              child: AnimatedBuilder(
                                animation: _rotationAnimation,
                                builder: (context, child) {
                                  final isCircleScreen = currentIndex == 1;
                                  final isSpecialScreen = isCircleScreen;

                                  const circleButtonGradient = LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF4DD0E1),
                                      Color(0xFF00ACC1),
                                    ],
                                  );

                                  LinearGradient buttonGradient;
                                  Color shadowColor;
                                  IconData buttonIcon;
                                  double iconSize;

                                  if (isCircleScreen) {
                                    buttonGradient = circleButtonGradient;
                                    shadowColor = const Color(0xFF00ACC1);
                                    buttonIcon = Icons.group_add_rounded;
                                    iconSize = 26;
                                  } else {
                                    buttonGradient = AppColors.primaryGradient;
                                    shadowColor = AppColors.primary;
                                    buttonIcon = Icons.add_rounded;
                                    iconSize = 32;
                                  }

                                  final rotationAngle = isSpecialScreen
                                      ? _rotationAnimation.value * 3.14159
                                      : 0.0;

                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      gradient: buttonGradient,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: shadowColor.withValues(
                                            alpha: 0.4,
                                          ),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Transform.rotate(
                                      angle: rotationAngle,
                                      child: Transform.rotate(
                                        angle: isCircleScreen ? -1.5708 : 0,
                                        child: Icon(
                                          buttonIcon,
                                          color: Colors.white,
                                          size: iconSize,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          IgnorePointer(
                            ignoring:
                                isTutorialActive ||
                                isStampTutorialActive ||
                                isCircleTutorialActive ||
                                isProfileTutorialActive,
                            child: _NavItem(
                              key: _stampNavKey,
                              icon: Icons.collections_bookmark_outlined,
                              activeIcon: Icons.collections_bookmark_rounded,
                              label: AppMessages.stamp.navLabel,
                              isActive: currentIndex == 2,
                              onTap: () => context.go('/stamps'),
                            ),
                          ),
                          IgnorePointer(
                            ignoring:
                                isStampTutorialActive ||
                                isCircleTutorialActive ||
                                isProfileTutorialActive,
                            child: _NavItem(
                              key: _myPageNavKey,
                              icon: Icons.person_outline,
                              activeIcon: Icons.person_rounded,
                              label: AppMessages.profile.navLabel,
                              isActive: currentIndex == 3,
                              onTap: () {
                                // チュートリアル Step 0: マイページへ遷移して次へ
                                if (tutorialStep ==
                                    TutorialPhase1Step.homeWelcome) {
                                  context.go('/profile');
                                  ref
                                      .read(tutorialPhase1Provider.notifier)
                                      .advance();
                                  return;
                                }
                                if (currentIndex == 3) {
                                  ref
                                      .read(profileScrollToTopProvider.notifier)
                                      .state++;
                                } else {
                                  context.go('/profile');
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Stack(
      key: _tutorialRootStackKey,
      children: [
        page,
        if (_isStartingCircleTrial)
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          AppMessages.circle.trialChecking,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (tutorialStep == TutorialPhase1Step.homeWelcome)
          Positioned.fill(
            child: TutorialOverlay(
              message: AppMessages.tutorial.welcomeHome,
              spotlightRect: _tutorialSpotlightRect,
              onSpotlightTap: () {
                if (!mounted) return;
                context.go('/profile');
                ref.read(tutorialPhase1Provider.notifier).advance();
              },
              circularSpotlight: false,
              // ボトムナビ直上に吹き出しを配置（端末差分を吸収）
              bubbleBottomOffset:
                  MediaQuery.of(context).padding.bottom +
                  _measuredBottomNavHeight +
                  12,
            ),
          ),
        if (_isBottomNavGuideStep(tutorialStep))
          Positioned.fill(
            child: TutorialOverlay(
              message: _bottomNavGuideMessage(tutorialStep),
              spotlightRect: _tutorialSpotlightRect,
              onMaskTap: () async {
                final notifier = ref.read(tutorialPhase1Provider.notifier);
                if (tutorialStep == TutorialPhase1Step.bottomNavMyPage) {
                  await notifier.markCompleted();
                } else {
                  await notifier.advance();
                }
              },
              characterAssetPath: 'assets/onbord/onbord_01.png',
              bubbleBottomOffset:
                  MediaQuery.of(context).padding.bottom +
                  _measuredBottomNavHeight +
                  16,
            ),
          ),
        if (location.startsWith('/circles') &&
            tutorialPhase5Step == TutorialPhase5Step.circleFabGuide)
          Positioned.fill(
            child: TutorialOverlay(
              message: AppMessages.tutorial.circleFabGuide,
              spotlightRect: _tutorialSpotlightRect,
              onSpotlightTap: () => ref
                  .read(tutorialPhase5Provider.notifier)
                  .markCompleted(),
              onMaskTap: () {},
              characterAssetPath: 'assets/onbord/onbord_01.png',
              bubbleBottomOffset:
                  MediaQuery.of(context).padding.bottom +
                  _measuredBottomNavHeight +
                  16,
            ),
          ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final bool isLoading;
  final bool showLockBadge;
  final VoidCallback? onTap;

  const _NavItem({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    this.isLoading = false,
    this.showLockBadge = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isActive ? activeIcon : icon,
                  color: isActive ? AppColors.primary : AppColors.textHint,
                  size: isLoading ? 0 : 26,
                ),
                if (isLoading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isActive ? AppColors.primary : AppColors.textHint,
                      ),
                    ),
                  ),
                if (showLockBadge)
                  Positioned(
                    right: -6,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.lock_outline,
                        size: 12,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? AppColors.primary : AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

