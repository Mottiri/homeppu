import 'package:cloud_firestore/cloud_firestore.dart';

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
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
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
    );
  }
}
