import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_messages.dart';
import '../../core/utils/dialog_helper.dart';
import '../../core/utils/snackbar_helper.dart';
import '../models/post_model.dart';

/// Shared post operations.
class PostService {
  static final PostService _instance = PostService._internal();
  factory PostService() => _instance;
  PostService._internal();

  final _firestore = FirebaseFirestore.instance;

  Future<bool> deletePost({
    required BuildContext context,
    required PostModel post,
    VoidCallback? onDeleted,
  }) async {
    final confirmed = await DialogHelper.showConfirmDialog(
      context: context,
      title: AppMessages.label.confirm,
      message: AppMessages.confirm.deletePost(),
      confirmText: AppMessages.label.delete,
      cancelText: AppMessages.label.cancel,
      isDangerous: true,
      barrierDismissible: false,
    );

    if (!confirmed) return false;

    try {
      await _firestore.collection('posts').doc(post.id).delete();

      if (context.mounted) {
        SnackBarHelper.showSuccess(context, AppMessages.success.postDeleted);
      }

      onDeleted?.call();
      return true;
    } catch (e, stackTrace) {
      debugPrint('PostService: Delete failed: $e');
      debugPrint('PostService: Stack trace: $stackTrace');

      if (context.mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
      }
      return false;
    }
  }

  Future<bool> deletePostById(String postId, String userId) async {
    try {
      await _firestore.collection('posts').doc(postId).delete();
      debugPrint('PostService: Deleted auto-post $postId');
      return true;
    } catch (e) {
      debugPrint('PostService: Failed to delete auto-post: $e');
      return false;
    }
  }
}
