import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/services/circle_service.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/models/circle_model.dart';

class MembersListScreen extends ConsumerWidget {
  final String circleId;
  final String circleName;
  final String ownerId;
  final String? subOwnerId; // 初期値（StreamBuilderで上書きされる）
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
    final circleService = ref.watch(circleServiceProvider);

    // サークルデータをリアルタイム監視（subOwnerIdの変更を検知）
    return StreamBuilder<CircleModel?>(
      stream: circleService.streamCircle(circleId),
      builder: (context, circleSnapshot) {
        // リアルタイムのsubOwnerIdを使用
        final currentSubOwnerId = circleSnapshot.data?.subOwnerId ?? subOwnerId;

        // メンバーをソート: オーナー → 副オーナー → その他
        final sortedMemberIds = List<String>.from(memberIds);
        sortedMemberIds.sort((a, b) {
          // オーナーは最上位
          if (a == ownerId) return -1;
          if (b == ownerId) return 1;
          // 副オーナーは2番目
          if (a == currentSubOwnerId) return -1;
          if (b == currentSubOwnerId) return 1;
          return 0;
        });

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
            itemCount: sortedMemberIds.length,
            itemBuilder: (context, index) {
              final memberId = sortedMemberIds[index];
              final isOwner = memberId == ownerId;
              final isSubOwner = memberId == currentSubOwnerId;

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(memberId)
                    .get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return _buildLoadingCard();
                  }

                  final userData =
                      snapshot.data!.data() as Map<String, dynamic>?;
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
                    hasExistingSubOwner: currentSubOwnerId != null,
                  );
                },
              );
            },
          ),
        );
      },
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
    required bool hasExistingSubOwner,
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
            // 任命ボタン（既に副オーナーがいる場合は表示しない）
            if (canAppoint && !hasExistingSubOwner)
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
      builder: (dialogContext) => AlertDialog(
        title: Text(AppMessages.circle.subOwnerAssignTitle),
        content: Text(AppMessages.circle.subOwnerAssignDescription(displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppMessages.label.cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                // オーナー情報を取得
                final ownerDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(ownerId)
                    .get();
                final ownerData = ownerDoc.data();
                final ownerName = ownerData?['displayName'] ?? 'オーナー';
                final ownerAvatarIndex = ownerData?['avatarIndex'] ?? 0;

                await ref
                    .read(circleServiceProvider)
                    .setSubOwner(
                      circleId,
                      memberId,
                      circleName: circleName,
                      ownerName: ownerName,
                      ownerAvatarIndex: ownerAvatarIndex,
                      ownerId: ownerId,
                    );
                if (context.mounted) {
                  SnackBarHelper.showSuccess(
                    context,
                    AppMessages.circle.subOwnerAssigned(displayName),
                  );
                  // Navigator.pop()は呼ばない - StreamBuilderで自動更新される
                }
              } catch (e) {
                debugPrint('MembersListScreen: assign sub-owner failed: $e');
                if (context.mounted) {
                  SnackBarHelper.showError(
                    context,
                    AppMessages.circle.subOwnerAssignFailed,
                  );
                }
              }
            },
            child: Text(AppMessages.circle.subOwnerAssignAction),
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
      builder: (dialogContext) => AlertDialog(
        title: Text(AppMessages.circle.subOwnerRemoveTitle),
        content: Text(AppMessages.circle.subOwnerRemoveConfirm(displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppMessages.label.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                // オーナー情報を取得
                final ownerDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(ownerId)
                    .get();
                final ownerData = ownerDoc.data();
                final ownerName = ownerData?['displayName'] ?? 'オーナー';
                final ownerAvatarIndex = ownerData?['avatarIndex'] ?? 0;

                await ref
                    .read(circleServiceProvider)
                    .removeSubOwner(
                      circleId,
                      subOwnerId: memberId,
                      circleName: circleName,
                      ownerName: ownerName,
                      ownerAvatarIndex: ownerAvatarIndex,
                      ownerId: ownerId,
                    );
                if (context.mounted) {
                  SnackBarHelper.showWarning(
                    context,
                    AppMessages.circle.subOwnerRemoved(displayName),
                  );
                  // Navigator.pop()は呼ばない - StreamBuilderで自動更新される
                }
              } catch (e) {
                debugPrint('MembersListScreen: remove sub-owner failed: $e');
                if (context.mounted) {
                  SnackBarHelper.showError(
                    context,
                    AppMessages.circle.subOwnerRemoveFailed,
                  );
                }
              }
            },
            child: Text(AppMessages.circle.subOwnerRemoveAction),
          ),
        ],
      ),
    );
  }
}
