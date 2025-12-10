import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType { comment, reaction, system }

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
      type: NotificationType.values.firstWhere(
        (e) => e.toString() == 'NotificationType.${data['type']}',
        orElse: () => NotificationType.system,
      ),
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      postId: data['postId'],
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
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
