// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../circle/presentation/screens/circles_screen.dart';
import 'home_screen.dart';

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
    if (location.startsWith('/circles')) return 1;
    if (location.startsWith('/stamps') || location.startsWith('/tasks')) {
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
      context.push('/create-circle');
      return;
    }

    final result = await context.push<bool>('/create-post');
    if (result == true && mounted) {
      ref.read(timelineRefreshProvider.notifier).state++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    if (currentUser?.banStatus == 'permanent') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (GoRouterState.of(context).matchedLocation != '/ban-appeal') {
          context.go('/ban-appeal');
        }
      });
    }

    final currentIndex = _getCurrentIndex(context);
    if (currentIndex != _previousIndex) {
      final wasSpecialScreen = _previousIndex == 1 || _previousIndex == 2;
      final isSpecialScreen = currentIndex == 1 || currentIndex == 2;

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

    const stampButtonGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF81C784),
        Color(0xFF66BB6A),
      ],
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: widget.child,
      extendBody: true,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'ホーム',
                  isActive: currentIndex == 0,
                  onTap: () {
                    if (currentIndex == 0) {
                      ref.read(homeScrollToTopProvider.notifier).state++;
                    } else {
                      context.go('/home');
                    }
                  },
                ),
                _NavItem(
                  icon: Icons.groups_outlined,
                  activeIcon: Icons.groups_rounded,
                  label: 'サークル',
                  isActive: currentIndex == 1,
                  onTap: () {
                    if (currentIndex == 1) {
                      ref.read(circleScrollToTopProvider.notifier).state++;
                    } else {
                      context.go('/circles');
                    }
                  },
                ),
                GestureDetector(
                  onTap: () => _handleCenterButtonTap(context, currentIndex),
                  child: AnimatedBuilder(
                    animation: _rotationAnimation,
                    builder: (context, child) {
                      final isStampScreen = currentIndex == 2;
                      final isCircleScreen = currentIndex == 1;
                      final isSpecialScreen = isStampScreen || isCircleScreen;

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

                      if (isStampScreen) {
                        buttonGradient = stampButtonGradient;
                        shadowColor = const Color(0xFF66BB6A);
                        buttonIcon = Icons.auto_awesome_rounded;
                        iconSize = 28;
                      } else if (isCircleScreen) {
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
                              color: shadowColor.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Transform.rotate(
                          angle: rotationAngle,
                          child: Transform.rotate(
                            angle: (isStampScreen || isCircleScreen)
                                ? -1.5708
                                : 0,
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
                _NavItem(
                  icon: Icons.collections_bookmark_outlined,
                  activeIcon: Icons.collections_bookmark_rounded,
                  label: AppMessages.stamp.navLabel,
                  isActive: currentIndex == 2,
                  onTap: () => context.go('/stamps'),
                ),
                _NavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person_rounded,
                  label: 'マイページ',
                  isActive: currentIndex == 3,
                  onTap: () => context.go('/profile'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
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
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? AppColors.primary : AppColors.textHint,
              size: 26,
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
