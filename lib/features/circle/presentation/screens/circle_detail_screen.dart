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
  bool _hasPendingRequest = false;
  bool _hasCheckedPending = false;
  String? _lastCheckedUserId;

  Future<void> _checkPendingRequest(String userId) async {
    if (_hasCheckedPending && _lastCheckedUserId == userId) return;

    final circleService = ref.read(circleServiceProvider);
    final hasPending = await circleService.hasPendingRequest(
      widget.circleId,
      userId,
    );

    if (mounted) {
      setState(() {
        _hasPendingRequest = hasPending;
        _hasCheckedPending = true;
        _lastCheckedUserId = userId;
      });
    }
  }

  Future<void> _handleJoin(CircleModel circle, String userId) async {
    if (_isJoining) return;

    // ルールがある場合は同意ダイアログを表示
    if (circle.rules != null && circle.rules!.isNotEmpty) {
      final agreed = await _showRulesConsentDialog(circle.rules!);
      if (agreed != true) return;
    }

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
            setState(() => _hasPendingRequest = true);
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

  /// サークル削除ダイアログ
  Future<void> _showDeleteDialog(CircleModel circle) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[400], size: 28),
            const SizedBox(width: 8),
            const Text('サークルを削除'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '「${circle.name}」を削除しますか？',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '• 全ての投稿・コメントが削除されます\n'
                '• メンバーに通知が送信されます\n'
                '• この操作は取り消せません',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: '削除理由（任意）',
                  hintText: 'メンバーに伝えたいことがあれば',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.message_outlined),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('削除する'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _handleDeleteCircle(circle, reasonController.text.trim());
    reasonController.dispose();
  }

  /// サークル削除処理
  Future<void> _handleDeleteCircle(CircleModel circle, String? reason) async {
    try {
      final circleService = ref.read(circleServiceProvider);

      await circleService.deleteCircle(
        circleId: circle.id,
        reason: reason?.isEmpty == true ? null : reason,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('サークルを削除しました'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/circles'); // サークル一覧に戻る
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除に失敗しました: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// ルール同意ダイアログ（参加前）
  Future<bool?> _showRulesConsentDialog(String rules) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.description_outlined, color: Colors.grey[700]),
            const SizedBox(width: 8),
            const Text('サークルルール'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Text(
                  rules,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[800],
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '参加するにはルールに同意する必要があります',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00ACC1),
              foregroundColor: Colors.white,
            ),
            child: const Text('同意して参加'),
          ),
        ],
      ),
    );
  }

  /// ルール確認ダイアログ（メンバー用）
  void _showRulesDialog(String rules) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.description_outlined, color: Colors.grey[700]),
            const SizedBox(width: 8),
            const Text('サークルルール'),
          ],
        ),
        content: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Text(
              rules,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[800],
                height: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  /// ピン留め投稿一覧ボトムシート
  void _showPinnedPostsList(List<PostModel> pinnedPosts, bool isOwner) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ハンドル
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // タイトル
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.push_pin, color: Colors.amber[700]),
                  const SizedBox(width: 8),
                  const Text(
                    'ピン留め投稿',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // リスト
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: pinnedPosts.length,
                itemBuilder: (context, index) {
                  final post = pinnedPosts[index];
                  return ListTile(
                    leading: post.isPinnedTop
                        ? Icon(Icons.star, color: Colors.amber[700])
                        : Icon(
                            Icons.push_pin_outlined,
                            color: Colors.grey[400],
                          ),
                    title: Text(
                      post.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      post.isPinnedTop ? 'トップ表示' : '',
                      style: TextStyle(color: Colors.amber[700], fontSize: 12),
                    ),
                    trailing: isOwner
                        ? PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) async {
                              final circleService = ref.read(
                                circleServiceProvider,
                              );
                              Navigator.pop(context);
                              if (value == 'top') {
                                await circleService.setTopPinnedPost(
                                  post.circleId!,
                                  post.id,
                                );
                              } else if (value == 'unpin') {
                                await circleService.togglePinPost(
                                  post.id,
                                  false,
                                );
                              }
                            },
                            itemBuilder: (context) => [
                              if (!post.isPinnedTop)
                                const PopupMenuItem(
                                  value: 'top',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.star,
                                        color: Colors.amber,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text('トップに表示'),
                                    ],
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'unpin',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.push_pin_outlined,
                                      color: Colors.grey,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text('ピン留め解除'),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/post/${post.id}');
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final circleService = ref.watch(circleServiceProvider);

    return StreamBuilder<CircleModel?>(
      stream: circleService.streamCircle(widget.circleId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          // サークルが削除された場合、一覧画面に戻る
          if (snapshot.connectionState == ConnectionState.active &&
              snapshot.data == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('このサークルは削除されました'),
                    backgroundColor: Colors.orange,
                  ),
                );
                context.go('/circles');
              }
            });
          }
          return Scaffold(
            backgroundColor: Colors.grey[50],
            body: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        final circle = snapshot.data!;
        // CircleServiceのカテゴリアイコンを使用
        final icon = CircleService.categoryIcons[circle.category] ?? '⭐';
        final isMember =
            currentUser != null &&
            circleService.isMember(circle, currentUser.uid);
        final isOwner =
            currentUser != null &&
            circleService.isOwner(circle, currentUser.uid);

        // 非公開サークルで非メンバーの場合、申請中かチェック
        if (!circle.isPublic && !isMember && currentUser != null) {
          _checkPendingRequest(currentUser.uid);
        }

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
                // オーナー用メニュー
                actions: isOwner
                    ? [
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: PopupMenuButton<String>(
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
                              child: const Icon(Icons.more_vert, size: 20),
                            ),
                            onSelected: (value) {
                              if (value == 'delete') {
                                _showDeleteDialog(circle);
                              } else if (value == 'requests') {
                                context.push(
                                  '/circle/${circle.id}/requests',
                                  extra: {'circleName': circle.name},
                                );
                              } else if (value == 'edit') {
                                context.push(
                                  '/circle/${circle.id}/edit',
                                  extra: circle,
                                );
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.edit_outlined,
                                      color: Color(0xFF00ACC1),
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text('編集'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'requests',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.person_add_outlined,
                                      color: Color(0xFF00ACC1),
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text('参加申請'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'サークルを削除',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]
                    : null,
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
                                      GestureDetector(
                                        onTap: () {
                                          context.push(
                                            '/circle/${circle.id}/members',
                                            extra: {
                                              'circleName': circle.name,
                                              'ownerId': circle.ownerId,
                                              'memberIds': circle.memberIds,
                                            },
                                          );
                                        },
                                        child: _buildTag(
                                          Icons.people_outline,
                                          '${circle.memberIds.length}人',
                                          showArrow: true,
                                        ),
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
                      // ルール確認ボタン（メンバーでルールがある場合のみ）
                      if (isMember &&
                          circle.rules != null &&
                          circle.rules!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: OutlinedButton.icon(
                            onPressed: () => _showRulesDialog(circle.rules!),
                            icon: Icon(
                              Icons.description_outlined,
                              color: Colors.grey[700],
                              size: 18,
                            ),
                            label: Text(
                              'サークルルール',
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 44),
                              side: BorderSide(color: Colors.grey[300]!),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
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
                            // 申請中の場合
                            : _hasPendingRequest && !circle.isPublic
                            ? OutlinedButton(
                                onPressed: null, // 非活性
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
                                      Icons.hourglass_empty,
                                      color: Colors.grey[500],
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '申請中',
                                      style: TextStyle(color: Colors.grey[600]),
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
              // ピン留め投稿セクション（オーナーのみ管理可能）
              if (isMember)
                StreamBuilder<List<PostModel>>(
                  stream: circleService.streamPinnedPosts(circle.id),
                  builder: (context, pinnedSnapshot) {
                    final pinnedPosts = pinnedSnapshot.data ?? [];
                    if (pinnedPosts.isEmpty)
                      return const SliverToBoxAdapter(child: SizedBox.shrink());

                    // トップピン投稿を取得
                    final topPinned = pinnedPosts.firstWhere(
                      (p) => p.isPinnedTop,
                      orElse: () => pinnedPosts.first,
                    );

                    return SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.amber.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.push_pin,
                                  size: 16,
                                  color: Colors.amber[700],
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'ピン留め',
                                  style: TextStyle(
                                    color: Colors.amber[700],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const Spacer(),
                                if (pinnedPosts.length > 1)
                                  GestureDetector(
                                    onTap: () => _showPinnedPostsList(
                                      pinnedPosts,
                                      isOwner,
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          '${pinnedPosts.length}件',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                        Icon(
                                          Icons.chevron_right,
                                          size: 16,
                                          color: Colors.grey[600],
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () =>
                                  context.push('/post/${topPinned.id}'),
                              child: Text(
                                topPinned.content,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey[800],
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
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
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final post = posts[index];
                      return PostCard(
                        key: ValueKey(post.id),
                        post: post,
                        isCircleOwner: isOwner,
                        onPinToggle: isOwner
                            ? (isPinned) async {
                                await circleService.togglePinPost(
                                  post.id,
                                  isPinned,
                                );
                              }
                            : null,
                      );
                    }, childCount: posts.length),
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

  Widget _buildTag(IconData icon, String text, {bool showArrow = false}) {
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
          if (showArrow) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 14, color: Colors.grey[500]),
          ],
        ],
      ),
    );
  }
}
