import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_colors.dart';
import '../models/post_model.dart';
import 'ai_service.dart';

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
      // 投稿ドキュメントを削除（カスケード削除はCloud Functionsで処理）
      await _firestore.collection('posts').doc(post.id).delete();

      debugPrint('PostService: Deleting post: ${post.id}');
      debugPrint('PostService: Post deleted successfully');

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

  /// タスク完了時の自動投稿を作成（ストリーク節目・目標達成用）
  /// 戻り値: 作成された投稿のID（削除用に保存すること）
  Future<String?> createTaskCompletionPost({
    required String userId,
    required String userDisplayName,
    required int userAvatarIndex,
    required String taskContent,
    required int streak,
    bool isGoalCompletion = false,
    String? goalTitle,
  }) async {
    try {
      // 投稿内容を生成
      String content;
      if (isGoalCompletion && goalTitle != null) {
        content = '🎉 目標「$goalTitle」を達成しました！おめでとうございます！';
      } else {
        content = '🔥 「$taskContent」を$streak日連続達成しました！';
      }

      // Cloud Functions経由で投稿を作成（セキュリティルールでクライアント直接作成は禁止）
      final aiService = AIService();
      final postId = await aiService.createPostWithRateLimit(
        content: content,
        userDisplayName: userDisplayName,
        userAvatarIndex: userAvatarIndex,
        postMode: 'ai', // システムによる自動投稿
      );

      debugPrint(
        'PostService: Created auto-post $postId for ${isGoalCompletion ? "goal" : "streak $streak"}',
      );
      return postId;
    } catch (e) {
      debugPrint('PostService: Failed to create auto-post: $e');
      return null;
    }
  }

  /// 投稿をIDで削除（確認ダイアログなし、内部用）
  Future<bool> deletePostById(String postId, String userId) async {
    try {
      // 投稿ドキュメントを削除（カスケード削除はCloud Functionsで処理）
      await _firestore.collection('posts').doc(postId).delete();
      debugPrint('PostService: Deleted auto-post $postId');
      return true;
    } catch (e) {
      debugPrint('PostService: Failed to delete auto-post: $e');
      return false;
    }
  }
}
