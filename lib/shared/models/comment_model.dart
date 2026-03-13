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
  final bool thanksLikedByPostOwner;
  final DateTime? thanksLikedAt;
  final String? thanksLikedBy;
  final String? clientRequestId;

  CommentModel({
    required this.id,
    required this.postId,
    required this.userId,
    required this.userDisplayName,
    required this.userAvatarIndex,
    this.isAI = false,
    required this.content,
    required this.createdAt,
    this.thanksLikedByPostOwner = false,
    this.thanksLikedAt,
    this.thanksLikedBy,
    this.clientRequestId,
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
      thanksLikedByPostOwner: data['thanksLikedByPostOwner'] == true,
      thanksLikedAt: (data['thanksLikedAt'] as Timestamp?)?.toDate(),
      thanksLikedBy: data['thanksLikedBy'] as String?,
      clientRequestId: data['clientRequestId'] as String?,
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
      'thanksLikedByPostOwner': thanksLikedByPostOwner,
      'thanksLikedAt':
          thanksLikedAt != null ? Timestamp.fromDate(thanksLikedAt!) : null,
      'thanksLikedBy': thanksLikedBy,
      if (clientRequestId != null) 'clientRequestId': clientRequestId,
    };
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
    bool? thanksLikedByPostOwner,
    DateTime? thanksLikedAt,
    String? thanksLikedBy,
    String? clientRequestId,
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
      thanksLikedByPostOwner:
          thanksLikedByPostOwner ?? this.thanksLikedByPostOwner,
      thanksLikedAt: thanksLikedAt ?? this.thanksLikedAt,
      thanksLikedBy: thanksLikedBy ?? this.thanksLikedBy,
      clientRequestId: clientRequestId ?? this.clientRequestId,
    );
  }
}


