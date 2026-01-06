import 'package:cloud_firestore/cloud_firestore.dart';
import 'ban_record_model.dart';

/// ユーザーモデル
class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String? bio;
  final int avatarIndex; // プリセットアバターのインデックス
  final String postMode; // 'ai', 'mix', 'human'
  final int virtue; // 徳ポイント
  final bool isAI; // AIアカウントかどうか
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isBanned;
  final String banStatus; // 'none', 'temporary', 'permanent'
  final List<BanRecordModel> banHistory;
  final DateTime? permanentBanScheduledDeletionAt;
  final int warningCount; // 一時BAN解除後の警告回数
  final int totalPosts;
  final int totalPraises; // 受け取った称賛の数
  final List<String> following; // フォロー中のユーザーID
  final List<String> followers; // フォロワーのユーザーID
  final int followingCount;
  final int followersCount;
  final int reportCount; // 通報された回数
  // 名前パーツ方式
  final String? namePrefix; // 形容詞パーツのID
  final String? nameSuffix; // 名詞パーツのID
  final List<String> unlockedNameParts; // アンロック済みパーツID
  final DateTime? lastNameChangeAt; // 最後に名前を変更した日時
  final String? fcmToken; // プッシュ通知用トークン
  final Map<String, bool> notificationSettings; // 通知設定
  final Map<String, bool> autoPostSettings; // 自動投稿設定
  final String? headerImageUrl; // ヘッダー画像URL
  final int? headerImageIndex; // デフォルトヘッダー画像のインデックス（0-5）
  final int? headerPrimaryColor; // ヘッダー画像から抽出したメイン色（ARGB int）
  final int? headerSecondaryColor; // ヘッダー画像から抽出したサブ色（ARGB int）

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.bio,
    this.avatarIndex = 0,
    this.postMode = 'ai', // デフォルトはAIモード（安心スタート）
    this.virtue = 100,
    this.isAI = false,
    required this.createdAt,
    required this.updatedAt,
    this.isBanned = false,
    this.banStatus = 'none',
    this.banHistory = const [],
    this.permanentBanScheduledDeletionAt,
    this.warningCount = 0,
    this.totalPosts = 0,
    this.totalPraises = 0,
    this.following = const [],
    this.followers = const [],
    this.followingCount = 0,
    this.followersCount = 0,
    this.reportCount = 0,
    this.namePrefix,
    this.nameSuffix,
    this.unlockedNameParts = const [],
    this.lastNameChangeAt,

    this.fcmToken,
    this.notificationSettings = const {'comments': true, 'reactions': true},
    this.autoPostSettings = const {'milestones': true, 'goals': true},
    this.headerImageUrl,
    this.headerImageIndex,
    this.headerPrimaryColor,
    this.headerSecondaryColor,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // BAN履歴の変換
    List<BanRecordModel> banHistory = [];
    if (data['banHistory'] != null) {
      banHistory = (data['banHistory'] as List)
          .map((item) => BanRecordModel.fromFirestore(item))
          .toList();
    }

    return UserModel(
      uid: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? 'ゲスト',
      bio: data['bio'],
      avatarIndex: data['avatarIndex'] ?? 0,
      postMode: data['postMode'] ?? 'ai', // デフォルトはAIモード
      virtue: data['virtue'] ?? 100,
      isAI: data['isAI'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isBanned: data['isBanned'] ?? false,
      banStatus: data['banStatus'] ?? 'none',
      banHistory: banHistory,
      permanentBanScheduledDeletionAt:
          (data['permanentBanScheduledDeletionAt'] as Timestamp?)?.toDate(),
      warningCount: data['warningCount'] ?? 0,
      totalPosts: data['totalPosts'] ?? 0,
      totalPraises: data['totalPraises'] ?? 0,
      following: List<String>.from(data['following'] ?? []),
      followers: List<String>.from(data['followers'] ?? []),
      followingCount: data['followingCount'] ?? 0,
      followersCount: data['followersCount'] ?? 0,
      reportCount: data['reportCount'] ?? 0,
      namePrefix: data['namePrefix'],
      nameSuffix: data['nameSuffix'],
      unlockedNameParts: List<String>.from(data['unlockedNameParts'] ?? []),
      lastNameChangeAt: (data['lastNameChangeAt'] as Timestamp?)?.toDate(),

      fcmToken: data['fcmToken'],
      notificationSettings: Map<String, bool>.from(
        data['notificationSettings'] ?? {'comments': true, 'reactions': true},
      ),
      autoPostSettings: Map<String, bool>.from(
        data['autoPostSettings'] ?? {'milestones': true, 'goals': true},
      ),
      headerImageUrl: data['headerImageUrl'],
      headerImageIndex: data['headerImageIndex'],
      headerPrimaryColor: data['headerPrimaryColor'],
      headerSecondaryColor: data['headerSecondaryColor'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'bio': bio,
      'avatarIndex': avatarIndex,
      'postMode': postMode,
      'virtue': virtue,
      'isAI': isAI,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isBanned': isBanned,
      'banStatus': banStatus,
      'banHistory': banHistory.map((e) => e.toFirestore()).toList(),
      if (permanentBanScheduledDeletionAt != null)
        'permanentBanScheduledDeletionAt': Timestamp.fromDate(
          permanentBanScheduledDeletionAt!,
        ),
      'warningCount': warningCount,
      'totalPosts': totalPosts,
      'totalPraises': totalPraises,
      'following': following,
      'followers': followers,
      'followingCount': followingCount,
      'followersCount': followersCount,
      'reportCount': reportCount,
      'namePrefix': namePrefix,
      'nameSuffix': nameSuffix,
      'unlockedNameParts': unlockedNameParts,
      if (lastNameChangeAt != null)
        'lastNameChangeAt': Timestamp.fromDate(lastNameChangeAt!),
      'notificationSettings': notificationSettings,
      'autoPostSettings': autoPostSettings,
      if (headerImageUrl != null) 'headerImageUrl': headerImageUrl,
      if (headerImageIndex != null) 'headerImageIndex': headerImageIndex,
      if (headerPrimaryColor != null) 'headerPrimaryColor': headerPrimaryColor,
      if (headerSecondaryColor != null)
        'headerSecondaryColor': headerSecondaryColor,
    };
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? bio,
    int? avatarIndex,
    String? postMode,
    int? virtue,
    bool? isAI,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isBanned,
    String? banStatus,
    List<BanRecordModel>? banHistory,
    DateTime? permanentBanScheduledDeletionAt,
    int? warningCount,
    int? totalPosts,
    int? totalPraises,
    List<String>? following,
    List<String>? followers,
    int? followingCount,
    int? followersCount,
    int? reportCount,
    String? namePrefix,
    String? nameSuffix,
    List<String>? unlockedNameParts,
    DateTime? lastNameChangeAt,
    String? fcmToken,
    Map<String, bool>? notificationSettings,
    Map<String, bool>? autoPostSettings,
    String? headerImageUrl,
    int? headerImageIndex,
    int? headerPrimaryColor,
    int? headerSecondaryColor,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarIndex: avatarIndex ?? this.avatarIndex,
      postMode: postMode ?? this.postMode,
      virtue: virtue ?? this.virtue,
      isAI: isAI ?? this.isAI,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isBanned: isBanned ?? this.isBanned,
      banStatus: banStatus ?? this.banStatus,
      banHistory: banHistory ?? this.banHistory,
      permanentBanScheduledDeletionAt:
          permanentBanScheduledDeletionAt ??
          this.permanentBanScheduledDeletionAt,
      warningCount: warningCount ?? this.warningCount,
      totalPosts: totalPosts ?? this.totalPosts,
      totalPraises: totalPraises ?? this.totalPraises,
      following: following ?? this.following,
      followers: followers ?? this.followers,
      followingCount: followingCount ?? this.followingCount,
      followersCount: followersCount ?? this.followersCount,
      reportCount: reportCount ?? this.reportCount,
      namePrefix: namePrefix ?? this.namePrefix,
      nameSuffix: nameSuffix ?? this.nameSuffix,
      unlockedNameParts: unlockedNameParts ?? this.unlockedNameParts,
      lastNameChangeAt: lastNameChangeAt ?? this.lastNameChangeAt,
      fcmToken: fcmToken ?? this.fcmToken,
      notificationSettings: notificationSettings ?? this.notificationSettings,
      autoPostSettings: autoPostSettings ?? this.autoPostSettings,
      headerImageUrl: headerImageUrl ?? this.headerImageUrl,
      headerImageIndex: headerImageIndex ?? this.headerImageIndex,
      headerPrimaryColor: headerPrimaryColor ?? this.headerPrimaryColor,
      headerSecondaryColor: headerSecondaryColor ?? this.headerSecondaryColor,
    );
  }
}
