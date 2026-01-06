import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// 画像から色を抽出するサービス
class ColorExtractionService {
  /// ネットワーク画像から色を抽出
  static Future<Map<String, int>?> extractColorsFromNetworkImage(
    String imageUrl,
  ) async {
    try {
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        NetworkImage(imageUrl),
        size: const Size(200, 200), // 処理を軽くするためリサイズ
        maximumColorCount: 10,
      );

      // プライマリカラーの決定（優先順位）
      final primaryColor =
          paletteGenerator.dominantColor?.color ??
          paletteGenerator.vibrantColor?.color ??
          paletteGenerator.mutedColor?.color;

      // セカンダリカラーの決定
      final secondaryColor =
          paletteGenerator.vibrantColor?.color ??
          paletteGenerator.lightVibrantColor?.color ??
          paletteGenerator.mutedColor?.color ??
          paletteGenerator.lightMutedColor?.color;

      if (primaryColor == null) return null;

      return {
        'primary': primaryColor.toARGB32(),
        'secondary': (secondaryColor ?? primaryColor).toARGB32(),
      };
    } catch (e) {
      debugPrint('ColorExtractionService: Failed to extract colors: $e');
      return null;
    }
  }
}

/// Color拡張: ARGB intに変換
extension ColorExtension on Color {
  int toARGB32() {
    return (a.toInt() << 24) | (r.toInt() << 16) | (g.toInt() << 8) | b.toInt();
  }
}

/// int拡張: Colorに変換
extension IntColorExtension on int {
  Color toColor() {
    return Color(this);
  }
}
