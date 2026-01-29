import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/models/user_model.dart';
import '../../../../shared/widgets/avatar_selector.dart';

/// フォロー中リスト（横スクロール）
class ProfileFollowingList extends StatelessWidget {
  final List<String> followingIds;

  const ProfileFollowingList({super.key, required this.followingIds});

  @override
  Widget build(BuildContext context) {
    if (followingIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: followingIds.length,
        itemBuilder: (context, index) {
          final userId = followingIds[index];
          return ProfileFollowingUserItem(userId: userId);
        },
      ),
    );
  }
}

/// フォロー中ユーザーアイテム
class ProfileFollowingUserItem extends StatelessWidget {
  final String userId;

  const ProfileFollowingUserItem({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('publicUsers')
          .doc(userId)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final user = UserModel.fromFirestore(snapshot.data!);

        return GestureDetector(
          onTap: () => context.push('/user/${user.uid}'),
          child: Container(
            width: 80,
            margin: const EdgeInsets.only(right: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AvatarWidget(avatarIndex: user.avatarIndex, size: 56),
                const SizedBox(height: 8),
                Text(
                  user.displayName,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
