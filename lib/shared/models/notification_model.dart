import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  comment,
  reaction,
  system,
  // サークル関連
  joinRequestReceived,
  joinRequestApproved,
  joinRequestRejected,
  circleDeleted,
  // タスク関連
  taskReminder,
  taskScheduled,
  // サポート（問い合わせ）関連
  inquiryReply, // 運営から返信があった
  inquiryStatusChanged, // ステータスが変更された
  inquiryReceived, // 新規問い合わせ受信（管理者向け）
  inquiryUserReply, // ユーザーから返信があった（管理者向け）
}

/// 通知のカテゴリ（タブ分類用）
enum NotificationCategory {
  support, // サポート通知
  timeline, // TL通知（コメント、リアクション）
  circle, // サークル通知
  task, // タスク通知
}

/// NotificationTypeからカテゴリを取得
NotificationCategory getCategoryFromType(NotificationType type) {
  switch (type) {
    case NotificationType.comment:
    case NotificationType.reaction:
      return NotificationCategory.timeline;
    case NotificationType.joinRequestReceived:
    case NotificationType.joinRequestApproved:
    case NotificationType.joinRequestRejected:
    case NotificationType.circleDeleted:
      return NotificationCategory.circle;
    case NotificationType.taskReminder:
    case NotificationType.taskScheduled:
      return NotificationCategory.task;
    case NotificationType.inquiryReply:
    case NotificationType.inquiryStatusChanged:
    case NotificationType.inquiryReceived:
    case NotificationType.inquiryUserReply:
      return NotificationCategory.support;
    case NotificationType.system:
      return NotificationCategory.timeline; // システム通知はTLに分類
  }
}

class NotificationModel {
  final String id;
  final String userId; // 通知を受け取るユーザー
  final String senderId; // アクションを起こしたユーザー
  final String senderName;
  final String senderAvatarUrl; // アバターアイコン用（インデックスなどの場合は適宜変更）
  final NotificationType type;
  final String title;
  final String body;
  final String? postId; // 関連する投稿ID
  final String? circleId; // 関連するサークルID
  final String? inquiryId; // 関連する問い合わせID（サポート通知用）
  final bool isRead;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.senderId,
    required this.senderName,
    this.senderAvatarUrl = '',
    required this.type,
    required this.title,
    required this.body,
    this.postId,
    this.circleId,
    this.inquiryId,
    this.isRead = false,
    required this.createdAt,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Unknown',
      senderAvatarUrl: data['senderAvatarUrl'] ?? '',
      type: _parseNotificationType(data['type'] as String?),
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      postId: data['postId'],
      circleId: data['circleId'],
      inquiryId: data['inquiryId'],
      isRead: data['isRead'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatarUrl': senderAvatarUrl,
      'type': type.name, // Enumの名前をそのまま保存
      'title': title,
      'body': body,
      'postId': postId,
      'circleId': circleId,
      'inquiryId': inquiryId,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  static NotificationType _parseNotificationType(String? typeStr) {
    if (typeStr == null) return NotificationType.system;

    switch (typeStr) {
      case 'comment':
        return NotificationType.comment;
      case 'reaction':
        return NotificationType.reaction;
      case 'join_request_received':
        return NotificationType.joinRequestReceived;
      case 'join_request_approved':
        return NotificationType.joinRequestApproved;
      case 'join_request_rejected':
        return NotificationType.joinRequestRejected;
      case 'circle_deleted':
        return NotificationType.circleDeleted;
      case 'task_reminder':
        return NotificationType.taskReminder;
      case 'task_scheduled':
        return NotificationType.taskScheduled;
      // サポート関連
      case 'inquiry_reply':
        return NotificationType.inquiryReply;
      case 'inquiry_status_changed':
        return NotificationType.inquiryStatusChanged;
      case 'inquiry_received':
        return NotificationType.inquiryReceived;
      case 'inquiry_user_reply':
        return NotificationType.inquiryUserReply;
      default:
        return NotificationType.system;
    }
  }
}
