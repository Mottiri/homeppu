import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/recent_reactions_service.dart';

/// リアクションボタン
class ReactionButton extends ConsumerStatefulWidget {
  final ReactionType type;
  final int count;
  final String postId;
  final void Function(String reactionType)? onReactionAdded; // リアクション追加時のコールバック

  const ReactionButton({
    super.key,
    required this.type,
    required this.count,
    required this.postId,
    this.onReactionAdded,
  });

  @override
  ConsumerState<ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends ConsumerState<ReactionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isReacted = false;
  bool _showSparkle = false;

  bool get _isEpic => widget.type.rarity == ReactionRarity.epic;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500), // 500msでしっかり見せる
      vsync: this,
    );
    // 大きく登場して戻るアニメーション
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 2.5,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40, // 最初の40%で大きくなる
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 2.5,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60, // 残り60%で戻る
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    // 既にリアクション済みの場合は削除処理（アニメーションなし）
    if (_isReacted) {
      setState(() => _isReacted = false);
      try {
        final functions = FirebaseFunctions.instanceFor(
          region: AppConstants.functionsRegion,
        );
        final callable = functions.httpsCallable('removeUserReaction');
        await callable.call({
          'postId': widget.postId,
          'reactionType': widget.type.value,
        });
      } catch (e) {
        setState(() => _isReacted = true);
      }
      return;
    }

    // リアクション追加：アニメーション付き
    setState(() {
      _isReacted = true;
      if (_isEpic) _showSparkle = true;
    });

    // アニメーション開始
    _controller.reset();
    _controller.forward();

    // アニメーション完了を待つ（500ms）
    await Future.delayed(const Duration(milliseconds: 500));

    if (_isEpic && mounted) {
      setState(() => _showSparkle = false);
    }

    // 親にリアクション追加を通知（シートは閉じない）
    widget.onReactionAdded?.call(widget.type.value);

    // Cloud Functionsはバックグラウンドで実行
    _sendReactionToServer();
  }

  /// リアクションをサーバーに送信（バックグラウンド実行）
  Future<void> _sendReactionToServer() async {
    try {
      final functions = FirebaseFunctions.instanceFor(
        region: AppConstants.functionsRegion,
      );
      final callable = functions.httpsCallable('addUserReaction');
      await callable.call({
        'postId': widget.postId,
        'reactionType': widget.type.value,
      });
      await RecentReactionsService.addReaction(widget.type.value);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        // 回数制限エラー（既にシートは閉じているのでログのみ）
        debugPrint('Reaction limit reached: ${e.message}');
      }
    } catch (e) {
      debugPrint('Reaction error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.type.colorValue);

    return GestureDetector(
      onTap: _onTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _isReacted ? _scaleAnimation.value : 1.0,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _isReacted
                        ? color.withValues(alpha: 0.2)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isReacted
                          ? color.withValues(alpha: 0.5)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [_ReactionIcon(type: widget.type)],
                  ),
                ),
                // Epicのみスパークル
                if (_showSparkle)
                  Positioned.fill(
                    child: _EpicSparkleOverlay(controller: _controller),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Epic リアクション専用のスパークルオーバーレイ
class _EpicSparkleOverlay extends StatelessWidget {
  final AnimationController controller;

  const _EpicSparkleOverlay({required this.controller});

  static const _count = 8;
  static const _angles = [0.0, 0.79, 1.57, 2.36, 3.14, 3.93, 4.71, 5.50];
  static const _icons = ['✦', '♡', '✧', '⋆', '✦', '♡', '✧', '⋆'];
  static const _colors = [
    Color(0xFFFF6B9D), // pink
    Color(0xFFFFD93D), // gold
    Color(0xFFFF8C42), // coral
    Color(0xFF6EC6FF), // cyan
    Color(0xFFC77DFF), // purple
    Color(0xFFA8E063), // lime
    Color(0xFFFF6B9D), // pink
    Color(0xFFFFD93D), // gold
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Particles appear from 15% to 85% of the animation.
        final raw = ((controller.value - 0.15) / 0.70).clamp(0.0, 1.0);
        final t = Curves.easeOut.transform(raw);
        if (t <= 0) return const SizedBox();
        return Stack(
          clipBehavior: Clip.none,
          children: [for (var i = 0; i < _count; i++) _buildParticle(i, t)],
        );
      },
    );
  }

  Widget _buildParticle(int index, double t) {
    final angle = _angles[index];
    final distance = 12.0 + (t * 24.0);
    final dx = distance * math.cos(angle);
    final dy = distance * math.sin(angle);
    final opacity = (1.0 - t).clamp(0.0, 1.0);
    final size = 8.0 + (1 - t) * 4.0;
    return Positioned.fill(
      child: Center(
        child: Transform.translate(
          offset: Offset(dx, dy),
          child: Opacity(
            opacity: opacity,
            child: Text(
              _icons[index],
              style: TextStyle(
                fontSize: size,
                color: _colors[index],
                shadows: [
                  Shadow(
                    color: _colors[index].withValues(alpha: 0.6),
                    blurRadius: 4,
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

/// リアクションアイコン（アセットがあれば画像、なければ絵文字）
class _ReactionIcon extends StatelessWidget {
  final ReactionType type;
  static const double _size = 32.0;

  const _ReactionIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      type.assetPath,
      width: _size,
      height: _size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        // アセットがない場合は絵文字にフォールバック
        return Text(type.emoji, style: const TextStyle(fontSize: 18));
      },
    );
  }
}
