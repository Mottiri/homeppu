import 'package:cloud_firestore/cloud_firestore.dart';

enum MediaType { image, video, file }

class MediaItem {
  final String url;
  final MediaType type;
  final String? fileName;
  final String? mimeType;
  final int? fileSize;
  final String? thumbnailUrl;
  final String? storagePath;

  MediaItem({
    required this.url,
    required this.type,
    this.fileName,
    this.mimeType,
    this.fileSize,
    this.thumbnailUrl,
    this.storagePath,
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
      thumbnailUrl: data['thumbnailUrl'],
      storagePath: data['storagePath'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'type': type.name,
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSize': fileSize,
      'thumbnailUrl': thumbnailUrl,
      'storagePath': storagePath,
    };
  }
}

class PostModel {
  final String id;
  final String userId;
  final String userDisplayName;
  final int userAvatarIndex;
  final String content;
  final String? imageUrl;
  final List<MediaItem> mediaItems;
  final String postMode;
  final String? circleId;
  final DateTime createdAt;
  final Map<String, int> reactions;
  final int commentCount;
  final bool isVisible;
  final bool isPinned;
  final bool isPinnedTop;
  final bool isFavorite;

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
    this.isFavorite = false,
  });

  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    var mediaItems = <MediaItem>[];
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
      isFavorite: data['isFavorite'] ?? false,
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
      'isFavorite': isFavorite,
    };
  }

  int get totalReactions {
    return reactions.values.fold(0, (acc, value) => acc + value);
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
    bool? isFavorite,
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
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  List<MediaItem> get allMedia {
    if (mediaItems.isNotEmpty) {
      return mediaItems.where((m) => m.type != MediaType.file).toList();
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return [MediaItem(url: imageUrl!, type: MediaType.image)];
    }
    return [];
  }

  List<MediaItem> get images =>
      allMedia.where((m) => m.type == MediaType.image).toList();

  List<MediaItem> get videos =>
      allMedia.where((m) => m.type == MediaType.video).toList();

  List<MediaItem> get files =>
      allMedia.where((m) => m.type == MediaType.file).toList();
}
