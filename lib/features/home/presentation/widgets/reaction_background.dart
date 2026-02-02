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
  static const int defaultMaxIcons = 40;

  const ReactionBackground({
    super.key,
    required this.reactions,
    required this.postId,
    this.opacity = 0.2,
    this.maxIcons = defaultMaxIcons,
  });

  @override
  State<ReactionBackground> createState() => _ReactionBackgroundState();
}

class _ReactionBackgroundState extends State<ReactionBackground>
    with TickerProviderStateMixin {
  static const int _opacityCapThreshold = 25;
  static const double _opacityCapValue = 0.12;
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
      final reactionType = ReactionType.values.firstWhere(
        (e) => e.value == type,
        orElse: () => ReactionType.heart,
      );

      if (newCount > oldCount) {
        // 新しいリアクションが追加された
        final addedCount = newCount - oldCount;
        for (var i = 0; i < addedCount; i++) {
          final key = '${type}_${oldCount + i}';
          _startAnimation(key, reactionType);
        }
      }
    });

    _previousReactions = Map.from(widget.reactions);
  }

  void _startAnimation(String key, ReactionType type) {
    // 既存のアニメーションがあれば破棄
    _animatingIcons[key]?.dispose();

    final controller = AnimationController(
      duration: Duration(milliseconds: type.rarity == ReactionRarity.epic ? 520 : type.rarity == ReactionRarity.rare ? 420 : 320),
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
        final totalCount = _totalReactionCount();
        final baseOpacity = totalCount >= _opacityCapThreshold
            ? min(widget.opacity, _opacityCapValue)
            : widget.opacity;

        // アイコンのリストを生成
        final icons = _generateIconList();

        if (icons.isEmpty) return const SizedBox.shrink();

        // Stackで重ねて表示
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: icons.map((iconData) {
            return _buildStableIcon(width, height, iconData, baseOpacity);
          }).toList(),
        );
      },
    );
  }

  int _totalReactionCount() {
    return widget.reactions.values.fold(0, (sum, count) => sum + count);
  }

  List<_IconDatum> _generateIconList() {
    final List<_IconDatum> list = [];
    final limit = widget.maxIcons ?? ReactionBackground.defaultMaxIcons;

    widget.reactions.forEach((key, count) {
      final type = ReactionType.values.firstWhere(
        (e) => e.value == key,
        orElse: () => ReactionType.heart,
      );

      for (var i = 0; i < count; i++) {
        if (limit > 0 && list.length >= limit) {
          return;
        }
        // PostID, 種類, その種類内のインデックス を組み合わせてシードにする
        final seed = Object.hash(widget.postId, key, i);
        final animationKey = '${key}_$i';
        list.add(_IconDatum(type, seed, animationKey));
      }
    });

    // パフォーマンス制限
    if (limit > 0 && list.length > limit) {
      return list.sublist(0, limit);
    }

    return list;
  }

  double _raritySizeScale(ReactionType type) {
    switch (type.rarity) {
      case ReactionRarity.common:
        return 1.0;
      case ReactionRarity.rare:
        return 1.4;
      case ReactionRarity.epic:
        return 2.0;
    }
  }

  double _rarityOpacityScale(ReactionType type) {
    switch (type.rarity) {
      case ReactionRarity.common:
        return 1.0;
      case ReactionRarity.rare:
        return 1.1;
      case ReactionRarity.epic:
        return 1.2;
    }
  }

  Curve _rarityCurve(ReactionType type) {
    switch (type.rarity) {
      case ReactionRarity.common:
        return Curves.easeOut;
      case ReactionRarity.rare:
        return Curves.easeOutBack;
      case ReactionRarity.epic:
        return Curves.elasticOut;
    }
  }

  Widget _wrapGlow(Widget child, ReactionType type) {
    if (type.rarity == ReactionRarity.common) return child;
    final color = type.rarityColor.withValues(
      alpha: type.rarity == ReactionRarity.epic ? 0.6 : 0.45,
    );
    final blur = type.rarity == ReactionRarity.epic ? 26.0 : 18.0;
    final spread = type.rarity == ReactionRarity.epic ? 3.0 : 2.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: blur,
            spreadRadius: spread,
          ),
        ],
      ),
      child: child,
    );
  }

  /// リアクションウィジェット（アセットがあれば画像、なければ絵文字）
  Widget _buildReactionWidget(ReactionType type, double size, double opacity) {
    return Image.asset(
      type.assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      opacity: AlwaysStoppedAnimation(opacity),
      errorBuilder: (context, error, stackTrace) {
        // アセットがない場合は絵文字にフォールバック
        return Text(
          type.emoji,
          style: TextStyle(
            fontSize: size,
            color: Colors.black.withValues(alpha: opacity),
            decoration: TextDecoration.none,
          ),
        );
      },
    );
  }

  Widget _buildStableIcon(
    double parentWidth,
    double parentHeight,
    _IconDatum iconData,
    double baseOpacity,
  ) {
    final random = Random(iconData.seed);

    // ??????? (-45? ? +45?)
    final angle = (random.nextDouble() - 0.5) * 1.5;

    // ???????? (22 ? 44) + ?????
    final baseSize = 22.0 + random.nextDouble() * 22.0;
    final rarityScale = _raritySizeScale(iconData.type);
    double size = baseSize * rarityScale;

    const padding = 6.0;
    final maxSize = min(parentWidth, parentHeight) - padding * 2;
    if (maxSize.isFinite && maxSize > 0) {
      size = size.clamp(16.0, maxSize);
    }

    final maxLeft = (parentWidth - size - padding * 2).clamp(0.0, parentWidth);
    final maxTop = (parentHeight - size - padding * 2).clamp(0.0, parentHeight);
    final left = padding + random.nextDouble() * maxLeft;
    final top = padding + random.nextDouble() * maxTop;

    final controller = _animatingIcons[iconData.animationKey];
    final isAnimating = controller != null && controller.isAnimating;

    if (isAnimating) {
      return Positioned(
        left: left,
        top: top,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final curveValue = _rarityCurve(iconData.type).transform(
              controller.value,
            );
            final startScale = iconData.type.rarity == ReactionRarity.epic
                ? 3.2
                : iconData.type.rarity == ReactionRarity.rare
                ? 2.6
                : 2.2;
            final endScale = iconData.type.rarity == ReactionRarity.epic
                ? 1.3
                : iconData.type.rarity == ReactionRarity.rare
                ? 1.1
                : 1.0;
            final scale = startScale - (curveValue * (startScale - endScale));

            final opacityScale = _rarityOpacityScale(iconData.type);
            final animatedOpacity =
                (1.0 - (controller.value * (1.0 - baseOpacity))) *
                opacityScale;

            final stamp = _buildReactionWidget(
              iconData.type,
              size,
              (animatedOpacity * (0.5 + random.nextDouble() * 0.5))
                  .clamp(0.0, 1.0),
            );

            return Transform.rotate(
              angle: angle,
              child: Transform.scale(
                scale: scale,
                child: _wrapGlow(stamp, iconData.type),
              ),
            );
          },
        ),
      );
    }

    // ????
    return Positioned(
      left: left,
      top: top,
      child: Transform.rotate(
        angle: angle,
        child: _buildReactionWidget(
          iconData.type,
          size,
          (baseOpacity * (0.5 + random.nextDouble() * 0.5) *
                  _rarityOpacityScale(iconData.type))
              .clamp(0.0, 1.0),
        ),
      ),
    );
  }
}

class _IconDatum {
  final ReactionType type;
  final int seed;
  final String animationKey;

  _IconDatum(this.type, this.seed, this.animationKey);
}
