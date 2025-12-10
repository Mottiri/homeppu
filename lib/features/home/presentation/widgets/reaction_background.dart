import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';

/// リアクションを背景に散りばめるウィジェット
/// 投稿IDをシードにして、リビルドしても同じ配置になるようにする
class ReactionBackground extends StatelessWidget {
  final Map<String, int> reactions;
  final String postId; // 配置のシードに使用
  final double opacity;
  final int? maxIcons;

  const ReactionBackground({
    super.key,
    required this.reactions,
    required this.postId,
    this.opacity = 0.2, // 少し濃くしても大丈夫そう
    this.maxIcons = 300,
  });

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

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

    reactions.forEach((key, count) {
      final type = ReactionType.values.firstWhere(
        (e) => e.value == key,
        orElse: () => ReactionType.love,
      );

      for (var i = 0; i < count; i++) {
        // PostID, 種類, その種類内のインデックス を組み合わせてシードにする
        // これにより、他のリアクションが増えても、このアイコン(#i)の配置シードは変わらない
        final seed = Object.hash(postId, key, i);
        list.add(_IconDatum(type.emoji, seed));
      }
    });

    // パフォーマンス制限
    if (maxIcons != null && list.length > maxIcons!) {
      // リスト先頭から300個に絞るが、シードは個別に持っているので配置はズレない
      return list.sublist(0, maxIcons!);
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

    // ランダムなサイズ (24 〜 56:少し大きめにしてみる)
    final size = 24.0 + random.nextDouble() * 32.0;

    return Positioned(
      left: left,
      top: top,
      child: Transform.rotate(
        angle: angle,
        child: Text(
          iconData.emoji,
          style: TextStyle(
            fontSize: size,
            // アルファ値も少しランダムにすると面白いかも
            color: Colors.black.withOpacity(
              opacity * (0.5 + random.nextDouble() * 0.5),
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

  _IconDatum(this.emoji, this.seed);
}
