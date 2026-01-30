import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_model.dart';

final notificationRepositoryProvider = Provider(
  (ref) => NotificationRepository(),
);

class NotificationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 通知一覧を取得するストリーム（全体）
  Stream<List<NotificationModel>> getNotificationsStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(50) // 直近50件
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => NotificationModel.fromFirestore(doc))
              .toList();
        });
  }

  // カテゴリ別の通知一覧を取得するストリーム
  Stream<List<NotificationModel>> getNotificationsStreamByCategory(
    String userId,
    NotificationCategory category,
  ) {
    final types = _getNotificationTypesForCategory(category);
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('type', whereIn: types)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => NotificationModel.fromFirestore(doc))
              .toList();
        });
  }

  // 未読件数を取得するストリーム（全体）
  Stream<int> getUnreadCountStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // カテゴリ別の未読件数を取得するストリーム
  Stream<int> getUnreadCountStreamByCategory(
    String userId,
    NotificationCategory category,
  ) {
    final types = _getNotificationTypesForCategory(category);
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .where('type', whereIn: types)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // 通知を既読にする
  Future<void> markAsRead(String userId, String notificationId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }

  // 全て既読にする
  Future<void> markAllAsRead(String userId) async {
    final batch = _firestore.batch();
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .get();

    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    await batch.commit();
  }

  List<String> _getNotificationTypesForCategory(
    NotificationCategory category,
  ) {
    switch (category) {
      case NotificationCategory.timeline:
        return const [
          'comment',
          'reaction',
          'system',
        ];
      case NotificationCategory.circle:
        return const [
          'join_request_received',
          'join_request_approved',
          'join_request_rejected',
          'circle_deleted',
          'circle_settings_changed',
          'circle_ghost_warning',
          'circle_ghost_deleted',
        ];
      case NotificationCategory.task:
        return const [
          'task_reminder',
          'task_scheduled',
          'goal_reminder',
        ];
      case NotificationCategory.support:
        return const [
          'inquiry_reply',
          'inquiry_status_changed',
          'inquiry_received',
          'inquiry_user_reply',
          'inquiry_deletion_warning',
          'admin_report',
          'review_needed',
          'post_deleted',
          'post_hidden',
          'user_banned',
          'user_unbanned',
        ];
    }
  }
}
