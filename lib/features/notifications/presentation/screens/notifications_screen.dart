import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
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
    (NotificationCategory.timeline, 'timeline', Icons.chat_bubble_outline),
    (NotificationCategory.task, 'task', Icons.task_alt),
    (NotificationCategory.circle, 'circle', Icons.group_outlined),
    (NotificationCategory.support, 'support', Icons.support_agent),
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

    final notificationRepository =
        ref.watch(notificationRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppMessages.notification.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              await ref
                  .read(notificationRepositoryProvider)
                  .markAllAsRead(user.uid);
            },
            tooltip: AppMessages.notification.markAllRead,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
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
              final labelKey = tab.$2;
              final label = switch (labelKey) {
                'timeline' => AppMessages.notification.tabTimeline,
                'task' => AppMessages.notification.tabTask,
                'circle' => AppMessages.notification.tabCircle,
                'support' => AppMessages.notification.tabSupport,
                _ => labelKey,
              };
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
                    Positioned(
                      top: -4,
                      right: -4,
                      child: _UnreadCountBadge(
                        category: category,
                        userId: user.uid,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((tab) {
          final category = tab.$1;
          final notificationsStream = notificationRepository
              .getNotificationsStreamByCategory(user.uid, category);
          return StreamBuilder<List<NotificationModel>>(
            stream: notificationsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                debugPrint('NotificationsScreen error: ${snapshot.error}');
                return Center(child: Text(AppMessages.error.general));
              }

              final notifications = snapshot.data ?? [];
              return _NotificationList(notifications: notifications);
            },
          );
        }).toList(),
      ),
    );
  }
}

class _UnreadCountBadge extends ConsumerWidget {
  final NotificationCategory category;
  final String userId;

  const _UnreadCountBadge({
    required this.category,
    required this.userId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadStream = ref
        .watch(notificationRepositoryProvider)
        .getUnreadCountStreamByCategory(userId, category);

    return StreamBuilder<int>(
      stream: unreadStream,
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        if (unreadCount <= 0) {
          return const SizedBox.shrink();
        }
        return Container(
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
        );
      },
    );
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
              AppMessages.notification.empty,
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
        final taskTypes = [
          NotificationType.taskReminder,
          NotificationType.taskScheduled,
        ];
        if (taskTypes.contains(notification.type) && context.mounted) {
          if (notification.taskId != null) {
            context.go(
              '/tasks',
              extra: {
                'highlightTaskId': notification.taskId,
                'highlightRequestId': DateTime.now().millisecondsSinceEpoch,
                if (notification.scheduledAt != null)
                  'targetDate': notification.scheduledAt,
                'forceRefresh': true,
              },
            );
          } else {
            context.go('/tasks');
          }
          return;
        }

        if (notification.type == NotificationType.reviewNeeded &&
            context.mounted) {
          context.push('/admin-review');
          return;
        }

        if ((notification.type == NotificationType.circleDeleted ||
                notification.type == NotificationType.circleGhostDeleted) &&
            context.mounted) {
          context.go('/circles');
          return;
        }

        if (notification.type == NotificationType.goalReminder &&
            context.mounted) {
          if (notification.goalId != null) {
            context.push('/goals/detail/${notification.goalId}');
          } else {
            context.push('/goals');
          }
          return;
        }

        if (notification.inquiryId != null && context.mounted) {
          // 管理者向け通知は管理者用画面へ
          final adminInquiryTypes = [
            NotificationType.inquiryReceived,
            NotificationType.inquiryUserReply,
          ];
          if (adminInquiryTypes.contains(notification.type)) {
            context.push('/admin/inquiry/${notification.inquiryId}');
          } else {
            // ユーザー向け通知はユーザー用画面へ
            context.push('/inquiry/${notification.inquiryId}');
          }
        } else if (notification.postId != null && context.mounted) {
          context.push('/post/${notification.postId}');
        } else if (notification.type == NotificationType.adminReport &&
            context.mounted) {
          if (notification.contentId != null) {
            context.push('/admin/reports/content/${notification.contentId}');
          } else {
            context.push('/admin/reports');
          }
        } else if (notification.circleId != null && context.mounted) {
          // 拒否/削除通知は遷移しない
          final noNavigateTypes = [
            NotificationType.joinRequestRejected,
            NotificationType.circleDeleted,
            NotificationType.circleGhostDeleted,
          ];
          if (!noNavigateTypes.contains(notification.type)) {
            context.push('/circle/${notification.circleId}');
          }
        } else if (context.mounted) {
          final circleFallbackTypes = [
            NotificationType.circleSettingsChanged,
            NotificationType.circleGhostWarning,
          ];
          if (circleFallbackTypes.contains(notification.type)) {
            context.go('/circles');
          }
        }
      },
      tileColor: !notification.isRead
          ? AppColors.primary.withValues(alpha: 0.05)
          : null,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return AppMessages.notification.minutesAgo(diff.inMinutes);
    } else if (diff.inHours < 24) {
      return AppMessages.notification.hoursAgo(diff.inHours);
    } else {
      return DateFormat('MM/dd HH:mm').format(date);
    }
  }
}
