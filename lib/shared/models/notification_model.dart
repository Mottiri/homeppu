import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  comment,
  reaction,
  system,
  joinRequestReceived,
  joinRequestApproved,
  joinRequestRejected,
  circleDeleted,
  circleSettingsChanged,
  circleGhostWarning,
  circleGhostDeleted,
  subOwnerAppointed,
  subOwnerRemoved,
  inquiryReply,
  inquiryStatusChanged,
  inquiryReceived,
  inquiryUserReply,
  inquiryDeletionWarning,
  adminReport,
  reviewNeeded,
  postDeleted,
  postHidden,
  postRejected,
  userBanned,
  userUnbanned,
}

enum NotificationCategory {
  support,
  timeline,
  circle,
}

NotificationCategory getCategoryFromType(NotificationType type) {
  switch (type) {
    case NotificationType.comment:
    case NotificationType.reaction:
    case NotificationType.system:
      return NotificationCategory.timeline;
    case NotificationType.joinRequestReceived:
    case NotificationType.joinRequestApproved:
    case NotificationType.joinRequestRejected:
    case NotificationType.circleDeleted:
    case NotificationType.circleSettingsChanged:
    case NotificationType.circleGhostWarning:
    case NotificationType.circleGhostDeleted:
    case NotificationType.subOwnerAppointed:
    case NotificationType.subOwnerRemoved:
      return NotificationCategory.circle;
    case NotificationType.inquiryReply:
    case NotificationType.inquiryStatusChanged:
    case NotificationType.inquiryReceived:
    case NotificationType.inquiryUserReply:
    case NotificationType.inquiryDeletionWarning:
    case NotificationType.adminReport:
    case NotificationType.reviewNeeded:
    case NotificationType.postDeleted:
    case NotificationType.postHidden:
    case NotificationType.postRejected:
    case NotificationType.userBanned:
    case NotificationType.userUnbanned:
      return NotificationCategory.support;
  }
}

class NotificationModel {
  final String id;
  final String userId;
  final String senderId;
  final String senderName;
  final String senderAvatarUrl;
  final NotificationType type;
  final String title;
  final String body;
  final String? postId;
  final String? circleId;
  final String? inquiryId;
  final String? reportId;
  final String? contentId;
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
    this.reportId,
    this.contentId,
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
      reportId: data['reportId'],
      contentId: data['contentId'],
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
      'type': type.name,
      'title': title,
      'body': body,
      'postId': postId,
      'circleId': circleId,
      'inquiryId': inquiryId,
      'reportId': reportId,
      'contentId': contentId,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  static NotificationType _parseNotificationType(String? typeStr) {
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
      case 'circle_settings_changed':
        return NotificationType.circleSettingsChanged;
      case 'circle_ghost_warning':
        return NotificationType.circleGhostWarning;
      case 'circle_ghost_deleted':
        return NotificationType.circleGhostDeleted;
      case 'sub_owner_appointed':
        return NotificationType.subOwnerAppointed;
      case 'sub_owner_removed':
        return NotificationType.subOwnerRemoved;
      case 'inquiry_reply':
        return NotificationType.inquiryReply;
      case 'inquiry_status_changed':
        return NotificationType.inquiryStatusChanged;
      case 'inquiry_received':
        return NotificationType.inquiryReceived;
      case 'inquiry_user_reply':
        return NotificationType.inquiryUserReply;
      case 'inquiry_deletion_warning':
        return NotificationType.inquiryDeletionWarning;
      case 'admin_report':
        return NotificationType.adminReport;
      case 'review_needed':
        return NotificationType.reviewNeeded;
      case 'post_deleted':
        return NotificationType.postDeleted;
      case 'post_hidden':
        return NotificationType.postHidden;
      case 'post_rejected':
        return NotificationType.postRejected;
      case 'user_banned':
        return NotificationType.userBanned;
      case 'user_unbanned':
        return NotificationType.userUnbanned;
      default:
        return NotificationType.system;
    }
  }
}
