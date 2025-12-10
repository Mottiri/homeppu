import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/providers/auth_provider.dart';

/// リアクションボタン
class ReactionButton extends ConsumerStatefulWidget {
  final ReactionType type;
  final int count;
  final String postId;

  const ReactionButton({
    super.key,
    required this.type,
    required this.count,
    required this.postId,
  });

  @override
  ConsumerState<ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends ConsumerState<ReactionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isReacted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    // アニメーション
    _controller.forward().then((_) => _controller.reverse());

    setState(() => _isReacted = !_isReacted);

    // Firestoreに反映
    try {
      final postRef = FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId);

      await postRef.update({
        'reactions.${widget.type.value}': FieldValue.increment(
          _isReacted ? 1 : -1,
        ),
      });

      // リアクション追加時のみ、通知トリガー用にサブコレクションに書き込む
      if (_isReacted) {
        await FirebaseFirestore.instance.collection('reactions').add({
          'postId': widget.postId,
          'userId': user.uid,
          'userDisplayName': user.displayName,
          'reactionType': widget.type.value,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      // エラー時は状態を戻す
      setState(() => _isReacted = !_isReacted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.type.colorValue);

    return GestureDetector(
      onTap: _onTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _isReacted ? _scaleAnimation.value : 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _isReacted
                    ? color.withOpacity(0.2)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isReacted
                      ? color.withOpacity(0.5)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.type.emoji, style: const TextStyle(fontSize: 18)),
                  /* カウントは表示しない（背景に表示するため）
                  if (widget.count > 0 || _isReacted) ...[
                    const SizedBox(width: 4),
                    Text(
                      '${widget.count + (_isReacted ? 1 : 0)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isReacted ? color : AppColors.textSecondary,
                      ),
                    ),
                  ],
                  */
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
