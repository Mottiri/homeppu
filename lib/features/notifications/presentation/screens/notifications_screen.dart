import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/notification_model.dart';
import '../../../../shared/repositories/notification_repository.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/widgets/avatar_selector.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // カテゴリタブの定義
  static const _tabs = [
    (NotificationCategory.all, 'すべて', Icons.notifications),
    (NotificationCategory.timeline, 'TL', Icons.chat_bubble_outline),
    (NotificationCategory.circle, 'サークル', Icons.group_outlined),
    (NotificationCategory.task, 'タスク', Icons.task_alt),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: StreamBuilder<List<NotificationModel>>(
            stream: notificationsStream,
            builder: (context, snapshot) {
              final notifications = snapshot.data ?? [];
              return TabBar(
                controller: _tabController,
                isScrollable: true, // スクロール可能にして狭い画面に対応
                tabAlignment: TabAlignment.center, // 中央寄せ
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                labelPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                ), // 適度なパディング
                tabs: _tabs.map((tab) {
                  final category = tab.$1;
                  final label = tab.$2;
                  final unreadCount = _getUnreadCount(notifications, category);
                  return Tab(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            top: -4,
                            right: -4,
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                unreadCount > 99 ? '99' : '$unreadCount',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
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

          final allNotifications = snapshot.data ?? [];

          return TabBarView(
            controller: _tabController,
            children: _tabs.map((tab) {
              final category = tab.$1;
              final filteredNotifications = _filterByCategory(
                allNotifications,
                category,
              );
              return _NotificationList(notifications: filteredNotifications);
            }).toList(),
          );
        },
      ),
    );
  }

  /// カテゴリ別の未読数を取得
  int _getUnreadCount(
    List<NotificationModel> notifications,
    NotificationCategory category,
  ) {
    if (category == NotificationCategory.all) {
      return notifications.where((n) => !n.isRead).length;
    }
    return notifications
        .where((n) => !n.isRead && getCategoryFromType(n.type) == category)
        .length;
  }

  /// カテゴリでフィルタリング
  List<NotificationModel> _filterByCategory(
    List<NotificationModel> notifications,
    NotificationCategory category,
  ) {
    if (category == NotificationCategory.all) {
      return notifications;
    }
    return notifications
        .where((n) => getCategoryFromType(n.type) == category)
        .toList();
  }
}

/// 通知リスト
class _NotificationList extends StatelessWidget {
  final List<NotificationModel> notifications;

  const _NotificationList({required this.notifications});

  @override
  Widget build(BuildContext context) {
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppColors.textSecondary),
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
      title: Text(
        notification.body.isNotEmpty ? notification.body : notification.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _formatDate(notification.createdAt),
        style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
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
