import 'package:cloud_firestore/cloud_firestore.dart';

/// 投稿モデル
class PostModel {
  final String id;
  final String userId;
  final String userDisplayName;
  final int userAvatarIndex;
  final String content;
  final String? imageUrl;
  final String postMode;        // 'ai', 'mix', 'human'
  final String? circleId;       // サークル投稿の場合
  final DateTime createdAt;
  final Map<String, int> reactions;  // {'love': 5, 'praise': 3, ...}
  final int commentCount;
  final bool isVisible;

  PostModel({
    required this.id,
    required this.userId,
    required this.userDisplayName,
    required this.userAvatarIndex,
    required this.content,
    this.imageUrl,
    required this.postMode,
    this.circleId,
    required this.createdAt,
    this.reactions = const {},
    this.commentCount = 0,
    this.isVisible = true,
  });

  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PostModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      userDisplayName: data['userDisplayName'] ?? 'ゲスト',
      userAvatarIndex: data['userAvatarIndex'] ?? 0,
      content: data['content'] ?? '',
      imageUrl: data['imageUrl'],
      postMode: data['postMode'] ?? 'mix',
      circleId: data['circleId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reactions: Map<String, int>.from(data['reactions'] ?? {}),
      commentCount: data['commentCount'] ?? 0,
      isVisible: data['isVisible'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userDisplayName': userDisplayName,
      'userAvatarIndex': userAvatarIndex,
      'content': content,
      'imageUrl': imageUrl,
      'postMode': postMode,
      'circleId': circleId,
      'createdAt': Timestamp.fromDate(createdAt),
      'reactions': reactions,
      'commentCount': commentCount,
      'isVisible': isVisible,
    };
  }

  /// リアクションの合計数
  int get totalReactions {
    return reactions.values.fold(0, (sum, count) => sum + count);
  }

  PostModel copyWith({
    String? id,
    String? userId,
    String? userDisplayName,
    int? userAvatarIndex,
    String? content,
    String? imageUrl,
    String? postMode,
    String? circleId,
    DateTime? createdAt,
    Map<String, int>? reactions,
    int? commentCount,
    bool? isVisible,
  }) {
    return PostModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userDisplayName: userDisplayName ?? this.userDisplayName,
      userAvatarIndex: userAvatarIndex ?? this.userAvatarIndex,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      postMode: postMode ?? this.postMode,
      circleId: circleId ?? this.circleId,
      createdAt: createdAt ?? this.createdAt,
      reactions: reactions ?? this.reactions,
      commentCount: commentCount ?? this.commentCount,
      isVisible: isVisible ?? this.isVisible,
    );
  }
}


