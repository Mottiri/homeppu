import 'package:cloud_firestore/cloud_firestore.dart';
import 'ban_record_model.dart';
import 'avatar_parts_model.dart';

class RewardedReactionUnlock {
  final int remaining;
  final DateTime expiresAt;

  const RewardedReactionUnlock({
    required this.remaining,
    required this.expiresAt,
  });

  factory RewardedReactionUnlock.fromMap(Map<String, dynamic> data) {
    final expiresRaw = data['expiresAt'];
    DateTime expiresAt;
    if (expiresRaw is Timestamp) {
      expiresAt = expiresRaw.toDate();
    } else if (expiresRaw is DateTime) {
      expiresAt = expiresRaw;
    } else {
      expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
    return RewardedReactionUnlock(
      remaining: (data['remaining'] as num?)?.toInt() ?? 0,
      expiresAt: expiresAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {'remaining': remaining, 'expiresAt': Timestamp.fromDate(expiresAt)};
  }
}

/// ユーザーモデル
class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String? bio;
  final int avatarIndex;
  final AvatarParts? avatarParts; // プリセットアバターのインデックス
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
  final List<String> unlockedReactionStamps; // アンロック済みリアクションスタンプID
  final List<String> unlockedAvatarParts; // アンロック済みアバターパーツID
  final List<String> unlockedStampSheets; // アンロック済みスタンプシートID
  final String? activeStampSheetId; // 現在使用中のスタンプシートID
  final int thanksStampCredits; // お礼スタンプの保有数
  final int stampSheetVersion; // スタンプシート同期バージョン
  final Map<String, RewardedReactionUnlock>
  rewardedReactionUnlocks; // 広告で一時解放されたリアクション
  final bool isSubscriber; // サブスク加入状態
  final DateTime? lastNameChangeAt; // 最後に名前を変更した日時
  final String? fcmToken; // プッシュ通知用トークン
  final Map<String, bool> notificationSettings; // 通知設定
  final String? headerImageUrl; // ヘッダー画像URL
  final int? headerImageIndex; // デフォルトヘッダー画像のインデックス（0-5）
  final int? headerPrimaryColor; // ヘッダー画像から抽出したメイン色（ARGB int）
  final int? headerSecondaryColor; // ヘッダー画像から抽出したサブ色（ARGB int）
  final String profileVisualMode; // 'icon' | 'avatar' | 'image'
  final String? profileImageUrl; // プロフィール画像URL
  final String? profileImageStoragePath; // プロフィール画像Storageパス
  final bool tutorialPhase1Completed; // 初回チュートリアルPhase1完了
  final String? tutorialPhase1Step; // チュートリアル進行ステップ（中断復帰用）

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.bio,
    this.avatarIndex = 0,
    this.avatarParts,
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
    this.unlockedReactionStamps = const [],
    this.unlockedAvatarParts = const [],
    this.unlockedStampSheets = const [],
    this.activeStampSheetId,
    this.thanksStampCredits = 0,
    this.stampSheetVersion = 0,
    this.rewardedReactionUnlocks = const {},
    this.isSubscriber = false,
    this.lastNameChangeAt,

    this.fcmToken,
    this.notificationSettings = const {'comments': true, 'reactions': true},
    this.headerImageUrl,
    this.headerImageIndex,
    this.headerPrimaryColor,
    this.headerSecondaryColor,
    this.profileVisualMode = 'icon',
    this.profileImageUrl,
    this.profileImageStoragePath,
    this.tutorialPhase1Completed = true,
    this.tutorialPhase1Step,
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
      avatarParts: AvatarParts.fromMap(data['avatarParts']),
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
      unlockedReactionStamps: List<String>.from(
        data['unlockedReactionStamps'] ?? [],
      ),
      unlockedAvatarParts: List<String>.from(data['unlockedAvatarParts'] ?? []),
      unlockedStampSheets: List<String>.from(data['unlockedStampSheets'] ?? []),
      activeStampSheetId: data['activeStampSheetId'],
      thanksStampCredits: data['thanksStampCredits'] ?? 0,
      stampSheetVersion: data['stampSheetVersion'] ?? 0,
      rewardedReactionUnlocks: _parseRewardedUnlocks(
        data['rewardedReactionUnlocks'],
      ),
      isSubscriber: data['isSubscriber'] ?? false,
      lastNameChangeAt: (data['lastNameChangeAt'] as Timestamp?)?.toDate(),

      fcmToken: data['fcmToken'],
      notificationSettings: Map<String, bool>.from(
        data['notificationSettings'] ?? {'comments': true, 'reactions': true},
      ),
      headerImageUrl: data['headerImageUrl'],
      headerImageIndex: data['headerImageIndex'],
      headerPrimaryColor: data['headerPrimaryColor'],
      headerSecondaryColor: data['headerSecondaryColor'],
      profileVisualMode: data['profileVisualMode'] ?? 'icon',
      profileImageUrl: data['profileImageUrl'],
      profileImageStoragePath: data['profileImageStoragePath'],
      tutorialPhase1Completed: data['tutorialPhase1Completed'] ?? false,
      tutorialPhase1Step: data['tutorialPhase1Step'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'bio': bio,
      'avatarIndex': avatarIndex,
      if (avatarParts != null) 'avatarParts': avatarParts!.toMap(),
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
      'unlockedReactionStamps': unlockedReactionStamps,
      'unlockedAvatarParts': unlockedAvatarParts,
      'unlockedStampSheets': unlockedStampSheets,
      'activeStampSheetId': activeStampSheetId,
      'thanksStampCredits': thanksStampCredits,
      'stampSheetVersion': stampSheetVersion,
      'rewardedReactionUnlocks': rewardedReactionUnlocks.map(
        (key, value) => MapEntry(key, value.toMap()),
      ),
      'isSubscriber': isSubscriber,
      if (lastNameChangeAt != null)
        'lastNameChangeAt': Timestamp.fromDate(lastNameChangeAt!),
      'notificationSettings': notificationSettings,
      if (headerImageUrl != null) 'headerImageUrl': headerImageUrl,
      if (headerImageIndex != null) 'headerImageIndex': headerImageIndex,
      if (headerPrimaryColor != null) 'headerPrimaryColor': headerPrimaryColor,
      if (headerSecondaryColor != null)
        'headerSecondaryColor': headerSecondaryColor,
      'profileVisualMode': profileVisualMode,
      if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      if (profileImageStoragePath != null)
        'profileImageStoragePath': profileImageStoragePath,
      'tutorialPhase1Completed': tutorialPhase1Completed,
      if (tutorialPhase1Step != null) 'tutorialPhase1Step': tutorialPhase1Step,
    };
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? bio,
    int? avatarIndex,
    AvatarParts? avatarParts,
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
    List<String>? unlockedReactionStamps,
    List<String>? unlockedAvatarParts,
    List<String>? unlockedStampSheets,
    String? activeStampSheetId,
    int? thanksStampCredits,
    int? stampSheetVersion,
    Map<String, RewardedReactionUnlock>? rewardedReactionUnlocks,
    bool? isSubscriber,
    DateTime? lastNameChangeAt,
    String? fcmToken,
    Map<String, bool>? notificationSettings,
    String? headerImageUrl,
    int? headerImageIndex,
    int? headerPrimaryColor,
    int? headerSecondaryColor,
    String? profileVisualMode,
    String? profileImageUrl,
    String? profileImageStoragePath,
    bool? tutorialPhase1Completed,
    String? tutorialPhase1Step,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarIndex: avatarIndex ?? this.avatarIndex,
      avatarParts: avatarParts ?? this.avatarParts,
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
      unlockedReactionStamps:
          unlockedReactionStamps ?? this.unlockedReactionStamps,
      unlockedAvatarParts: unlockedAvatarParts ?? this.unlockedAvatarParts,
      unlockedStampSheets: unlockedStampSheets ?? this.unlockedStampSheets,
      activeStampSheetId: activeStampSheetId ?? this.activeStampSheetId,
      thanksStampCredits: thanksStampCredits ?? this.thanksStampCredits,
      stampSheetVersion: stampSheetVersion ?? this.stampSheetVersion,
      rewardedReactionUnlocks:
          rewardedReactionUnlocks ?? this.rewardedReactionUnlocks,
      isSubscriber: isSubscriber ?? this.isSubscriber,
      lastNameChangeAt: lastNameChangeAt ?? this.lastNameChangeAt,
      fcmToken: fcmToken ?? this.fcmToken,
      notificationSettings: notificationSettings ?? this.notificationSettings,
      headerImageUrl: headerImageUrl ?? this.headerImageUrl,
      headerImageIndex: headerImageIndex ?? this.headerImageIndex,
      headerPrimaryColor: headerPrimaryColor ?? this.headerPrimaryColor,
      headerSecondaryColor: headerSecondaryColor ?? this.headerSecondaryColor,
      profileVisualMode: profileVisualMode ?? this.profileVisualMode,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      profileImageStoragePath:
          profileImageStoragePath ?? this.profileImageStoragePath,
      tutorialPhase1Completed:
          tutorialPhase1Completed ?? this.tutorialPhase1Completed,
      tutorialPhase1Step: tutorialPhase1Step ?? this.tutorialPhase1Step,
    );
  }
}

Map<String, RewardedReactionUnlock> _parseRewardedUnlocks(dynamic raw) {
  if (raw is! Map) return {};
  final data = Map<String, dynamic>.from(raw);
  final result = <String, RewardedReactionUnlock>{};
  data.forEach((key, value) {
    if (value is Map) {
      result[key] = RewardedReactionUnlock.fromMap(
        Map<String, dynamic>.from(value),
      );
    }
  });
  return result;
}
