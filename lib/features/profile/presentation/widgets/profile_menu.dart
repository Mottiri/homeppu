import 'package:flutter/material.dart';

import 'profile_following_list.dart';

class ProfileMenu extends StatelessWidget {
  final List<String> followingIds;

  const ProfileMenu({super.key, required this.followingIds});

  @override
  Widget build(BuildContext context) {
    if (followingIds.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'フォロー中',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          ProfileFollowingList(followingIds: followingIds),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
