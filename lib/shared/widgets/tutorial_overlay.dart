import 'dart:async';

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
    this.spotlightColor = const Color(0xFFFFC1C1),
    this.pulseMinScale = 0.94,
    this.pulseMaxScale = 1.06,
    this.frameBorderWidth = 2.6,
    this.frameGlowOpacity = 0.55,
    this.debugTag = 'overlay',
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

  // kept for API compatibility with callers; frame is intentionally disabled.
  final bool circularSpotlight;
  final Color spotlightColor;
  final double pulseMinScale;
  final double pulseMaxScale;
  final double frameBorderWidth;
  final double frameGlowOpacity;
  final String debugTag;

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

    return [
      Positioned.fill(
        child: _AnimatedMaskWithHole(
          baseHoleRect: spotlightRect!.inflate(_spotlightPadding),
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
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isActionEnabled;
  final String characterAssetPath;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ClipRRect(
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
        const SizedBox(width: 10),
        Expanded(
          child: Container(
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
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.5,
                    color: AppColors.textPrimary,
                  ),
                ),
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

class _MaskWithHoleClipper extends CustomClipper<Path> {
  const _MaskWithHoleClipper({required this.holeRect, required this.circular});

  final Rect holeRect;
  final bool circular;

  @override
  Path getClip(Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final hole = circular
        ? (Path()..addOval(holeRect))
        : (Path()..addRRect(
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: widget.minScale,
      end: widget.maxScale,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

Future<Rect?> resolveRectWithRetry(
  GlobalKey key, {
  GlobalKey? ancestorKey,
  int maxRetries = 5,
  int intervalMs = 200,
}) async {
  for (int i = 0; i < maxRetries; i++) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final offset = ancestorKey != null
          ? box.localToGlobal(
              Offset.zero,
              ancestor: ancestorKey.currentContext?.findRenderObject(),
            )
          : box.localToGlobal(Offset.zero);
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
