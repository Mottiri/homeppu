import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/services/media_service.dart';
import '../../../../shared/models/post_model.dart';

/// 管理者用：要審査投稿一覧画面
class AdminReviewScreen extends ConsumerStatefulWidget {
  const AdminReviewScreen({super.key});

  @override
  ConsumerState<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends ConsumerState<AdminReviewScreen> {
  final _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('要審査投稿'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('pendingReviews')
              .where('reviewed', isEqualTo: false)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('エラーが発生しました: ${snapshot.error}'));
            }

            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: AppColors.success,
                    ),
                    SizedBox(height: 16),
                    Text(
                      '審査待ちの投稿はありません',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final reviewDoc = docs[index];
                final data = reviewDoc.data() as Map<String, dynamic>;
                final postId = data['postId'] as String;
                final reason = data['reason'] as String? ?? '';

                return FutureBuilder<DocumentSnapshot>(
                  future: _firestore.collection('posts').doc(postId).get(),
                  builder: (context, postSnapshot) {
                    if (!postSnapshot.hasData || !postSnapshot.data!.exists) {
                      return const SizedBox.shrink();
                    }

                    final post = PostModel.fromFirestore(postSnapshot.data!);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 理由バナー
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withOpacity(0.2),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.flag,
                                  color: AppColors.warning,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    reason,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 投稿内容
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  post.content,
                                  style: const TextStyle(fontSize: 16),
                                  maxLines: 5,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (post.allMedia.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    'メディア: ${post.allMedia.length}件',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // アクションボタン
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _approvePost(postId, reviewDoc.id),
                                    icon: const Icon(Icons.check),
                                    label: const Text('承認'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.success,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _deletePost(post, reviewDoc.id),
                                    icon: const Icon(Icons.delete),
                                    label: const Text('削除'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.error,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// 投稿を承認
  Future<void> _approvePost(String postId, String reviewId) async {
    try {
      // 投稿のneedsReviewをfalseに更新
      await _firestore.collection('posts').doc(postId).update({
        'needsReview': false,
      });

      // pendingReviewsをreviewedに更新
      await _firestore.collection('pendingReviews').doc(reviewId).update({
        'reviewed': true,
        'reviewedAt': FieldValue.serverTimestamp(),
        'action': 'approved',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('投稿を承認しました'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('承認に失敗しました: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// 投稿を削除
  Future<void> _deletePost(PostModel post, String reviewId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('投稿を削除'),
        content: const Text('この投稿を削除しますか？この操作は取り消せません。'),
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

    if (confirmed != true) return;

    try {
      // Storageからメディアを削除
      if (post.allMedia.isNotEmpty) {
        final mediaService = MediaService();
        for (final media in post.allMedia) {
          await mediaService.deleteMedia(media.url);
        }
      }

      // 投稿を削除
      await _firestore.collection('posts').doc(post.id).delete();

      // pendingReviewsを更新
      await _firestore.collection('pendingReviews').doc(reviewId).update({
        'reviewed': true,
        'reviewedAt': FieldValue.serverTimestamp(),
        'action': 'deleted',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('投稿を削除しました'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('削除に失敗しました: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
