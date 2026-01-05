import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';

/// 統一されたEmpty State表示
/// フレンドリーで温かみのあるデザイン
class EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String? subtitle;
  final Widget? action;
  final bool enableAnimation;

  const EmptyState({
    super.key,
    required this.emoji,
    required this.title,
    this.subtitle,
    this.action,
    this.enableAnimation = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 装飾的な背景サークル
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primaryLight.withValues(alpha: 0.3),
                    AppColors.secondaryLight.withValues(alpha: 0.3),
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 56),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );

    if (enableAnimation) {
      return content
          .animate()
          .fadeIn(duration: 600.ms, curve: Curves.easeOut)
          .scale(
            begin: const Offset(0.9, 0.9),
            end: const Offset(1.0, 1.0),
            duration: 600.ms,
            curve: Curves.easeOut,
          );
    }

    return content;
  }
}

/// プリセットのEmpty State
class EmptyStates {
  EmptyStates._();

  /// 投稿がない
  static EmptyState noPosts({VoidCallback? onCreatePost}) => EmptyState(
        emoji: '✨',
        title: 'まだ投稿がないよ',
        subtitle: '最初の投稿をしてみよう！\nみんなが応援してくれるよ',
        action: onCreatePost != null
            ? _GlowingButton(
                onPressed: onCreatePost,
                label: '投稿する',
              )
            : null,
      );

  /// フォローしている人がいない
  static EmptyState noFollowing({VoidCallback? onExplore}) => EmptyState(
        emoji: '👥',
        title: 'まだ誰もフォローしていないよ',
        subtitle: '「おすすめ」タブで気になる人を\n見つけてフォローしてみよう！',
        action: onExplore != null
            ? _GlowingButton(
                onPressed: onExplore,
                label: 'おすすめを見る',
              )
            : null,
      );

  /// 通知がない
  static const EmptyState noNotifications = EmptyState(
    emoji: '🔔',
    title: '通知はまだないよ',
    subtitle: '投稿したりコメントすると\nここに通知が届くよ',
  );

  /// サークルがない
  static EmptyState noCircles({VoidCallback? onCreateCircle}) => EmptyState(
        emoji: '🌈',
        title: 'サークルがないよ',
        subtitle: '新しいサークルを作って\n仲間を集めよう！',
        action: onCreateCircle != null
            ? _GlowingButton(
                onPressed: onCreateCircle,
                label: 'サークルを作る',
              )
            : null,
      );

  /// タスクがない
  static EmptyState noTasks({VoidCallback? onCreateTask}) => EmptyState(
        emoji: '📝',
        title: '今日のタスクはないよ',
        subtitle: 'やりたいことを追加して\n一緒に頑張ろう！',
        action: onCreateTask != null
            ? _GlowingButton(
                onPressed: onCreateTask,
                label: 'タスクを追加',
              )
            : null,
      );

  /// 検索結果がない
  static const EmptyState noResults = EmptyState(
    emoji: '🔍',
    title: '見つからなかったよ',
    subtitle: '別のキーワードで試してみてね',
  );

  /// お気に入りがない
  static const EmptyState noFavorites = EmptyState(
    emoji: '⭐',
    title: 'お気に入りがないよ',
    subtitle: '投稿をお気に入りに追加すると\nここに表示されるよ',
  );

  /// エラー
  static EmptyState error({VoidCallback? onRetry}) => EmptyState(
        emoji: '😢',
        title: 'エラーが起きちゃった',
        subtitle: 'しばらくしてからもう一度試してね',
        action: onRetry != null
            ? _GlowingButton(
                onPressed: onRetry,
                label: 'もう一度試す',
              )
            : null,
      );
}

/// グロー効果のあるボタン
class _GlowingButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;

  const _GlowingButton({
    required this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
