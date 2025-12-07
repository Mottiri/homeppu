import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/models/post_model.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/widgets/report_dialog.dart';
import '../../../../shared/widgets/video_player_screen.dart';
import 'reaction_button.dart';

/// 投稿カード
class PostCard extends StatefulWidget {
  final PostModel post;
  final VoidCallback? onDeleted;

  const PostCard({super.key, required this.post, this.onDeleted});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _isDeleting = false;

  PostModel get post => widget.post;

  /// 自分の投稿かどうか
  bool get isMyPost {
    final currentUser = FirebaseAuth.instance.currentUser;
    return currentUser != null && currentUser.uid == post.userId;
  }

  /// 投稿を削除
  Future<void> _deletePost() async {
    // 確認ダイアログを表示
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('投稿を削除'),
        content: const Text('この投稿を削除しますか？\nこの操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      // Firestoreから投稿を削除
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(post.id)
          .delete();

      // 関連するコメントも削除
      final comments = await FirebaseFirestore.instance
          .collection('comments')
          .where('postId', isEqualTo: post.id)
          .get();
      
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in comments.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // ユーザーの投稿数を減少
      await FirebaseFirestore.instance
          .collection('users')
          .doc(post.userId)
          .update({
        'totalPosts': FieldValue.increment(-1),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('投稿を削除しました'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onDeleted?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('削除に失敗しました: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // timeagoの日本語設定
    timeago.setLocaleMessages('ja', timeago.JaMessages());
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => context.push('/post/${post.id}'),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ユーザー情報
              Row(
                children: [
                  GestureDetector(
                    onTap: () => context.push('/user/${post.userId}'),
                    child: AvatarWidget(
                      avatarIndex: post.userAvatarIndex,
                      size: 44,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => context.push('/user/${post.userId}'),
                          child: Text(
                            post.userDisplayName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        Text(
                          timeago.format(post.createdAt, locale: 'ja'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  // オプションメニュー（通報・削除など）
                  _isDeleting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_horiz,
                            color: AppColors.textHint,
                            size: 20,
                          ),
                          onSelected: (value) {
                            if (value == 'report') {
                              ReportDialog.show(
                                context: context,
                                contentId: post.id,
                                contentType: 'post',
                                targetUserId: post.userId,
                                contentPreview: post.content,
                              );
                            } else if (value == 'delete') {
                              _deletePost();
                            }
                          },
                          itemBuilder: (context) => [
                            // 自分の投稿なら削除オプションを表示
                            if (isMyPost)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('この投稿を削除', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            // 他人の投稿なら通報オプションを表示
                            if (!isMyPost)
                              const PopupMenuItem(
                                value: 'report',
                                child: Row(
                                  children: [
                                    Icon(Icons.flag_outlined, size: 18),
                                    SizedBox(width: 8),
                                    Text('この投稿を通報'),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // 投稿内容
              Text(
                post.content,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                ),
              ),
              
              // メディア表示
              if (post.allMedia.isNotEmpty) ...[
                const SizedBox(height: 12),
                _MediaGrid(mediaItems: post.allMedia),
              ],
              
              const SizedBox(height: 16),
              
              // リアクションエリア
              Row(
                children: [
                  ...ReactionType.values.map((type) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ReactionButton(
                      type: type,
                      count: post.reactions[type.value] ?? 0,
                      postId: post.id,
                    ),
                  )),
                  const Spacer(),
                  // コメント数
                  Row(
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline,
                        size: 18,
                        color: AppColors.textHint,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${post.commentCount}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// メディアグリッド表示
class _MediaGrid extends StatelessWidget {
  final List<MediaItem> mediaItems;

  const _MediaGrid({required this.mediaItems});

  @override
  Widget build(BuildContext context) {
    if (mediaItems.isEmpty) return const SizedBox.shrink();

    // メディア数に応じてレイアウトを変更
    if (mediaItems.length == 1) {
      return _buildSingleMedia(context, mediaItems.first);
    } else if (mediaItems.length == 2) {
      return _buildTwoMedia(context);
    } else if (mediaItems.length == 3) {
      return _buildThreeMedia(context);
    } else {
      return _buildFourMedia(context);
    }
  }

  Widget _buildSingleMedia(BuildContext context, MediaItem item) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: _buildMediaItem(context, item, height: 200),
    );
  }

  Widget _buildTwoMedia(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: _buildMediaItem(context, mediaItems[0], height: 150),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
            child: _buildMediaItem(context, mediaItems[1], height: 150),
          ),
        ),
      ],
    );
  }

  Widget _buildThreeMedia(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: _buildMediaItem(context, mediaItems[0], height: 200),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(topRight: Radius.circular(16)),
                child: _buildMediaItem(context, mediaItems[1], height: 98),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: const BorderRadius.only(bottomRight: Radius.circular(16)),
                child: _buildMediaItem(context, mediaItems[2], height: 98),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFourMedia(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(16)),
                child: _buildMediaItem(context, mediaItems[0], height: 100),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(topRight: Radius.circular(16)),
                child: _buildMediaItem(context, mediaItems[1], height: 100),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16)),
                child: _buildMediaItem(context, mediaItems[2], height: 100),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(bottomRight: Radius.circular(16)),
                child: _buildMediaItem(context, mediaItems.length > 3 ? mediaItems[3] : mediaItems[2], height: 100),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMediaItem(BuildContext context, MediaItem item, {required double height}) {
    switch (item.type) {
      case MediaType.image:
        return GestureDetector(
          onTap: () => _showFullScreenImage(context, item.url),
          child: CachedNetworkImage(
            imageUrl: item.url,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              height: height,
              color: Colors.grey.shade200,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              height: height,
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        );

      case MediaType.video:
        return GestureDetector(
          onTap: () => _showVideoPlayer(context, item.url),
          child: Container(
            height: height,
            color: Colors.black87,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // サムネイル（動画のプレビュー）
                if (item.url.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: item.url,
                    height: height,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      color: Colors.black54,
                    ),
                  ),
                // 再生アイコン
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ],
            ),
          ),
        );

      case MediaType.file:
        return GestureDetector(
          onTap: () => _openFile(context, item),
          child: Container(
            height: height,
            color: Colors.grey.shade100,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getFileIcon(item.fileName ?? ''),
                  size: 40,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    item.fileName ?? 'ファイル',
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (item.fileSize != null)
                  Text(
                    _formatFileSize(item.fileSize!),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
        );
    }
  }

  void _showFullScreenImage(BuildContext context, String url) {
    // rootNavigator: true でShellRouteの外で表示（ボトムナビを非表示）
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showVideoPlayer(BuildContext context, String url) {
    // rootNavigator: true でShellRouteの外で表示（ボトムナビを非表示）
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(videoUrl: url),
      ),
    );
  }

  void _openFile(BuildContext context, MediaItem item) {
    // TODO: ファイルダウンロード・表示を実装
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.fileName}を開きます')),
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'txt':
        return Icons.text_snippet;
      case 'zip':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
