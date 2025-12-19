import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/recent_reactions_service.dart';

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
      duration: const Duration(milliseconds: 500), // 500msでしっかり見せる
      vsync: this,
    );
    // 大きく登場して戻るアニメーション
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 2.5,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40, // 最初の40%で大きくなる
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 2.5,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60, // 残り60%で戻る
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    // リアクション追加時のみアニメーション
    if (!_isReacted) {
      _controller.reset();
      _controller.forward(); // 1.0→2.5→1.0のアニメーション
    }

    setState(() => _isReacted = !_isReacted);

    try {
      if (_isReacted) {
        // リアクション追加: Cloud Functions経由（回数制限あり）
        final functions = FirebaseFunctions.instanceFor(
          region: 'asia-northeast1',
        );
        final callable = functions.httpsCallable('addUserReaction');

        await callable.call({
          'postId': widget.postId,
          'reactionType': widget.type.value,
        });

        // 直近使用リストに追加
        await RecentReactionsService.addReaction(widget.type.value);
      } else {
        // リアクション削除: 直接Firestoreを更新（カウントのみ）
        final postRef = FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.postId);

        await postRef.update({
          'reactions.${widget.type.value}': FieldValue.increment(-1),
        });
      }
    } on FirebaseFunctionsException catch (e) {
      // エラー時は状態を戻す
      setState(() => _isReacted = !_isReacted);

      // 回数制限エラーの場合はSnackBarで通知
      if (e.code == 'resource-exhausted' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'リアクション回数の上限に達しました'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      // その他のエラー時
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
