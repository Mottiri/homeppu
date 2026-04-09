import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_messages.dart';
import '../models/post_model.dart';

class PostModerationCard extends StatelessWidget {
  final PostModel post;
  final VoidCallback? onTap;
  final VoidCallback? onRepost;
  final EdgeInsetsGeometry margin;

  const PostModerationCard({
    super.key,
    required this.post,
    this.onTap,
    this.onRepost,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 0),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _resolveTone();
    final media = post.allMedia.isNotEmpty ? post.allMedia.first : null;
    final child = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(tone.icon, color: tone.foreground, size: 18),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: tone.foreground.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        tone.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tone.foreground,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (media != null) ...[
                  const SizedBox(height: 12),
                  _ModerationPreview(media: media),
                ],
                if (post.content.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    post.content,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  tone.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppMessages.post.ownerOnlyHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                if (post.isRejected && onRepost != null) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: onRepost,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(AppMessages.post.repostAction),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return child;
  }

  _ModerationTone _resolveTone() {
    if (post.isRejected) {
      return _ModerationTone(
        label: AppMessages.post.rejectedStatus,
        description: AppMessages.post.rejectedDescription,
        background: const Color(0xFFFFF1F1),
        border: const Color(0xFFFFD3D3),
        foreground: const Color(0xFFC84C4C),
        icon: Icons.report_gmailerrorred_outlined,
      );
    }
    if (post.isReviewNeeded) {
      return _ModerationTone(
        label: AppMessages.post.reviewNeededStatus,
        description: AppMessages.post.reviewNeededDescription,
        background: const Color(0xFFF5F7FF),
        border: const Color(0xFFD9E1FF),
        foreground: const Color(0xFF5577D6),
        icon: Icons.hourglass_top_rounded,
      );
    }
    return _ModerationTone(
      label: AppMessages.post.processingStatus,
      description: AppMessages.post.processingDescription,
      background: const Color(0xFFFFFAEE),
      border: const Color(0xFFF3E0B2),
      foreground: const Color(0xFFB9841A),
      icon: Icons.schedule_rounded,
    );
  }
}

class _ModerationPreview extends StatelessWidget {
  final MediaItem media;

  const _ModerationPreview({required this.media});

  @override
  Widget build(BuildContext context) {
    final previewUrl = media.thumbnailUrl ?? media.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 160,
        width: double.infinity,
        child: switch (media.type) {
          MediaType.image => Image.network(
            previewUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _FallbackPreview(
              icon: Icons.broken_image_outlined,
            ),
          ),
          MediaType.video => Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black87),
              if (previewUrl.isNotEmpty)
                Image.network(
                  previewUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              const Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  size: 48,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          MediaType.file => const _FallbackPreview(
            icon: Icons.insert_drive_file_outlined,
          ),
        },
      ),
    );
  }
}

class _FallbackPreview extends StatelessWidget {
  final IconData icon;

  const _FallbackPreview({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.backgroundSecondary,
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.textSecondary, size: 32),
    );
  }
}

class _ModerationTone {
  final String label;
  final String description;
  final Color background;
  final Color border;
  final Color foreground;
  final IconData icon;

  const _ModerationTone({
    required this.label,
    required this.description,
    required this.background,
    required this.border,
    required this.foreground,
    required this.icon,
  });
}
