import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';

/// リアクションを背景に散りばめるウィジェット
/// 投稿IDをシードにして、リビルドしても同じ配置になるようにする
/// 新しいリアクションには登場アニメーションを適用
class ReactionBackground extends StatefulWidget {
  final Map<String, int> reactions;
  final String postId; // 配置のシードに使用
  final double opacity;
  final int? maxIcons;

  const ReactionBackground({
    super.key,
    required this.reactions,
    required this.postId,
    this.opacity = 0.2,
    this.maxIcons = 300,
  });

  @override
  State<ReactionBackground> createState() => _ReactionBackgroundState();
}

class _ReactionBackgroundState extends State<ReactionBackground>
    with TickerProviderStateMixin {
  // 前回のリアクション数を保存（新規検出用）
  Map<String, int> _previousReactions = {};

  // アニメーション中のアイコン（キー: "type_index", 値: AnimationController）
  final Map<String, AnimationController> _animatingIcons = {};

  @override
  void initState() {
    super.initState();
    _previousReactions = Map.from(widget.reactions);
  }

  @override
  void didUpdateWidget(ReactionBackground oldWidget) {
    super.didUpdateWidget(oldWidget);

    // リアクション数の変化を検出
    widget.reactions.forEach((type, newCount) {
      final oldCount = _previousReactions[type] ?? 0;

      if (newCount > oldCount) {
        // 新しいリアクションが追加された
        final addedCount = newCount - oldCount;
        for (var i = 0; i < addedCount; i++) {
          final key = '${type}_${oldCount + i}';
          _startAnimation(key);
        }
      }
    });

    _previousReactions = Map.from(widget.reactions);
  }

  void _startAnimation(String key) {
    // 既存のアニメーションがあれば破棄
    _animatingIcons[key]?.dispose();

    final controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _animatingIcons[key] = controller;

    controller.forward().then((_) {
      if (mounted) {
        controller.dispose();
        _animatingIcons.remove(key);
        setState(() {}); // アニメーション完了後に再描画
      }
    });

    setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _animatingIcons.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reactions.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        // アイコンのリストを生成
        final icons = _generateIconList();

        if (icons.isEmpty) return const SizedBox.shrink();

        // Stackで重ねて表示
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: icons.map((iconData) {
            return _buildStableIcon(width, height, iconData);
          }).toList(),
        );
      },
    );
  }

  List<_IconDatum> _generateIconList() {
    final List<_IconDatum> list = [];

    widget.reactions.forEach((key, count) {
      final type = ReactionType.values.firstWhere(
        (e) => e.value == key,
        orElse: () => ReactionType.love,
      );

      for (var i = 0; i < count; i++) {
        // PostID, 種類, その種類内のインデックス を組み合わせてシードにする
        final seed = Object.hash(widget.postId, key, i);
        final animationKey = '${key}_$i';
        list.add(_IconDatum(type.emoji, seed, animationKey));
      }
    });

    // パフォーマンス制限
    if (widget.maxIcons != null && list.length > widget.maxIcons!) {
      return list.sublist(0, widget.maxIcons!);
    }

    return list;
  }

  Widget _buildStableIcon(
    double parentWidth,
    double parentHeight,
    _IconDatum iconData,
  ) {
    final random = Random(iconData.seed);

    // ランダムな位置 (-10% 〜 110%)
    final left = random.nextDouble() * parentWidth * 1.2 - (parentWidth * 0.1);
    final top = random.nextDouble() * parentHeight * 1.2 - (parentHeight * 0.1);

    // ランダムな回転 (-45度 〜 +45度)
    final angle = (random.nextDouble() - 0.5) * 1.5;

    // ランダムなサイズ (24 〜 56)
    final baseSize = 24.0 + random.nextDouble() * 32.0;

    // アニメーション中かどうかチェック
    final controller = _animatingIcons[iconData.animationKey];
    final isAnimating = controller != null && controller.isAnimating;

    if (isAnimating) {
      // アニメーション中: 大きい→小さくなる
      return Positioned(
        left: left,
        top: top,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            // 開始時は2.5倍、終了時は1倍
            final scale = 2.5 - (controller.value * 1.5);
            // 開始時は不透明、終了時は通常の透明度
            final animatedOpacity =
                1.0 - (controller.value * (1.0 - widget.opacity));

            return Transform.rotate(
              angle: angle,
              child: Transform.scale(
                scale: scale,
                child: Text(
                  iconData.emoji,
                  style: TextStyle(
                    fontSize: baseSize,
                    color: Colors.black.withValues(
                      alpha:
                          animatedOpacity * (0.5 + random.nextDouble() * 0.5),
                    ),
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    // 通常表示
    return Positioned(
      left: left,
      top: top,
      child: Transform.rotate(
        angle: angle,
        child: Text(
          iconData.emoji,
          style: TextStyle(
            fontSize: baseSize,
            color: Colors.black.withValues(
              alpha: widget.opacity * (0.5 + random.nextDouble() * 0.5),
            ),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _IconDatum {
  final String emoji;
  final int seed;
  final String animationKey;

  _IconDatum(this.emoji, this.seed, this.animationKey);
}
