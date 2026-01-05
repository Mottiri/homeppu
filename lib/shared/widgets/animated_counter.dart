import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// アニメーション付きカウンター
/// 数値の変化をスムーズにアニメーションで表示
class AnimatedCounter extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;
  final String? prefix;
  final String? suffix;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 500),
    this.curve = Curves.easeOutCubic,
    this.prefix,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      curve: curve,
      builder: (context, animatedValue, child) {
        return Text(
          '${prefix ?? ''}$animatedValue${suffix ?? ''}',
          style: style ??
              Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
        );
      },
    );
  }
}

/// アニメーション付きカウンター（ラベル付き）
class LabeledAnimatedCounter extends StatelessWidget {
  final int value;
  final String label;
  final IconData? icon;
  final Color? color;
  final Duration duration;
  final bool showAnimation;

  const LabeledAnimatedCounter({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.color,
    this.duration = const Duration(milliseconds: 600),
    this.showAnimation = true,
  });

  @override
  Widget build(BuildContext context) {
    final displayColor = color ?? AppColors.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: displayColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: displayColor, size: 22),
          ),
          const SizedBox(height: 8),
        ],
        showAnimation
            ? TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: value),
                duration: duration,
                curve: Curves.easeOutCubic,
                builder: (context, animatedValue, child) {
                  return Text(
                    _formatNumber(animatedValue),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: displayColor,
                        ),
                  );
                },
              )
            : Text(
                _formatNumber(value),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: displayColor,
                    ),
              ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }

  String _formatNumber(int number) {
    if (number >= 10000) {
      return '${(number / 10000).toStringAsFixed(1)}万';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}k';
    }
    return number.toString();
  }
}
