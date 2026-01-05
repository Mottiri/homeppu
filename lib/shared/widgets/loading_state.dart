import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';

/// 統一されたLoading State表示
/// フレンドリーでブランドに合ったデザイン
class LoadingState extends StatelessWidget {
  final String? message;
  final LoadingStyle style;

  const LoadingState({
    super.key,
    this.message,
    this.style = LoadingStyle.dots,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLoader(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            )
                .animate(onPlay: (controller) => controller.repeat())
                .fadeIn(duration: 600.ms)
                .then()
                .fadeOut(duration: 600.ms),
          ],
        ],
      ),
    );
  }

  Widget _buildLoader() {
    switch (style) {
      case LoadingStyle.dots:
        return const _BouncingDots();
      case LoadingStyle.pulse:
        return const _PulsingCircle();
      case LoadingStyle.wave:
        return const _WaveLoader();
      case LoadingStyle.spinner:
        return const _GradientSpinner();
    }
  }
}

enum LoadingStyle { dots, pulse, wave, spinner }

/// バウンシングドットのローダー
class _BouncingDots extends StatelessWidget {
  const _BouncingDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: _Dot(delay: index * 200),
        );
      }),
    );
  }
}

class _Dot extends StatelessWidget {
  final int delay;

  const _Dot({required this.delay});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .slideY(
          begin: 0,
          end: -0.5,
          duration: 400.ms,
          delay: delay.ms,
          curve: Curves.easeInOut,
        )
        .then()
        .slideY(
          begin: -0.5,
          end: 0,
          duration: 400.ms,
          curve: Curves.easeInOut,
        );
  }
}

/// パルシングサークルのローダー
class _PulsingCircle extends StatelessWidget {
  const _PulsingCircle();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 外側のパルス
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.3),
                AppColors.primary.withValues(alpha: 0.0),
              ],
            ),
          ),
        )
            .animate(onPlay: (controller) => controller.repeat())
            .scale(
              begin: const Offset(1.0, 1.0),
              end: const Offset(1.5, 1.5),
              duration: 1000.ms,
              curve: Curves.easeOut,
            )
            .fadeOut(duration: 1000.ms),
        // 内側のサークル
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
        )
            .animate(onPlay: (controller) => controller.repeat())
            .scale(
              begin: const Offset(1.0, 1.0),
              end: const Offset(0.9, 0.9),
              duration: 500.ms,
              curve: Curves.easeInOut,
            )
            .then()
            .scale(
              begin: const Offset(0.9, 0.9),
              end: const Offset(1.0, 1.0),
              duration: 500.ms,
              curve: Curves.easeInOut,
            ),
      ],
    );
  }
}

/// ウェーブローダー
class _WaveLoader extends StatelessWidget {
  const _WaveLoader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          child: _WaveBar(delay: index * 100),
        );
      }),
    );
  }
}

class _WaveBar extends StatelessWidget {
  final int delay;

  const _WaveBar({required this.delay});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 24,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(3),
      ),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .scaleY(
          begin: 0.5,
          end: 1.0,
          duration: 300.ms,
          delay: delay.ms,
          curve: Curves.easeInOut,
        )
        .then()
        .scaleY(
          begin: 1.0,
          end: 0.5,
          duration: 300.ms,
          curve: Curves.easeInOut,
        );
  }
}

/// グラデーションスピナー
class _GradientSpinner extends StatelessWidget {
  const _GradientSpinner();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: CircularProgressIndicator(
        strokeWidth: 4,
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        backgroundColor: AppColors.primaryLight.withValues(alpha: 0.3),
      ),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .rotate(duration: 1000.ms, curve: Curves.linear);
  }
}

/// プリセットのLoading State
class LoadingStates {
  LoadingStates._();

  /// 投稿読み込み中
  static const LoadingState posts = LoadingState(
    message: 'みんなの投稿を読み込み中...',
    style: LoadingStyle.dots,
  );

  /// 通知読み込み中
  static const LoadingState notifications = LoadingState(
    message: 'お知らせを確認中...',
    style: LoadingStyle.pulse,
  );

  /// プロフィール読み込み中
  static const LoadingState profile = LoadingState(
    message: 'プロフィールを読み込み中...',
    style: LoadingStyle.wave,
  );

  /// 汎用ローディング
  static const LoadingState general = LoadingState(
    style: LoadingStyle.dots,
  );

  /// 送信中
  static const LoadingState sending = LoadingState(
    message: '送信中...',
    style: LoadingStyle.spinner,
  );

  /// 保存中
  static const LoadingState saving = LoadingState(
    message: '保存しています...',
    style: LoadingStyle.pulse,
  );
}
