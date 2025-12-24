import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/avatar_selector.dart';

class MembersListScreen extends ConsumerWidget {
  final String circleId;
  final String circleName;
  final String ownerId;
  final List<String> memberIds;

  const MembersListScreen({
    super.key,
    required this.circleId,
    required this.circleName,
    required this.ownerId,
    required this.memberIds,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                memberId: memberId,
                displayName: displayName,
                avatarIndex: avatarIndex,
                isOwner: isOwner,
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
    BuildContext context, {
    required String memberId,
    required String displayName,
    required int avatarIndex,
    required bool isOwner,
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
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
