import 'package:cloud_firestore/cloud_firestore.dart';

enum MediaType { image, video, file }

enum PostModerationStatus {
  processing,
  approved,
  rejected,
  reviewNeeded,
}

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
  final List<String> mediaStoragePaths;
  final String postMode;
  final String? circleId;
  final DateTime createdAt;
  final Map<String, int> reactions;
  final int commentCount;
  final bool isVisible;
  final bool isPinned;
  final bool isPinnedTop;
  final bool isFavorite;
  final PostModerationStatus moderationStatus;
  final String moderationReason;
  final DateTime? moderationCompletedAt;
  final DateTime? ownerVisibleUntil;
  final bool needsReview;
  final String needsReviewReason;
  final bool publishSideEffectsPending;
  final bool grantVirtueOnPublish;
  final String? clientRequestId;

  PostModel({
    required this.id,
    required this.userId,
    required this.userDisplayName,
    required this.userAvatarIndex,
    required this.content,
    this.imageUrl,
    this.mediaItems = const [],
    this.mediaStoragePaths = const [],
    required this.postMode,
    this.circleId,
    required this.createdAt,
    this.reactions = const {},
    this.commentCount = 0,
    this.isVisible = true,
    this.isPinned = false,
    this.isPinnedTop = false,
    this.isFavorite = false,
    this.moderationStatus = PostModerationStatus.approved,
    this.moderationReason = '',
    this.moderationCompletedAt,
    this.ownerVisibleUntil,
    this.needsReview = false,
    this.needsReviewReason = '',
    this.publishSideEffectsPending = false,
    this.grantVirtueOnPublish = false,
    this.clientRequestId,
  });

  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    var parsedMediaItems = <MediaItem>[];
    if (data['mediaItems'] != null) {
      parsedMediaItems = (data['mediaItems'] as List)
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
      mediaItems: parsedMediaItems,
      mediaStoragePaths: List<String>.from(data['mediaStoragePaths'] ?? const []),
      postMode: data['postMode'] ?? 'mix',
      circleId: data['circleId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reactions: Map<String, int>.from(data['reactions'] ?? const {}),
      commentCount: data['commentCount'] ?? 0,
      isVisible: data['isVisible'] ?? true,
      isPinned: data['isPinned'] ?? false,
      isPinnedTop: data['isPinnedTop'] ?? false,
      isFavorite: data['isFavorite'] ?? false,
      moderationStatus: _parseModerationStatus(data['moderationStatus']),
      moderationReason: data['moderationReason'] ?? '',
      moderationCompletedAt:
          (data['moderationCompletedAt'] as Timestamp?)?.toDate(),
      ownerVisibleUntil: (data['ownerVisibleUntil'] as Timestamp?)?.toDate(),
      needsReview: data['needsReview'] ?? false,
      needsReviewReason: data['needsReviewReason'] ?? '',
      publishSideEffectsPending: data['publishSideEffectsPending'] ?? false,
      grantVirtueOnPublish: data['grantVirtueOnPublish'] ?? false,
      clientRequestId: data['clientRequestId'],
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
      'mediaStoragePaths': mediaStoragePaths,
      'postMode': postMode,
      'circleId': circleId,
      'createdAt': Timestamp.fromDate(createdAt),
      'reactions': reactions,
      'commentCount': commentCount,
      'isVisible': isVisible,
      'isPinned': isPinned,
      'isPinnedTop': isPinnedTop,
      'isFavorite': isFavorite,
      'moderationStatus': moderationStatus.name,
      'moderationReason': moderationReason,
      'moderationCompletedAt':
          moderationCompletedAt != null
              ? Timestamp.fromDate(moderationCompletedAt!)
              : null,
      'ownerVisibleUntil':
          ownerVisibleUntil != null
              ? Timestamp.fromDate(ownerVisibleUntil!)
              : null,
      'needsReview': needsReview,
      'needsReviewReason': needsReviewReason,
      'publishSideEffectsPending': publishSideEffectsPending,
      'grantVirtueOnPublish': grantVirtueOnPublish,
      'clientRequestId': clientRequestId,
    };
  }

  int get totalReactions {
    return reactions.values.fold(0, (acc, value) => acc + value);
  }

  bool get isProcessing => moderationStatus == PostModerationStatus.processing;

  bool get isApproved => moderationStatus == PostModerationStatus.approved;

  bool get isRejected => moderationStatus == PostModerationStatus.rejected;

  bool get isReviewNeeded => moderationStatus == PostModerationStatus.reviewNeeded;

  bool get isOwnerVisibleModerationPost =>
      !isVisible &&
      (isProcessing || isRejected || isReviewNeeded);

  bool isOwnerVisibleModerationPostFor(
    String? viewerUserId, {
    bool isAdmin = false,
    DateTime? now,
  }) {
    if (!isOwnerVisibleModerationPost) return false;
    if (!isAdmin && viewerUserId != userId) return false;
    if (isRejected && ownerVisibleUntil != null) {
      return ownerVisibleUntil!.isAfter(now ?? DateTime.now());
    }
    return true;
  }

  PostModel copyWith({
    String? id,
    String? userId,
    String? userDisplayName,
    int? userAvatarIndex,
    String? content,
    String? imageUrl,
    List<MediaItem>? mediaItems,
    List<String>? mediaStoragePaths,
    String? postMode,
    String? circleId,
    DateTime? createdAt,
    Map<String, int>? reactions,
    int? commentCount,
    bool? isVisible,
    bool? isPinned,
    bool? isPinnedTop,
    bool? isFavorite,
    PostModerationStatus? moderationStatus,
    String? moderationReason,
    DateTime? moderationCompletedAt,
    DateTime? ownerVisibleUntil,
    bool? needsReview,
    String? needsReviewReason,
    bool? publishSideEffectsPending,
    bool? grantVirtueOnPublish,
    String? clientRequestId,
  }) {
    return PostModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userDisplayName: userDisplayName ?? this.userDisplayName,
      userAvatarIndex: userAvatarIndex ?? this.userAvatarIndex,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      mediaItems: mediaItems ?? this.mediaItems,
      mediaStoragePaths: mediaStoragePaths ?? this.mediaStoragePaths,
      postMode: postMode ?? this.postMode,
      circleId: circleId ?? this.circleId,
      createdAt: createdAt ?? this.createdAt,
      reactions: reactions ?? this.reactions,
      commentCount: commentCount ?? this.commentCount,
      isVisible: isVisible ?? this.isVisible,
      isPinned: isPinned ?? this.isPinned,
      isPinnedTop: isPinnedTop ?? this.isPinnedTop,
      isFavorite: isFavorite ?? this.isFavorite,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      moderationReason: moderationReason ?? this.moderationReason,
      moderationCompletedAt:
          moderationCompletedAt ?? this.moderationCompletedAt,
      ownerVisibleUntil: ownerVisibleUntil ?? this.ownerVisibleUntil,
      needsReview: needsReview ?? this.needsReview,
      needsReviewReason: needsReviewReason ?? this.needsReviewReason,
      publishSideEffectsPending:
          publishSideEffectsPending ?? this.publishSideEffectsPending,
      grantVirtueOnPublish:
          grantVirtueOnPublish ?? this.grantVirtueOnPublish,
      clientRequestId: clientRequestId ?? this.clientRequestId,
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

  static PostModerationStatus _parseModerationStatus(dynamic raw) {
    switch (raw) {
      case 'processing':
        return PostModerationStatus.processing;
      case 'rejected':
        return PostModerationStatus.rejected;
      case 'review_needed':
        return PostModerationStatus.reviewNeeded;
      case 'approved':
      default:
        return PostModerationStatus.approved;
    }
  }
}
