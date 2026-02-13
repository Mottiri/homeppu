import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/public_user_provider.dart';
import '../providers/auth_provider.dart';
import 'avatar_selector.dart';

class PublicUserAvatar extends ConsumerWidget {
  final String userId;
  final int avatarIndex;
  final double size;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;

  const PublicUserAvatar({
    super.key,
    required this.userId,
    required this.avatarIndex,
    this.size = 40,
    this.backgroundColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    if (currentUser != null && currentUser.uid == userId) {
      final mode = currentUser.profileVisualMode;
      return AvatarWidget(
        avatarIndex: avatarIndex,
        avatarParts: mode == 'avatar' ? currentUser.avatarParts : null,
        imageUrl: mode == 'image' ? currentUser.profileImageUrl : null,
        size: size,
        backgroundColor: backgroundColor,
        borderRadius: borderRadius,
      );
    }

    if (userId.isEmpty) {
      return AvatarWidget(
        avatarIndex: avatarIndex,
        size: size,
        backgroundColor: backgroundColor,
        borderRadius: borderRadius,
      );
    }

    final data = ref.watch(publicUserDocProvider(userId)).valueOrNull;
    final mode = (data?['profileVisualMode'] as String?) ?? 'icon';
    final imageUrl = data?['profileImageUrl'] as String?;
    final parts = ref.watch(publicUserAvatarPartsProvider(userId));
    return AvatarWidget(
      avatarIndex: avatarIndex,
      avatarParts: mode == 'avatar' ? parts : null,
      imageUrl: mode == 'image' ? imageUrl : null,
      size: size,
      backgroundColor: backgroundColor,
      borderRadius: borderRadius,
    );
  }
}
