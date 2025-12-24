import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/services/circle_service.dart';
import '../../../../shared/widgets/avatar_selector.dart';

class JoinRequestsScreen extends ConsumerWidget {
  final String circleId;
  final String circleName;

  const JoinRequestsScreen({
    super.key,
    required this.circleId,
    required this.circleName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circleService = ref.watch(circleServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('参加申請'),
        backgroundColor: const Color(0xFF00ACC1),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: circleService.streamJoinRequests(circleId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00ACC1)),
            );
          }

          final requests = snapshot.data ?? [];

          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00ACC1).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.inbox_outlined,
                      size: 64,
                      color: Color(0xFF00ACC1),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '参加申請はありません',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              return _JoinRequestCard(
                request: request,
                circleId: circleId,
                circleName: circleName,
                circleService: circleService,
              );
            },
          );
        },
      ),
    );
  }
}

class _JoinRequestCard extends StatefulWidget {
  final Map<String, dynamic> request;
  final String circleId;
  final String circleName;
  final CircleService circleService;

  const _JoinRequestCard({
    required this.request,
    required this.circleId,
    required this.circleName,
    required this.circleService,
  });

  @override
  State<_JoinRequestCard> createState() => _JoinRequestCardState();
}

class _JoinRequestCardState extends State<_JoinRequestCard> {
  bool _isLoading = false;
  Map<String, dynamic>? _userInfo;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final userId = widget.request['userId'] as String?;
    if (userId == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _userInfo = doc.data();
        });
      }
    } catch (e) {
      debugPrint('Failed to load user info: $e');
    }
  }

  void _navigateToProfile(BuildContext context) {
    final userId = widget.request['userId'] as String?;
    if (userId != null) {
      context.push('/profile/$userId');
    }
  }

  Future<void> _handleApprove() async {
    setState(() => _isLoading = true);

    try {
      await widget.circleService.approveJoinRequest(
        widget.request['id'],
        widget.circleId,
        widget.circleName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('参加を承認しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラーが発生しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleReject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('申請を拒否'),
        content: Text('${_userInfo?['displayName'] ?? ''}さんの申請を拒否しますか？'),
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
            child: const Text('拒否'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await widget.circleService.rejectJoinRequest(
        widget.request['id'],
        widget.circleId,
        widget.circleName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('申請を拒否しました'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラーが発生しました: $e'),
            backgroundColor: Colors.red,
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
    final createdAt = widget.request['createdAt'] as Timestamp?;
    final dateStr = createdAt != null ? _formatDate(createdAt.toDate()) : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // アバター（タップでプロフィールへ）
            GestureDetector(
              onTap: () => _navigateToProfile(context),
              child: AvatarWidget(
                avatarIndex: _userInfo?['avatarIndex'] ?? 0,
                size: 48,
              ),
            ),
            const SizedBox(width: 12),
            // ユーザー情報（タップでプロフィールへ）
            Expanded(
              child: GestureDetector(
                onTap: () => _navigateToProfile(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userInfo?['displayName'] ?? '読み込み中...',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            // ボタン
            if (_isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拒否ボタン
                  IconButton(
                    onPressed: _handleReject,
                    icon: const Icon(Icons.close, color: Colors.red),
                    tooltip: '拒否',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 承認ボタン
                  IconButton(
                    onPressed: _handleApprove,
                    icon: const Icon(Icons.check, color: Colors.green),
                    tooltip: '承認',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}時間前';
    } else {
      return '${diff.inDays}日前';
    }
  }
}
