import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/widgets/avatar_selector.dart';

/// 投稿作成画面
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _contentController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _createPost() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;

    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final postId = const Uuid().v4();
      
      // 投稿を作成（Cloud Functionsトリガーが自動でAIコメントを生成）
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .set({
        'userId': user.uid,
        'userDisplayName': user.displayName,
        'userAvatarIndex': user.avatarIndex,
        'content': content,
        'postMode': user.postMode,
        'createdAt': Timestamp.now(),
        'reactions': {
          'love': 0,
          'praise': 0,
          'cheer': 0,
          'empathy': 0,
        },
        'commentCount': 0,
        'isVisible': true,
      });

      // ユーザーの投稿数を更新
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'totalPosts': FieldValue.increment(1),
      });

      if (mounted) {
        // 成功メッセージ
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppConstants.friendlyMessages['post_success']!),
            backgroundColor: AppColors.success,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppConstants.friendlyMessages['error_general']!),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final remainingChars = AppConstants.maxPostLength - _contentController.text.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('新しい投稿'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.close_rounded),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton(
              onPressed: _contentController.text.trim().isEmpty || _isLoading
                  ? null
                  : _createPost,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('投稿する'),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.warmGradient,
        ),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ユーザー情報
                    if (user != null)
                      Row(
                        children: [
                          AvatarWidget(
                            avatarIndex: user.avatarIndex,
                            size: 48,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            user.displayName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    
                    const SizedBox(height: 20),
                    
                    // 投稿入力
                    TextField(
                      controller: _contentController,
                      maxLines: null,
                      minLines: 6,
                      maxLength: AppConstants.maxPostLength,
                      decoration: const InputDecoration(
                        hintText: '今日あったこと、がんばったこと、\n何でも投稿してみよう✨',
                        border: InputBorder.none,
                        fillColor: Colors.transparent,
                        counterText: '',
                      ),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.6,
                      ),
                      onChanged: (value) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ),
            
            // ボトムバー
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    // 画像追加ボタン
                    IconButton(
                      onPressed: () {
                        // TODO: 画像選択
                      },
                      icon: const Icon(Icons.image_outlined),
                      color: AppColors.textSecondary,
                    ),
                    const Spacer(),
                    // 文字数
                    Text(
                      '$remainingChars',
                      style: TextStyle(
                        color: remainingChars < 50
                            ? AppColors.warning
                            : AppColors.textHint,
                        fontWeight: remainingChars < 50
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
