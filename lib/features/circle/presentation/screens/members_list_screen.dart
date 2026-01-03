import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/services/circle_service.dart';
import '../../../../shared/providers/auth_provider.dart';

class MembersListScreen extends ConsumerWidget {
  final String circleId;
  final String circleName;
  final String ownerId;
  final String? subOwnerId;
  final List<String> memberIds;

  const MembersListScreen({
    super.key,
    required this.circleId,
    required this.circleName,
    required this.ownerId,
    this.subOwnerId,
    required this.memberIds,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(authStateProvider).value?.uid;
    final isCurrentUserOwner = currentUserId == ownerId;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('メンバー一覧'),
            Text(
              '$circleName (${memberIds.length}人)',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: memberIds.length,
        itemBuilder: (context, index) {
          final memberId = memberIds[index];
          final isOwner = memberId == ownerId;
          final isSubOwner = memberId == subOwnerId;

          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(memberId)
                .get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return _buildLoadingCard();
              }

              final userData = snapshot.data!.data() as Map<String, dynamic>?;
              if (userData == null) return const SizedBox.shrink();

              final displayName = userData['displayName'] ?? 'ユーザー';
              final avatarIndex = userData['avatarIndex'] ?? 0;

              return _buildMemberCard(
                context,
                ref,
                memberId: memberId,
                displayName: displayName,
                avatarIndex: avatarIndex,
                isOwner: isOwner,
                isSubOwner: isSubOwner,
                canAppoint: isCurrentUserOwner && !isOwner && !isSubOwner,
                canRemoveSubOwner: isCurrentUserOwner && isSubOwner,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 100,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(
    BuildContext context,
    WidgetRef ref, {
    required String memberId,
    required String displayName,
    required int avatarIndex,
    required bool isOwner,
    required bool isSubOwner,
    required bool canAppoint,
    required bool canRemoveSubOwner,
  }) {
    return GestureDetector(
      onTap: () => context.push('/profile/$memberId'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            AvatarWidget(avatarIndex: avatarIndex, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isOwner)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.workspace_premium,
                                size: 12,
                                color: Colors.amber[700],
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'オーナー',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.amber[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (isSubOwner)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star,
                                size: 12,
                                color: Colors.blue[700],
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '副オーナー',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Flexible(
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (canAppoint)
              IconButton(
                icon: Icon(Icons.star_outline, color: Colors.blue[600]),
                tooltip: '副オーナーに任命',
                onPressed: () =>
                    _showAppointDialog(context, ref, memberId, displayName),
              )
            else if (canRemoveSubOwner)
              IconButton(
                icon: Icon(
                  Icons.remove_circle_outline,
                  color: Colors.grey[600],
                ),
                tooltip: '副オーナーを解任',
                onPressed: () =>
                    _showRemoveDialog(context, ref, memberId, displayName),
              )
            else
              Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _showAppointDialog(
    BuildContext context,
    WidgetRef ref,
    String memberId,
    String displayName,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('副オーナーに任命'),
        content: Text(
          '$displayName さんを副オーナーに任命しますか？\n\n副オーナーはピン留めや参加承認などの権限を持ちます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref
                    .read(circleServiceProvider)
                    .setSubOwner(circleId, memberId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$displayName さんを副オーナーに任命しました')),
                  );
                  Navigator.pop(context); // メンバー一覧を閉じて更新を反映
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('任命に失敗しました')));
                }
              }
            },
            child: const Text('任命する'),
          ),
        ],
      ),
    );
  }

  void _showRemoveDialog(
    BuildContext context,
    WidgetRef ref,
    String memberId,
    String displayName,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('副オーナーを解任'),
        content: Text('$displayName さんの副オーナー権限を解除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(circleServiceProvider).removeSubOwner(circleId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$displayName さんの副オーナー権限を解除しました')),
                  );
                  Navigator.pop(context); // メンバー一覧を閉じて更新を反映
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('解任に失敗しました')));
                }
              }
            },
            child: const Text('解任する'),
          ),
        ],
      ),
    );
  }
}
