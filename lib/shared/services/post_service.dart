import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_colors.dart';
import '../models/post_model.dart';
import 'media_service.dart';

/// 投稿関連の共通ロジックを提供するサービス
class PostService {
  static final PostService _instance = PostService._internal();
  factory PostService() => _instance;
  PostService._internal();

  final _firestore = FirebaseFirestore.instance;

  /// 投稿を削除する（確認ダイアログ付き）
  ///
  /// 以下の処理を一括で実行:
  /// 1. 関連するコメントを削除
  /// 2. 関連するリアクションを削除
  /// 3. 投稿自体を削除
  /// 4. ユーザーのtotalPostsを更新
  /// 5. サークルのpostCountを更新（サークル投稿の場合）
  /// 6. Storageからメディアを削除
  Future<bool> deletePost({
    required BuildContext context,
    required PostModel post,
    VoidCallback? onDeleted,
  }) async {
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

    if (confirmed != true) return false;

    try {
      // バッチ処理で一括削除（整合性担保とルール回避のため）
      final batch = _firestore.batch();

      // 1. 関連するコメントを削除対象に追加
      // Note: 投稿を先に消すと、コメント削除のセキュリティルール(get(post))が失敗するため
      // バッチにするか、コメント→投稿の順で消す必要がある。バッチが確実。
      final comments = await _firestore
          .collection('comments')
          .where('postId', isEqualTo: post.id)
          .get();

      for (final doc in comments.docs) {
        batch.delete(doc.reference);
      }

      // 2. 関連するリアクションも削除対象に追加
      final reactions = await _firestore
          .collection('reactions')
          .where('postId', isEqualTo: post.id)
          .get();

      for (final doc in reactions.docs) {
        batch.delete(doc.reference);
      }

      // 3. 投稿自体を削除対象に追加
      batch.delete(_firestore.collection('posts').doc(post.id));

      // 4. ユーザーの投稿数を減少
      batch.update(_firestore.collection('users').doc(post.userId), {
        'totalPosts': FieldValue.increment(-1),
      });

      // 5. サークル投稿の場合、postCountをデクリメント
      if (post.circleId != null && post.circleId!.isNotEmpty) {
        batch.update(_firestore.collection('circles').doc(post.circleId), {
          'postCount': FieldValue.increment(-1),
        });
      }

      // コミット
      debugPrint('PostService: Deleting post: ${post.id}');
      await batch.commit();
      debugPrint('PostService: Post deleted successfully');

      // 6. Storageからメディアを削除（バッチ外で実行）
      if (post.allMedia.isNotEmpty) {
        final mediaService = MediaService();
        for (final media in post.allMedia) {
          debugPrint('PostService: Deleting media from Storage: ${media.url}');
          await mediaService.deleteMedia(media.url);

          // サムネイルも削除
          if (media.thumbnailUrl != null && media.thumbnailUrl!.isNotEmpty) {
            debugPrint(
              'PostService: Deleting thumbnail from Storage: ${media.thumbnailUrl}',
            );
            await mediaService.deleteMedia(media.thumbnailUrl!);
          }
        }
        debugPrint('PostService: Deleted ${post.allMedia.length} media files');
      }

      // 成功メッセージ
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('投稿を削除しました'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // コールバック実行
      onDeleted?.call();
      return true;
    } catch (e, stackTrace) {
      debugPrint('PostService: Delete failed: $e');
      debugPrint('PostService: Stack trace: $stackTrace');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('削除に失敗しました: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return false;
    }
  }
}
