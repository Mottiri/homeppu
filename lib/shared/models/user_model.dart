import 'package:cloud_firestore/cloud_firestore.dart';

/// ユーザーモデル
class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String? bio;
  final int avatarIndex;        // プリセットアバターのインデックス
  final String postMode;        // 'ai', 'mix', 'human'
  final int virtue;             // 徳ポイント
  final bool isAI;              // AIアカウントかどうか
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isBanned;
  final int totalPosts;
  final int totalPraises;       // 受け取った称賛の数
  final List<String> following; // フォロー中のユーザーID
  final List<String> followers; // フォロワーのユーザーID
  final int followingCount;
  final int followersCount;
  final int reportCount;          // 通報された回数

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.bio,
    this.avatarIndex = 0,
    this.postMode = 'mix',
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
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? 'ゲスト',
      bio: data['bio'],
      avatarIndex: data['avatarIndex'] ?? 0,
      postMode: data['postMode'] ?? 'mix',
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
    );
  }
}
