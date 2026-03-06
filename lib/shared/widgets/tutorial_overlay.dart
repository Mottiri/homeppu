import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class TutorialOverlay extends StatelessWidget {
  static const double _spotlightPadding = 6;

  const TutorialOverlay({
    super.key,
    required this.message,
    this.spotlightRect,
    this.actionLabel,
    this.onAction,
    this.isActionEnabled = true,
    this.onSpotlightTap,
    this.onMaskTap,
    this.characterAssetPath = 'assets/onbord/onbord_01.png',
    this.bubbleBottomOffset,
    this.circularSpotlight = false,
    this.passThroughSpotlight = false,
    this.pulseMinScale = 0.94,
    this.pulseMaxScale = 1.06,
    this.characterKey,
    this.bubbleKey,
  });

  final String message;
  final Rect? spotlightRect;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isActionEnabled;
  final VoidCallback? onSpotlightTap;
  final VoidCallback? onMaskTap;
  final String characterAssetPath;
  final double? bubbleBottomOffset;
  final bool circularSpotlight;
  final bool passThroughSpotlight;
  final double pulseMinScale;
  final double pulseMaxScale;
  final Key? characterKey;
  final Key? bubbleKey;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ..._buildMasks(),
        if (spotlightRect != null && onSpotlightTap != null)
          Positioned.fromRect(
            rect: spotlightRect!,
            child: GestureDetector(
              onTap: onSpotlightTap,
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom:
              bubbleBottomOffset ??
              (MediaQuery.of(context).padding.bottom + 16),
          child: _CoachBubble(
            message: message,
            actionLabel: actionLabel,
            onAction: onAction,
            isActionEnabled: isActionEnabled,
            characterAssetPath: characterAssetPath,
            characterKey: characterKey,
            bubbleKey: bubbleKey,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMasks() {
    const maskColor = Color(0x66000000);

    if (spotlightRect == null) {
      return [
        Positioned.fill(
          child: GestureDetector(
            onTap: onMaskTap ?? () {},
            child: const ColoredBox(color: maskColor),
          ),
        ),
      ];
    }

    final baseHoleRect = spotlightRect!.inflate(_spotlightPadding);

    if (passThroughSpotlight) {
      return [
        Positioned.fill(
          child: IgnorePointer(
            child: _AnimatedMaskWithHole(
              baseHoleRect: baseHoleRect,
              circular: circularSpotlight,
              maskColor: maskColor,
              minScale: pulseMinScale,
              maxScale: pulseMaxScale,
            ),
          ),
        ),
        Positioned.fill(
          child: _PassThroughMaskLayers(
            baseHoleRect: baseHoleRect,
            circular: circularSpotlight,
            // Keep tap-blocking layers invisible so only the rounded
            // spotlight hole mask is rendered (avoids a second square mask look).
            maskColor: Colors.transparent,
            minScale: pulseMinScale,
            maxScale: pulseMaxScale,
            onTap: onMaskTap,
          ),
        ),
      ];
    }

    return [
      Positioned.fill(
        child: _AnimatedMaskWithHole(
          baseHoleRect: baseHoleRect,
          circular: circularSpotlight,
          maskColor: maskColor,
          minScale: pulseMinScale,
          maxScale: pulseMaxScale,
          onTap: onMaskTap,
        ),
      ),
    ];
  }

}

class _CoachBubble extends StatelessWidget {
  const _CoachBubble({
    required this.message,
    this.actionLabel,
    this.onAction,
    this.isActionEnabled = true,
    required this.characterAssetPath,
    this.characterKey,
    this.bubbleKey,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isActionEnabled;
  final String characterAssetPath;
  final Key? characterKey;
  final Key? bubbleKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        KeyedSubtree(
          key: characterKey,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              characterAssetPath,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            key: bubbleKey,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StyledTutorialMessage(message: message),
                if (actionLabel != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isActionEnabled ? onAction : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(actionLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StyledTutorialMessage extends StatelessWidget {
  const _StyledTutorialMessage({required this.message});

  final String message;

  static final RegExp _tokenPattern = RegExp(
    r'(\[\[danger:[^\]]+\]\]|\*\*[^*]+\*\*)',
    multiLine: true,
  );

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: AppColors.textPrimary,
    );
    final spans = <TextSpan>[];
    int cursor = 0;
    for (final match in _tokenPattern.allMatches(message)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: message.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('[[danger:') && token.endsWith(']]')) {
        final content = token.substring(9, token.length - 2);
        spans.add(
          TextSpan(
            text: content,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.error,
            ),
          ),
        );
      } else if (token.startsWith('**') && token.endsWith('**')) {
        final content = token.substring(2, token.length - 2);
        spans.add(
          TextSpan(
            text: content,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else {
        spans.add(TextSpan(text: token));
      }
      cursor = match.end;
    }
    if (cursor < message.length) {
      spans.add(TextSpan(text: message.substring(cursor)));
    }

    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }
}

class _MaskWithHoleClipper extends CustomClipper<Path> {
  const _MaskWithHoleClipper({required this.holeRect, required this.circular});

  final Rect holeRect;
  final bool circular;

  @override
  Path getClip(Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final hole = circular
        ? (Path()..addOval(holeRect))
        : (Path()
          ..addRRect(
            RRect.fromRectAndRadius(holeRect, const Radius.circular(16)),
          ));
    return Path.combine(PathOperation.difference, full, hole);
  }

  @override
  bool shouldReclip(covariant _MaskWithHoleClipper oldClipper) {
    return oldClipper.holeRect != holeRect || oldClipper.circular != circular;
  }
}

class _AnimatedMaskWithHole extends StatefulWidget {
  const _AnimatedMaskWithHole({
    required this.baseHoleRect,
    required this.circular,
    required this.maskColor,
    required this.minScale,
    required this.maxScale,
    this.onTap,
  });

  final Rect baseHoleRect;
  final bool circular;
  final Color maskColor;
  final double minScale;
  final double maxScale;
  final VoidCallback? onTap;

  @override
  State<_AnimatedMaskWithHole> createState() => _AnimatedMaskWithHoleState();
}

class _AnimatedMaskWithHoleState extends State<_AnimatedMaskWithHole>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  bool get _isStaticPulse =>
      (widget.maxScale - widget.minScale).abs() < 0.0001;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(
      begin: widget.minScale,
      end: widget.maxScale,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (!_isStaticPulse) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedMaskWithHole oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasStatic =
        (oldWidget.maxScale - oldWidget.minScale).abs() < 0.0001;
    if (wasStatic == _isStaticPulse) return;
    if (_isStaticPulse) {
      _controller.stop();
      _controller.value = 0;
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isStaticPulse) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap ?? () {},
        child: ClipPath(
          clipBehavior: Clip.hardEdge,
          clipper: _MaskWithHoleClipper(
            holeRect: widget.baseHoleRect,
            circular: widget.circular,
          ),
          child: ColoredBox(color: widget.maskColor),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final scaled = Rect.fromCenter(
          center: widget.baseHoleRect.center,
          width: widget.baseHoleRect.width * _scale.value,
          height: widget.baseHoleRect.height * _scale.value,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap ?? () {},
          child: ClipPath(
            clipBehavior: Clip.hardEdge,
            clipper: _MaskWithHoleClipper(
              holeRect: scaled,
              circular: widget.circular,
            ),
            child: ColoredBox(color: widget.maskColor),
          ),
        );
      },
    );
  }
}

class _PassThroughMaskLayers extends StatefulWidget {
  const _PassThroughMaskLayers({
    required this.baseHoleRect,
    required this.circular,
    required this.maskColor,
    required this.minScale,
    required this.maxScale,
    this.onTap,
  });

  final Rect baseHoleRect;
  final bool circular;
  final Color maskColor;
  final double minScale;
  final double maxScale;
  final VoidCallback? onTap;

  @override
  State<_PassThroughMaskLayers> createState() => _PassThroughMaskLayersState();
}

class _PassThroughMaskLayersState extends State<_PassThroughMaskLayers>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  bool get _isStaticPulse =>
      (widget.maxScale - widget.minScale).abs() < 0.0001;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(
      begin: widget.minScale,
      end: widget.maxScale,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (!_isStaticPulse) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant _PassThroughMaskLayers oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasStatic =
        (oldWidget.maxScale - oldWidget.minScale).abs() < 0.0001;
    if (wasStatic == _isStaticPulse) return;
    if (_isStaticPulse) {
      _controller.stop();
      _controller.value = 0;
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _tappableMask({required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap ?? () {},
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isStaticPulse) {
      return _buildLayers(widget.baseHoleRect);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final holeRect = Rect.fromCenter(
          center: widget.baseHoleRect.center,
          width: widget.baseHoleRect.width * _scale.value,
          height: widget.baseHoleRect.height * _scale.value,
        );
        return _buildLayers(holeRect);
      },
    );
  }

  Widget _buildLayers(Rect holeRect) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: holeRect.top.clamp(0, double.infinity).toDouble(),
          child: _tappableMask(child: ColoredBox(color: widget.maskColor)),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: holeRect.bottom,
          bottom: 0,
          child: _tappableMask(child: ColoredBox(color: widget.maskColor)),
        ),
        Positioned(
          left: 0,
          top: holeRect.top,
          width: holeRect.left.clamp(0, double.infinity).toDouble(),
          height: holeRect.height,
          child: _tappableMask(child: ColoredBox(color: widget.maskColor)),
        ),
        Positioned(
          left: holeRect.right,
          right: 0,
          top: holeRect.top,
          height: holeRect.height,
          child: _tappableMask(child: ColoredBox(color: widget.maskColor)),
        ),
      ],
    );
  }
}

Future<Rect?> resolveRectWithRetry(
  GlobalKey key, {
  GlobalKey? ancestorKey,
  GlobalKey? coordinateSpaceKey,
  int maxRetries = 5,
  int intervalMs = 200,
}) async {
  for (int i = 0; i < maxRetries; i++) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final globalOffset = box.localToGlobal(Offset.zero);
      Offset offset = globalOffset;
      if (coordinateSpaceKey != null) {
        final coordinateBox =
            coordinateSpaceKey.currentContext?.findRenderObject() as RenderBox?;
        if (coordinateBox == null || !coordinateBox.hasSize) {
          await Future.delayed(Duration(milliseconds: intervalMs));
          continue;
        }
        offset = globalOffset - coordinateBox.localToGlobal(Offset.zero);
      } else if (ancestorKey != null) {
        final ancestorBox =
            ancestorKey.currentContext?.findRenderObject() as RenderBox?;
        if (ancestorBox == null || !ancestorBox.hasSize) {
          await Future.delayed(Duration(milliseconds: intervalMs));
          continue;
        }
        offset = ancestorBox.globalToLocal(globalOffset);
      }
      return Rect.fromLTWH(
        offset.dx,
        offset.dy,
        box.size.width,
        box.size.height,
      );
    }
    await Future.delayed(Duration(milliseconds: intervalMs));
  }
  return null;
}
