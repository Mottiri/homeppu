import 'package:cloud_firestore/cloud_firestore.dart';

/// メディアタイプ
enum MediaType { image, video, file }

/// メディアアイテム
class MediaItem {
  final String url;
  final MediaType type;
  final String? fileName;
  final String? mimeType;
  final int? fileSize; // バイト

  MediaItem({
    required this.url,
    required this.type,
    this.fileName,
    this.mimeType,
    this.fileSize,
  });

  factory MediaItem.fromMap(Map<String, dynamic> data) {
    return MediaItem(
      url: data['url'] ?? '',
      type: MediaType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => MediaType.image,
      ),
      fileName: data['fileName'],
      mimeType: data['mimeType'],
      fileSize: data['fileSize'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'type': type.name,
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSize': fileSize,
    };
  }
}

/// 投稿モデル
class PostModel {
  final String id;
  final String userId;
  final String userDisplayName;
  final int userAvatarIndex;
  final String content;
  final String? imageUrl; // 後方互換性のため残す
  final List<MediaItem> mediaItems; // 新しいメディアリスト
  final String postMode; // 'ai', 'mix', 'human'
  final String? circleId; // サークル投稿の場合
  final DateTime createdAt;
  final Map<String, int> reactions; // {'love': 5, 'praise': 3, ...}
  final int commentCount;
  final bool isVisible;
  final bool isPinned; // ピン留め
  final bool isPinnedTop; // トップ表示ピン

  PostModel({
    required this.id,
    required this.userId,
    required this.userDisplayName,
    required this.userAvatarIndex,
    required this.content,
    this.imageUrl,
    this.mediaItems = const [],
    required this.postMode,
    this.circleId,
    required this.createdAt,
    this.reactions = const {},
    this.commentCount = 0,
    this.isVisible = true,
    this.isPinned = false,
    this.isPinnedTop = false,
  });

  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // メディアアイテムのパース
    List<MediaItem> mediaItems = [];
    if (data['mediaItems'] != null) {
      mediaItems = (data['mediaItems'] as List)
          .map((item) => MediaItem.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    }

    return PostModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      userDisplayName: data['userDisplayName'] ?? 'ゲスト',
      userAvatarIndex: data['userAvatarIndex'] ?? 0,
      content: data['content'] ?? '',
      imageUrl: data['imageUrl'],
      mediaItems: mediaItems,
      postMode: data['postMode'] ?? 'mix',
      circleId: data['circleId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reactions: Map<String, int>.from(data['reactions'] ?? {}),
      commentCount: data['commentCount'] ?? 0,
      isVisible: data['isVisible'] ?? true,
      isPinned: data['isPinned'] ?? false,
      isPinnedTop: data['isPinnedTop'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userDisplayName': userDisplayName,
      'userAvatarIndex': userAvatarIndex,
      'content': content,
      'imageUrl': imageUrl,
      'mediaItems': mediaItems.map((item) => item.toMap()).toList(),
      'postMode': postMode,
      'circleId': circleId,
      'createdAt': Timestamp.fromDate(createdAt),
      'reactions': reactions,
      'commentCount': commentCount,
      'isVisible': isVisible,
      'isPinned': isPinned,
      'isPinnedTop': isPinnedTop,
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
    List<MediaItem>? mediaItems,
    String? postMode,
    String? circleId,
    DateTime? createdAt,
    Map<String, int>? reactions,
    int? commentCount,
    bool? isVisible,
    bool? isPinned,
    bool? isPinnedTop,
  }) {
    return PostModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userDisplayName: userDisplayName ?? this.userDisplayName,
      userAvatarIndex: userAvatarIndex ?? this.userAvatarIndex,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      mediaItems: mediaItems ?? this.mediaItems,
      postMode: postMode ?? this.postMode,
      circleId: circleId ?? this.circleId,
      createdAt: createdAt ?? this.createdAt,
      reactions: reactions ?? this.reactions,
      commentCount: commentCount ?? this.commentCount,
      isVisible: isVisible ?? this.isVisible,
      isPinned: isPinned ?? this.isPinned,
      isPinnedTop: isPinnedTop ?? this.isPinnedTop,
    );
  }

  /// すべてのメディア（後方互換性も含めて）
  List<MediaItem> get allMedia {
    if (mediaItems.isNotEmpty) return mediaItems;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return [MediaItem(url: imageUrl!, type: MediaType.image)];
    }
    return [];
  }

  /// 画像のみ
  List<MediaItem> get images =>
      allMedia.where((m) => m.type == MediaType.image).toList();

  /// 動画のみ
  List<MediaItem> get videos =>
      allMedia.where((m) => m.type == MediaType.video).toList();

  /// ファイルのみ
  List<MediaItem> get files =>
      allMedia.where((m) => m.type == MediaType.file).toList();
}
