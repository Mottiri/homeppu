import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/models/circle_model.dart';
import '../../../../shared/models/post_model.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/circle_service.dart';
import '../../../home/presentation/widgets/post_card.dart';

/// サークル詳細画面
class CircleDetailScreen extends ConsumerStatefulWidget {
  final String circleId;

  const CircleDetailScreen({super.key, required this.circleId});

  @override
  ConsumerState<CircleDetailScreen> createState() => _CircleDetailScreenState();
}

class _CircleDetailScreenState extends ConsumerState<CircleDetailScreen> {
  bool _isJoining = false;

  static const Map<String, String> categoryIcons = {
    '勉強': '📚',
    'ダイエット': '🥗',
    '運動': '💪',
    '趣味': '🎨',
    '仕事': '💼',
    '資格': '📝',
    '読書': '📖',
    '語学': '🌍',
    'プログラミング': '💻',
    '音楽': '🎵',
    'その他': '⭐',
  };

  Future<void> _handleJoin(CircleModel circle, String userId) async {
    if (_isJoining) return;
    setState(() => _isJoining = true);

    try {
      final circleService = ref.read(circleServiceProvider);

      if (circle.isPublic) {
        // 公開サークル: 即参加
        await circleService.joinCircle(widget.circleId, userId);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('サークルに参加しました！🎉')));
        }
      } else {
        // 招待制サークル: 参加申請
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('参加申請'),
            content: const Text('このサークルは招待制です。\n管理者に参加申請を送信しますか？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('キャンセル'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('申請する'),
              ),
            ],
          ),
        );

        if (confirm == true) {
          await circleService.sendJoinRequest(widget.circleId, userId);
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('参加申請を送信しました')));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('エラーが発生しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _handleLeave(String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('サークルを退会'),
        content: const Text('本当にこのサークルを退会しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('退会する'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final circleService = ref.read(circleServiceProvider);
        await circleService.leaveCircle(widget.circleId, userId);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('サークルを退会しました')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('エラーが発生しました: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final circleService = ref.watch(circleServiceProvider);

    return StreamBuilder<CircleModel?>(
      stream: circleService.streamCircle(widget.circleId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return Scaffold(
            backgroundColor: Colors.grey[50],
            body: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        final circle = snapshot.data!;
        final icon = categoryIcons[circle.category] ?? '⭐';
        final isMember =
            currentUser != null &&
            circleService.isMember(circle, currentUser.uid);
        final isOwner =
            currentUser != null &&
            circleService.isOwner(circle, currentUser.uid);

        return Scaffold(
          backgroundColor: Colors.grey[50],
          floatingActionButton: isMember
              ? FloatingActionButton(
                  onPressed: () => context.push(
                    '/create-post',
                    extra: {'circleId': widget.circleId},
                  ),
                  backgroundColor: const Color(0xFF00ACC1), // シアン
                  child: const Icon(Icons.edit, color: Colors.white),
                )
              : null,
          body: CustomScrollView(
            slivers: [
              // ヘッダー
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                backgroundColor: Colors.white,
                leading: IconButton(
                  onPressed: () => context.pop(),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.arrow_back_rounded, size: 20),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // カバー画像またはグラデーション
                      circle.coverImageUrl != null
                          ? Image.network(
                              circle.coverImageUrl!,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.primary.withOpacity(0.7),
                                    AppColors.primaryLight,
                                  ],
                                ),
                              ),
                            ),
                      // オーバーレイ
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.3),
                            ],
                          ),
                        ),
                      ),
                      // サークル情報
                      Positioned(
                        bottom: 20,
                        left: 20,
                        right: 20,
                        child: Row(
                          children: [
                            // アイコン
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: circle.iconImageUrl != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: Image.network(
                                        circle.iconImageUrl!,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : Center(
                                      child: Text(
                                        icon,
                                        style: const TextStyle(fontSize: 36),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 16),
                            // 名前と情報
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    circle.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black26,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      _buildTag(
                                        Icons.people_outline,
                                        '${circle.memberCount}人',
                                      ),
                                      const SizedBox(width: 8),
                                      _buildTag(
                                        Icons.category_outlined,
                                        circle.category,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 参加ボタンと説明
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 説明
                      Text(
                        circle.description,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: Colors.grey[700],
                        ),
                      ),
                      if (circle.goal.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Text('🎯', style: TextStyle(fontSize: 20)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  circle.goal,
                                  style: TextStyle(
                                    color: Colors.grey[800],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // 参加ボタン
                      SizedBox(
                        width: double.infinity,
                        height: 52, // 高さを増やしてテキストの切れを防止
                        child: currentUser == null
                            ? ElevatedButton(
                                onPressed: () => context.push('/login'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('ログインして参加'),
                              )
                            : isMember
                            ? OutlinedButton(
                                onPressed: isOwner
                                    ? null
                                    : () => _handleLeave(currentUser.uid),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.grey[300]!),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      isOwner ? Icons.star : Icons.check,
                                      color: isOwner
                                          ? Colors.amber
                                          : Colors.grey[600],
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isOwner ? 'オーナー' : '参加中',
                                      style: TextStyle(
                                        color: isOwner
                                            ? Colors.amber[700]
                                            : Colors.grey[600],
                                        fontWeight: isOwner
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ElevatedButton(
                                onPressed: _isJoining
                                    ? null
                                    : () =>
                                          _handleJoin(circle, currentUser.uid),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isJoining
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.person_add,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            circle.isPublic ? '参加する' : '参加申請',
                                          ),
                                        ],
                                      ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),

              // 投稿ヘッダー
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      const Text('📝', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Text(
                        'みんなの投稿',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

              // サークル内の投稿
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('posts')
                    .where('circleId', isEqualTo: widget.circleId)
                    .where('isVisible', isEqualTo: true)
                    .orderBy('createdAt', descending: true)
                    .limit(AppConstants.postsPerPage)
                    .snapshots(),
                builder: (context, postSnapshot) {
                  if (!postSnapshot.hasData) {
                    return const SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    );
                  }

                  final posts = postSnapshot.data!.docs
                      .map((doc) => PostModel.fromFirestore(doc))
                      .toList();

                  if (posts.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(40),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight.withOpacity(0.3),
                                shape: BoxShape.circle,
                              ),
                              child: const Text(
                                '✨',
                                style: TextStyle(fontSize: 40),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'まだ投稿がないよ',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '最初の投稿をしてみよう！',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => PostCard(
                        key: ValueKey(posts[index].id),
                        post: posts[index],
                      ),
                      childCount: posts.length,
                    ),
                  );
                },
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTag(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[700]),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
