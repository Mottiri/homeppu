import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/widgets/avatar_selector.dart';
import '../../../../shared/models/avatar_parts_model.dart';
import '../../../../shared/services/circle_service.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/models/circle_model.dart';

class MembersListScreen extends ConsumerStatefulWidget {
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
  ConsumerState<MembersListScreen> createState() => _MembersListScreenState();
}

class _MembersListScreenState extends ConsumerState<MembersListScreen> {
  Map<String, Map<String, dynamic>> _memberData = {};
  bool _isLoadingMembers = true;

  @override
  void initState() {
    super.initState();
    _fetchMembers();
  }

  Future<void> _fetchMembers() async {
    final result = <String, Map<String, dynamic>>{};
    try {
      for (var i = 0; i < widget.memberIds.length; i += 30) {
        final batch = widget.memberIds.sublist(
          i,
          min(i + 30, widget.memberIds.length),
        );
        final snapshot = await FirebaseFirestore.instance
            .collection('publicUsers')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (final doc in snapshot.docs) {
          result[doc.id] = doc.data();
        }
      }
    } catch (e) {
      debugPrint('MembersListScreen: batch fetch failed: $e');
    }
    if (mounted) {
      setState(() {
        _memberData = result;
        _isLoadingMembers = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authStateProvider).value?.uid;
    final isCurrentUserOwner = currentUserId == widget.ownerId;
    final circleService = ref.watch(circleServiceProvider);

    return StreamBuilder<CircleModel?>(
      stream: circleService.streamCircle(widget.circleId),
      builder: (context, circleSnapshot) {
        final currentSubOwnerId = circleSnapshot.data?.subOwnerId ?? widget.subOwnerId;

        final sortedMemberIds = List<String>.from(widget.memberIds);
        sortedMemberIds.sort((a, b) {
          if (a == widget.ownerId) return -1;
          if (b == widget.ownerId) return 1;
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
                  '${widget.circleName} (${widget.memberIds.length}人)',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
          ),
          body: _isLoadingMembers
              ? ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sortedMemberIds.length,
                  itemBuilder: (_, _) => _buildLoadingCard(),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sortedMemberIds.length,
                  itemBuilder: (context, index) {
                    final memberId = sortedMemberIds[index];
                    final isOwner = memberId == widget.ownerId;
                    final isSubOwner = memberId == currentSubOwnerId;

                    final userData = _memberData[memberId];
                    if (userData == null) return const SizedBox.shrink();

                    final currentUser =
                        ref.watch(currentUserProvider).valueOrNull;
                    final isSelf = currentUser?.uid == memberId;
                    final displayName = isSelf
                        ? (currentUser?.displayName ?? userData['displayName'])
                        : (userData['displayName'] ?? 'User');
                    final avatarIndex = isSelf
                        ? (currentUser?.avatarIndex ?? userData['avatarIndex'] ?? 0)
                        : (userData['avatarIndex'] ?? 0);
                    final avatarParts = isSelf
                        ? currentUser?.avatarParts
                        : AvatarParts.fromMap(userData['avatarParts']);

                    return _buildMemberCard(
                      context,
                      ref,
                      memberId: memberId,
                      displayName: displayName,
                      avatarIndex: avatarIndex,
                      avatarParts: avatarParts,
                      isOwner: isOwner,
                      isSubOwner: isSubOwner,
                      canAppoint: isCurrentUserOwner && !isOwner && !isSubOwner,
                      canRemoveSubOwner: isCurrentUserOwner && isSubOwner,
                      hasExistingSubOwner: currentSubOwnerId != null,
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
    AvatarParts? avatarParts,
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
            AvatarWidget(
              avatarIndex: avatarIndex,
              avatarParts: avatarParts,
              borderRadius: BorderRadius.circular(14),
              size: 48,
            ),
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
                final ownerDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.ownerId)
                    .get();
                final ownerData = ownerDoc.data();
                final ownerName = ownerData?['displayName'] ?? 'オーナー';
                final ownerAvatarIndex = ownerData?['avatarIndex'] ?? 0;

                await ref
                    .read(circleServiceProvider)
                    .setSubOwner(
                      widget.circleId,
                      memberId,
                      circleName: widget.circleName,
                      ownerName: ownerName,
                      ownerAvatarIndex: ownerAvatarIndex,
                      ownerId: widget.ownerId,
                    );
                if (context.mounted) {
                  SnackBarHelper.showSuccess(
                    context,
                    AppMessages.circle.subOwnerAssigned(displayName),
                  );
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
                final ownerDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.ownerId)
                    .get();
                final ownerData = ownerDoc.data();
                final ownerName = ownerData?['displayName'] ?? 'オーナー';
                final ownerAvatarIndex = ownerData?['avatarIndex'] ?? 0;

                await ref
                    .read(circleServiceProvider)
                    .removeSubOwner(
                      widget.circleId,
                      subOwnerId: memberId,
                      circleName: widget.circleName,
                      ownerName: ownerName,
                      ownerAvatarIndex: ownerAvatarIndex,
                      ownerId: widget.ownerId,
                    );
                if (context.mounted) {
                  SnackBarHelper.showWarning(
                    context,
                    AppMessages.circle.subOwnerRemoved(displayName),
                  );
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
