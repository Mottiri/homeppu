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

  // S6: 未読件数を取得するストリーム（全体）
  // userドキュメントの非正規化フィールドを監視（1ドキュメント）
  Stream<int> getUnreadCountStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          final count = (data?['unreadNotificationCount'] as int?) ?? 0;
          return count < 0 ? 0 : count;
        });
  }

  // S6: カテゴリ別の未読件数を取得するストリーム
  // userドキュメントの非正規化フィールドを監視（同一ドキュメントのためリスナー共有）
  Stream<int> getUnreadCountStreamByCategory(
    String userId,
    NotificationCategory category,
  ) {
    final field = _getCategoryCountField(category);
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          final count = (data?[field] as int?) ?? 0;
          return count < 0 ? 0 : count;
        });
  }

  String _getCategoryCountField(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.timeline:
        return 'unreadTimelineCount';
      case NotificationCategory.circle:
        return 'unreadCircleCount';
      case NotificationCategory.support:
        return 'unreadSupportCount';
    }
  }

  // S6: 通知を既読にする（カウントデクリメント付き）
  Future<void> markAsRead(
    String userId,
    String notificationId,
    NotificationType type,
  ) async {
    final batch = _firestore.batch();

    final notifRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notificationId);
    batch.update(notifRef, {'isRead': true});

    final userRef = _firestore.collection('users').doc(userId);
    final category = getCategoryFromType(type);
    final categoryField = _getCategoryCountField(category);
    batch.update(userRef, {
      'unreadNotificationCount': FieldValue.increment(-1),
      categoryField: FieldValue.increment(-1),
    });

    await batch.commit();
  }

  // S6: 全て既読にする（カウントリセット付き）
  // increment(-count) で競合安全に減算
  Future<void> markAllAsRead(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .get();

    if (snapshot.docs.isEmpty) return;

    // カテゴリ別にカウント
    int timelineCount = 0;
    int circleCount = 0;
    int supportCount = 0;
    for (var doc in snapshot.docs) {
      final type = doc.data()['type'] as String? ?? 'system';
      final category = getCategoryFromType(
        NotificationType.values.firstWhere(
          (e) => e.name == _snakeToCamel(type),
          orElse: () => NotificationType.system,
        ),
      );
      switch (category) {
        case NotificationCategory.timeline:
          timelineCount++;
        case NotificationCategory.circle:
          circleCount++;
        case NotificationCategory.support:
          supportCount++;
      }
    }

    final batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    final userRef = _firestore.collection('users').doc(userId);
    batch.update(userRef, {
      'unreadNotificationCount': FieldValue.increment(-(timelineCount + circleCount + supportCount)),
      'unreadTimelineCount': FieldValue.increment(-timelineCount),
      'unreadCircleCount': FieldValue.increment(-circleCount),
      'unreadSupportCount': FieldValue.increment(-supportCount),
    });

    await batch.commit();
  }

  /// Firestore の snake_case type を camelCase に変換
  static String _snakeToCamel(String snake) {
    final parts = snake.split('_');
    return parts.first +
        parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
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
          'sub_owner_appointed',
          'sub_owner_removed',
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
          'post_rejected',
          'user_banned',
          'user_unbanned',
        ];
    }
  }
}
