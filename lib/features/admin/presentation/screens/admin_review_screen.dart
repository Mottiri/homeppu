import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/dialog_helper.dart';
import '../../../../core/utils/snackbar_helper.dart';
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
              return Center(
                child: Text(
                  AppMessages.error.withDetail(snapshot.error.toString()),
                ),
              );
            }

            final docs = snapshot.data?.docs ?? [];

            if (docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: AppColors.success,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppMessages.empty.adminReviewEmpty,
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
                              color: AppColors.warning.withValues(alpha: 0.2),
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
                          // 投稿詳細遷移ボタン
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => context.pushNamed(
                                  'postDetail',
                                  pathParameters: {'postId': post.id},
                                ),
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('投稿詳細を見る'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
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
        SnackBarHelper.showSuccess(context, AppMessages.admin.postApproved);
      }
    } catch (e) {
      debugPrint('AdminReviewScreen: approve failed: $e');
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.admin.approveFailed);
      }
    }
  }

  /// 投稿を削除
  Future<void> _deletePost(PostModel post, String reviewId) async {
    final confirmed = await DialogHelper.showConfirmDialog(
      context: context,
      title: AppMessages.admin.deletePostTitle,
      message: AppMessages.admin.deletePostMessage,
      confirmText: AppMessages.label.delete,
      cancelText: AppMessages.label.cancel,
      isDangerous: true,
      barrierDismissible: false,
    );

    if (!confirmed) return;

    try {
      // Storageからメディアを削除
      if (post.allMedia.isNotEmpty) {
        final mediaService = MediaService();
        for (final media in post.allMedia) {
          await mediaService.deleteMedia(media.url);

          // サムネイルも削除
          if (media.thumbnailUrl != null && media.thumbnailUrl!.isNotEmpty) {
            await mediaService.deleteMedia(media.thumbnailUrl!);
          }
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
        SnackBarHelper.showSuccess(context, AppMessages.admin.postDeleted);
      }
    } catch (e) {
      debugPrint('AdminReviewScreen: delete failed: $e');
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.admin.deleteFailed);
      }
    }
  }
}
