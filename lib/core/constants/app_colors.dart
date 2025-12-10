import 'package:flutter/material.dart';

/// ほめっぷのカラーパレット
/// 暖色系・パステルカラーで攻撃性のない配色
class AppColors {
  AppColors._();

  // プライマリカラー（暖かみのあるコーラルピンク）
  static const Color primary = Color(0xFFFF8A80);
  static const Color primaryLight = Color(0xFFFFBCB0);
  static const Color primaryDark = Color(0xFFC85A54);

  // セカンダリカラー（優しいピーチオレンジ）
  static const Color secondary = Color(0xFFFFAB91);
  static const Color secondaryLight = Color(0xFFFFDDC1);
  static const Color secondaryDark = Color(0xFFC97B63);

  // アクセントカラー（温かみのあるイエロー）
  static const Color accent = Color(0xFFFFE082);
  static const Color accentLight = Color(0xFFFFFFB3);
  static const Color accentDark = Color(0xFFCAB053);

  // 背景色
  static const Color background = Color(0xFFFFFBF5);
  static const Color backgroundSecondary = Color(0xFFFFF3E8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFFFF8F2);

  // テキストカラー
  static const Color textPrimary = Color(0xFF4A4A4A);
  static const Color textSecondary = Color(0xFF7A7A7A);
  static const Color textTertiary = Color(0xFFCCCCCC); // より薄いグレー
  static const Color textHint = Color(0xFFAAAAAA);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // 特別なカラー
  static const Color love = Color(0xFFFF6B6B); // いいね・愛情表現
  static const Color praise = Color(0xFFFFD93D); // 称賛・すごい
  static const Color cheer = Color(0xFF6BCB77); // 応援・がんばれ
  static const Color empathy = Color(0xFF4D96FF); // 共感
  static const Color virtue = Color(0xFFB794F4); // 徳ポイント
  static const Color comment = Color(0xFF4DB6AC); // コメント（ティール）

  // システムカラー
  static const Color success = Color(0xFF81C784);
  static const Color warning = Color(0xFFFFB74D);
  static const Color error = Color(0xFFE57373);
  static const Color info = Color(0xFF64B5F6);

  // グラデーション
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  static const LinearGradient warmGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF3E8), Color(0xFFFFFBF5)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFFFF8F2)],
  );
}
