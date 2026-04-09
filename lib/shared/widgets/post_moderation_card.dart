import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_messages.dart';
import '../../core/utils/dialog_helper.dart';
import '../../core/utils/snackbar_helper.dart';
import '../models/post_model.dart';
import '../providers/moderation_provider.dart';
import '../providers/public_user_provider.dart';
import '../services/moderation_service.dart';
import 'public_user_avatar.dart';

enum _ModerationMenuAction { repost, delete }

class PostModerationCard extends ConsumerStatefulWidget {
  final PostModel post;
  final VoidCallback? onTap;
  final VoidCallback? onRepost;
  final VoidCallback? onDeleted;
  final EdgeInsetsGeometry margin;

  const PostModerationCard({
    super.key,
    required this.post,
    this.onTap,
    this.onRepost,
    this.onDeleted,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 0),
  });

  @override
  ConsumerState<PostModerationCard> createState() => _PostModerationCardState();
}

class _PostModerationCardState extends ConsumerState<PostModerationCard> {
  bool _isDeleting = false;

  Future<void> _deleteRejectedPost() async {
    final confirmed = await DialogHelper.showConfirmDialog(
      context: context,
      title: AppMessages.confirm.deleteTitle,
      message: AppMessages.confirm.deleteRejectedPost(),
      confirmText: AppMessages.label.delete,
      cancelText: AppMessages.label.cancel,
      isDangerous: true,
      barrierDismissible: false,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await ref
          .read(moderationServiceProvider)
          .deleteRejectedPost(postId: widget.post.id);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, AppMessages.success.postDeleted);
      widget.onDeleted?.call();
    } on ModerationException catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        e.message.isNotEmpty
            ? e.message
            : AppMessages.error.rejectedPostDeleteFailed,
      );
    } catch (_) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        AppMessages.error.rejectedPostDeleteFailed,
      );
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _resolveTone(widget.post);
    final media = widget.post.allMedia.isNotEmpty ? widget.post.allMedia.first : null;
    final displayName =
        ref.watch(publicUserDisplayNameProvider(widget.post.userId)) ??
        widget.post.userDisplayName;
    final canDelete = widget.post.isRejected;
    final hasMenu = canDelete || widget.onRepost != null;

    return Card(
      margin: widget.margin,
      clipBehavior: Clip.hardEdge,
      color: tone.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: tone.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PublicUserAvatar(
                      userId: widget.post.userId,
                      avatarIndex: widget.post.userAvatarIndex,
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            timeago.format(widget.post.createdAt, locale: 'ja'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(tone: tone),
                    const SizedBox(width: 4),
                    if (_isDeleting)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (hasMenu)
                      PopupMenuButton<_ModerationMenuAction>(
                        icon: const Icon(
                          Icons.more_horiz,
                          color: AppColors.textHint,
                          size: 20,
                        ),
                        onSelected: (value) async {
                          if (value == _ModerationMenuAction.repost) {
                            widget.onRepost?.call();
                            return;
                          }
                          await _deleteRejectedPost();
                        },
                        itemBuilder: (context) => [
                          if (widget.onRepost != null)
                            PopupMenuItem<_ModerationMenuAction>(
                              value: _ModerationMenuAction.repost,
                              child: Row(
                                children: [
                                  const Icon(Icons.edit_outlined, size: 18),
                                  const SizedBox(width: 8),
                                  Text(AppMessages.post.repostAction),
                                ],
                              ),
                            ),
                          if (canDelete)
                            PopupMenuItem<_ModerationMenuAction>(
                              value: _ModerationMenuAction.delete,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    AppMessages.label.delete,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                if (media != null) ...[
                  const SizedBox(height: 12),
                  _ModerationPreview(media: media),
                ],
                if (widget.post.content.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.post.content,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  _ModerationTone _resolveTone(PostModel post) {
    if (post.isRejected) {
      return _ModerationTone(
        label: AppMessages.post.rejectedStatus,
        background: Color(0xFFFFF1F1),
        border: Color(0xFFFFD3D3),
        badgeForeground: Color(0xFFC84C4C),
        badgeBackground: Color(0xFFFFE1E1),
      );
    }
    if (post.isReviewNeeded) {
      return _ModerationTone(
        label: AppMessages.post.reviewNeededStatus,
        background: Color(0xFFF5F7FF),
        border: Color(0xFFD9E1FF),
        badgeForeground: Color(0xFF5577D6),
        badgeBackground: Color(0xFFE7EDFF),
      );
    }
    return _ModerationTone(
      label: AppMessages.post.processingStatus,
      background: Color(0xFFFFFAEE),
      border: Color(0xFFF3E0B2),
      badgeForeground: Color(0xFFB9841A),
      badgeBackground: Color(0xFFFFF0C8),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final _ModerationTone tone;

  const _StatusBadge({required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.badgeBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tone.label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: tone.badgeForeground,
          fontWeight: FontWeight.bold,
        ),
      ),
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
        height: 200,
        width: double.infinity,
        child: switch (media.type) {
          MediaType.image => Image.network(
            previewUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const _FallbackPreview(
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
  final Color background;
  final Color border;
  final Color badgeForeground;
  final Color badgeBackground;

  const _ModerationTone({
    required this.label,
    required this.background,
    required this.border,
    required this.badgeForeground,
    required this.badgeBackground,
  });
}
