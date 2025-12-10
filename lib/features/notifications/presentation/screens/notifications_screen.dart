import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/notification_model.dart';
import '../../../../shared/repositories/notification_repository.dart';
import '../../../../shared/providers/auth_provider.dart';

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
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withOpacity(0.1),
        // TODO: アバター画像表示 (notification.senderAvatarUrl)
        child: Icon(
          _getIcon(notification.type),
          color: _getIconColor(notification.type),
          size: 20,
        ),
      ),
      title: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: notification.senderName,
              style: const TextStyle(fontWeight: FontWeight.bold),
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

        // 投稿詳細へ遷移
        if (notification.postId != null && context.mounted) {
          context.push('/post/${notification.postId}');
        }
      },
      tileColor: !notification.isRead
          ? AppColors.primary.withOpacity(0.05)
          : null,
    );
  }

  IconData _getIcon(NotificationType type) {
    switch (type) {
      case NotificationType.comment:
        return Icons.chat_bubble_outline;
      case NotificationType.reaction:
        return Icons.favorite_border;
      case NotificationType.system:
        return Icons.info_outline;
    }
  }

  Color _getIconColor(NotificationType type) {
    switch (type) {
      case NotificationType.comment:
        return AppColors.comment;
      case NotificationType.reaction:
        return AppColors.praise; // 称賛色
      case NotificationType.system:
        return AppColors.primary;
    }
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
