import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/widgets/avatar_selector.dart';

/// フォロー中ユーザー一覧画面
class FollowingListScreen extends StatefulWidget {
  final List<String> followingIds;

  const FollowingListScreen({super.key, required this.followingIds});

  @override
  State<FollowingListScreen> createState() => _FollowingListScreenState();
}

class _FollowingListScreenState extends State<FollowingListScreen> {
  List<UserModel>? _users;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      // 10件ずつチャンク分割して一括取得
      final chunks = <List<String>>[];
      for (var i = 0; i < widget.followingIds.length; i += 10) {
        chunks.add(widget.followingIds.sublist(
          i,
          i + 10 > widget.followingIds.length
              ? widget.followingIds.length
              : i + 10,
        ));
      }

      final futures = chunks.map((chunk) => FirebaseFirestore.instance
          .collection('publicUsers')
          .where(FieldPath.documentId, whereIn: chunk)
          .get());

      final snapshots = await Future.wait(futures);

      if (!mounted) return;

      final users = <UserModel>[];
      for (final snapshot in snapshots) {
        for (final doc in snapshot.docs) {
          if (doc.exists) {
            users.add(UserModel.fromFirestore(doc));
          }
        }
      }

      // followingIds の順序を維持
      final userMap = {for (final u in users) u.uid: u};
      final orderedUsers = <UserModel>[];
      for (final id in widget.followingIds) {
        final user = userMap[id];
        if (user != null) orderedUsers.add(user);
      }

      setState(() => _users = orderedUsers);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppMessages.home.tabFollowing),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(AppMessages.error.general),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() => _hasError = false);
                _loadUsers();
              },
              child: Text(AppMessages.label.retry),
            ),
          ],
        ),
      );
    }

    if (_users == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_users!.isEmpty) {
      return Center(
        child: Text(
          AppMessages.home.emptyFollowingDescription,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _users!.length,
      itemBuilder: (context, index) {
        final user = _users![index];
        return _FollowingUserTile(user: user);
      },
    );
  }
}

class _FollowingUserTile extends StatelessWidget {
  final UserModel user;

  const _FollowingUserTile({required this.user});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: AvatarWidget(
        avatarIndex: user.avatarIndex,
        avatarParts:
            user.profileVisualMode == 'avatar' ? user.avatarParts : null,
        imageUrl:
            user.profileVisualMode == 'image' ? user.profileImageUrl : null,
        size: 44,
        borderRadius: BorderRadius.circular(12),
      ),
      title: Text(
        user.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => context.push('/user/${user.uid}'),
    );
  }
}
