import 'package:cloud_firestore/cloud_firestore.dart';

/// コメントモデル（1階層のみ）
class CommentModel {
  final String id;
  final String postId;
  final String userId;
  final String userDisplayName;
  final int userAvatarIndex;
  final bool isAI;
  final String content;
  final DateTime createdAt;
  final DateTime? scheduledAt;  // AI応答の場合、表示予定時刻

  CommentModel({
    required this.id,
    required this.postId,
    required this.userId,
    required this.userDisplayName,
    required this.userAvatarIndex,
    this.isAI = false,
    required this.content,
    required this.createdAt,
    this.scheduledAt,
  });

  factory CommentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CommentModel(
      id: doc.id,
      postId: data['postId'] ?? '',
      userId: data['userId'] ?? '',
      userDisplayName: data['userDisplayName'] ?? 'ゲスト',
      userAvatarIndex: data['userAvatarIndex'] ?? 0,
      isAI: data['isAI'] ?? false,
      content: data['content'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      scheduledAt: (data['scheduledAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'postId': postId,
      'userId': userId,
      'userDisplayName': userDisplayName,
      'userAvatarIndex': userAvatarIndex,
      'isAI': isAI,
      'content': content,
      'createdAt': Timestamp.fromDate(createdAt),
      'scheduledAt': scheduledAt != null ? Timestamp.fromDate(scheduledAt!) : null,
    };
  }

  /// コメントを表示していいか（AI応答の遅延表示対応）
  bool get isVisibleNow {
    if (scheduledAt == null) return true;
    return DateTime.now().isAfter(scheduledAt!);
  }

  CommentModel copyWith({
    String? id,
    String? postId,
    String? userId,
    String? userDisplayName,
    int? userAvatarIndex,
    bool? isAI,
    String? content,
    DateTime? createdAt,
    DateTime? scheduledAt,
  }) {
    return CommentModel(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      userDisplayName: userDisplayName ?? this.userDisplayName,
      userAvatarIndex: userAvatarIndex ?? this.userAvatarIndex,
      isAI: isAI ?? this.isAI,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      scheduledAt: scheduledAt ?? this.scheduledAt,
    );
  }
}


