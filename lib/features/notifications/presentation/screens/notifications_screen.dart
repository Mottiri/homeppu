import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/notification_model.dart';
import '../../../../shared/repositories/notification_repository.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/widgets/avatar_selector.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final notificationsStream = ref
        .watch(notificationRepositoryProvider)
        .getNotificationsStream(user.uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              await ref
                  .read(notificationRepositoryProvider)
                  .markAllAsRead(user.uid);
            },
            tooltip: '全て既読にする',
          ),
        ],
      ),
      body: StreamBuilder<List<NotificationModel>>(
        stream: notificationsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('エラーが発生しました: ${snapshot.error}'));
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.notifications_off_outlined,
                    size: 64,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'まだ通知はありません',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return _NotificationTile(notification: notification);
            },
          );
        },
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final NotificationModel notification;

  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;

    return ListTile(
      leading: GestureDetector(
        onTap: () {
          if (notification.senderId.isNotEmpty) {
            context.push('/profile/${notification.senderId}');
          }
        },
        child: AvatarWidget(
          avatarIndex: int.tryParse(notification.senderAvatarUrl) ?? 0,
          size: 40,
        ),
      ),
      title: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            WidgetSpan(
              child: GestureDetector(
                onTap: () {
                  if (notification.senderId.isNotEmpty) {
                    context.push('/profile/${notification.senderId}');
                  }
                },
                child: Text(
                  notification.senderName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            TextSpan(text: 'さんが${notification.title}'),
          ],
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notification.body.isNotEmpty)
            Text(
              notification.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          Text(
            _formatDate(notification.createdAt),
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
      trailing: !notification.isRead
          ? Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            )
          : null,
      onTap: () async {
        // 既読にする
        if (!notification.isRead && user != null) {
          await ref
              .read(notificationRepositoryProvider)
              .markAsRead(user.uid, notification.id);
        }

        // 遷移先を決定
        if (notification.postId != null && context.mounted) {
          context.push('/post/${notification.postId}');
        } else if (notification.circleId != null && context.mounted) {
          // 拒否/削除通知は遷移しない
          final noNavigateTypes = [
            NotificationType.joinRequestRejected,
            NotificationType.circleDeleted,
          ];
          if (!noNavigateTypes.contains(notification.type)) {
            context.push('/circle/${notification.circleId}');
          }
        }
      },
      tileColor: !notification.isRead
          ? AppColors.primary.withOpacity(0.05)
          : null,
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
      return DateFormat('MM/dd HH:mm').format(date);
    }
  }
}
