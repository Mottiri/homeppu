import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';

/// Frontend Design Skill原則に基づいた強化カード
/// - 立体的なグラデーション
/// - 深みのある影
/// - マイクロインタラクション（ホバー効果の代わりに長押し効果）
class EnhancedCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enableAnimation;
  final int index; // リスト内での位置（非対称レイアウト用）

  const EnhancedCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
    this.onTap,
    this.onLongPress,
    this.enableAnimation = true,
    this.index = 0,
  });

  @override
  State<EnhancedCard> createState() => _EnhancedCardState();
}

class _EnhancedCardState extends State<EnhancedCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    // 非対称的なマージン（偶数・奇数で左右のパディングを変える）
    final isEven = widget.index % 2 == 0;
    final asymmetricMargin = widget.margin ??
        EdgeInsets.only(
          left: isEven ? 16 : 24,
          right: isEven ? 24 : 16,
          top: 8,
          bottom: 8,
        );

    Widget card = GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: asymmetricMargin,
        decoration: BoxDecoration(
          // 立体的なグラデーション背景
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            // 深みのある影（Frontend Design Skill原則）
            BoxShadow(
              color: AppColors.primary.withValues(alpha: _isPressed ? 0.25 : 0.15),
              blurRadius: _isPressed ? 12 : 20,
              offset: Offset(0, _isPressed ? 4 : 8),
              spreadRadius: _isPressed ? 0 : 2,
            ),
            // 二重影で深さを強調
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: _isPressed ? 0.1 : 0.05),
              blurRadius: _isPressed ? 6 : 10,
              offset: Offset(0, _isPressed ? 2 : 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: widget.padding ?? const EdgeInsets.all(16),
            child: widget.child,
          ),
        ),
      ),
    );

    // アニメーション有効時
    if (widget.enableAnimation) {
      return card
          .animate()
          .fadeIn(duration: 400.ms)
          .slideY(
            begin: 0.1,
            end: 0,
            duration: 400.ms,
            curve: Curves.easeOut,
          );
    }

    return card;
  }
}
