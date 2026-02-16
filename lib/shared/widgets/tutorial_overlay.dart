import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// チュートリアルオーバーレイ
///
/// 画面全体にグレーマスクを重ね、指定された領域をスポットライト（穴）として透過する。
/// 下部にキャラ画像 + 吹き出しを表示する。
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
    this.characterAssetPath = 'assets/onbord/onbord_01.png',
    this.bubbleBottomOffset,
    this.circularSpotlight = false,
    this.spotlightColor = Colors.white,
    this.pulseMinScale = 0.94,
    this.pulseMaxScale = 1.06,
    this.frameBorderWidth = 2.6,
    this.frameGlowOpacity = 0.55,
  });

  /// 吹き出しに表示するメッセージ
  final String message;

  /// スポットライト領域（null の場合は穴なし＝全面マスク）
  final Rect? spotlightRect;

  /// アクションボタンのラベル（null ならボタン非表示）
  final String? actionLabel;

  /// アクションボタンのコールバック
  final VoidCallback? onAction;

  /// アクションボタンの有効/無効
  final bool isActionEnabled;

  /// スポットライト領域がタップされた時のコールバック
  final VoidCallback? onSpotlightTap;

  /// キャラ画像のアセットパス
  final String characterAssetPath;

  /// 吹き出しの下端オフセット（null の場合は safeArea + 16）
  final double? bubbleBottomOffset;

  /// スポットライトを円形で表示するか
  final bool circularSpotlight;

  /// スポットライト枠の色
  final Color spotlightColor;

  /// 脈動アニメーションの最小スケール
  final double pulseMinScale;

  /// 脈動アニメーションの最大スケール
  final double pulseMaxScale;

  /// フレーム線の太さ
  final double frameBorderWidth;

  /// フレーム外周グローの不透明度
  final double frameGlowOpacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // マスク領域
        ..._buildMasks(context),

        if (spotlightRect != null)
          Builder(
            builder: (context) {
              final frameRect = spotlightRect!.inflate(_spotlightPadding);
              return Positioned(
                left: frameRect.left,
                top: frameRect.top,
                width: frameRect.width,
                height: frameRect.height,
                child: IgnorePointer(
                  child: OverflowBox(
                    alignment: Alignment.center,
                    minWidth: frameRect.width,
                    minHeight: frameRect.height,
                    maxWidth: frameRect.width * 2.2,
                    maxHeight: frameRect.height * 2.2,
                    child: _AnimatedSpotlightFrame(
                      rect: frameRect,
                      circular: circularSpotlight,
                      frameColor: spotlightColor,
                      minScale: pulseMinScale,
                      maxScale: pulseMaxScale,
                      borderWidth: frameBorderWidth,
                      glowOpacity: frameGlowOpacity,
                    ),
                  ),
                ),
              );
            },
          ),

        // スポットライト領域のタップ検出
        if (spotlightRect != null && onSpotlightTap != null)
          Positioned.fromRect(
            rect: spotlightRect!,
            child: GestureDetector(
              onTap: onSpotlightTap,
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),

        // キャラ + 吹き出し
        Positioned(
          left: 12,
          right: 12,
          bottom:
              bubbleBottomOffset ?? (MediaQuery.of(context).padding.bottom + 16),
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

  List<Widget> _buildMasks(BuildContext context) {
    const maskColor = Color(0x66000000);

    if (spotlightRect == null) {
      // 穴なし＝全面マスク
      return [
        Positioned.fill(
          child: GestureDetector(
            onTap: () {}, // タップ吸収
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
        ),
      ),
    ];
  }
}

/// キャラ + 吹き出しウィジェット
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
        // キャラ画像
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

        // 吹き出し
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
  final Rect holeRect;
  final bool circular;

  const _MaskWithHoleClipper({required this.holeRect, required this.circular});

  @override
  Path getClip(Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final hole = circular
        ? (Path()..addOval(holeRect))
        : (Path()..addRRect(RRect.fromRectAndRadius(holeRect, const Radius.circular(16))));
    return Path.combine(PathOperation.difference, full, hole);
  }

  @override
  bool shouldReclip(covariant _MaskWithHoleClipper oldClipper) {
    return oldClipper.holeRect != holeRect || oldClipper.circular != circular;
  }
}

class _AnimatedSpotlightFrame extends StatefulWidget {
  final Rect rect;
  final bool circular;
  final Color frameColor;
  final double minScale;
  final double maxScale;
  final double borderWidth;
  final double glowOpacity;

  const _AnimatedSpotlightFrame({
    required this.rect,
    required this.circular,
    required this.frameColor,
    required this.minScale,
    required this.maxScale,
    required this.borderWidth,
    required this.glowOpacity,
  });

  @override
  State<_AnimatedSpotlightFrame> createState() => _AnimatedSpotlightFrameState();
}

class _AnimatedSpotlightFrameState extends State<_AnimatedSpotlightFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fillAlpha;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: widget.minScale, end: widget.maxScale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    // 中身が静止に見えないよう、内側ハイライトの脈動を強める。
    _fillAlpha = Tween<double>(begin: 0.04, end: 0.22).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Transform.scale(
            scale: _scale.value,
            child: Container(
              width: widget.rect.width,
              height: widget.rect.height,
              decoration: widget.circular
                  ? BoxDecoration(
                      color: widget.frameColor.withValues(alpha: _fillAlpha.value),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.frameColor,
                        width: widget.borderWidth,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.frameColor.withValues(
                            alpha: widget.glowOpacity,
                          ),
                          blurRadius: 12,
                        ),
                      ],
                    )
                  : BoxDecoration(
                      color: widget.frameColor.withValues(alpha: _fillAlpha.value),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: widget.frameColor,
                        width: widget.borderWidth,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: widget.frameColor.withValues(
                            alpha: widget.glowOpacity,
                          ),
                          blurRadius: 12,
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _AnimatedMaskWithHole extends StatefulWidget {
  final Rect baseHoleRect;
  final bool circular;
  final Color maskColor;
  final double minScale;
  final double maxScale;

  const _AnimatedMaskWithHole({
    required this.baseHoleRect,
    required this.circular,
    required this.maskColor,
    required this.minScale,
    required this.maxScale,
  });

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
    _scale = Tween<double>(begin: widget.minScale, end: widget.maxScale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
          onTap: () {},
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

/// GlobalKey から Rect を取得するヘルパー（リトライ付き）
///
/// 最大 [maxRetries] 回、[interval] ms 間隔でリトライする。
/// 取得できなかった場合は null を返す。
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
