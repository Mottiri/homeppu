import 'package:cloud_firestore/cloud_firestore.dart';

enum CircleAIMode { aiOnly, mix, humanOnly }

class CircleModel {
  final String id;
  final String name;
  final String description;
  final String category;
  final String ownerId;
  final String? subOwnerId;
  final List<String> memberIds;
  final CircleAIMode aiMode;
  final List<Map<String, dynamic>> generatedAIs;
  final bool isPublic;
  final int maxMembers;
  final DateTime createdAt;
  final DateTime? recentActivity;
  final DateTime? lastHumanPostAt;
  final String goal;
  final String? coverImageUrl;
  final String? coverImageStoragePath;
  final String? iconImageUrl;
  final String? iconImageStoragePath;
  final int memberCount;
  final int postCount;
  final String? rules;
  final bool isDeleted;

  CircleModel({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.ownerId,
    this.subOwnerId,
    required this.memberIds,
    required this.aiMode,
    this.generatedAIs = const [],
    this.isPublic = true,
    this.maxMembers = 20,
    required this.createdAt,
    this.recentActivity,
    this.lastHumanPostAt,
    required this.goal,
    this.coverImageUrl,
    this.coverImageStoragePath,
    this.iconImageUrl,
    this.iconImageStoragePath,
    this.memberCount = 0,
    this.postCount = 0,
    this.rules,
    this.isDeleted = false,
  });

  factory CircleModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CircleModel(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      category: data['category'] ?? 'その他',
      ownerId: data['ownerId'] ?? '',
      subOwnerId: data['subOwnerId'],
      memberIds: List<String>.from(data['memberIds'] ?? []),
      aiMode: CircleAIMode.values.firstWhere(
        (e) => e.name == (data['aiMode'] ?? 'mix'),
        orElse: () => CircleAIMode.mix,
      ),
      generatedAIs: List<Map<String, dynamic>>.from(data['generatedAIs'] ?? []),
      isPublic: data['isPublic'] ?? true,
      maxMembers: data['maxMembers'] ?? 20,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      recentActivity: (data['recentActivity'] as Timestamp?)?.toDate(),
      lastHumanPostAt: (data['lastHumanPostAt'] as Timestamp?)?.toDate(),
      goal: data['goal'] ?? '',
      coverImageUrl: data['coverImageUrl'],
      coverImageStoragePath: data['coverImageStoragePath'],
      iconImageUrl: data['iconImageUrl'],
      iconImageStoragePath: data['iconImageStoragePath'],
      memberCount: data['memberCount'] ?? 0,
      postCount: data['postCount'] ?? 0,
      rules: data['rules'],
      isDeleted: data['isDeleted'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'category': category,
      'ownerId': ownerId,
      'subOwnerId': subOwnerId,
      'memberIds': memberIds,
      'aiMode': aiMode.name,
      'generatedAIs': generatedAIs,
      'isPublic': isPublic,
      'maxMembers': maxMembers,
      'createdAt': Timestamp.fromDate(createdAt),
      'recentActivity': recentActivity != null
          ? Timestamp.fromDate(recentActivity!)
          : null,
      'lastHumanPostAt': lastHumanPostAt != null
          ? Timestamp.fromDate(lastHumanPostAt!)
          : null,
      'goal': goal,
      'coverImageUrl': coverImageUrl,
      'coverImageStoragePath': coverImageStoragePath,
      'iconImageUrl': iconImageUrl,
      'iconImageStoragePath': iconImageStoragePath,
      'memberCount': memberCount,
      'postCount': postCount,
      'rules': rules,
      'isDeleted': isDeleted,
    };
  }

  CircleModel copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    String? ownerId,
    String? subOwnerId,
    List<String>? memberIds,
    CircleAIMode? aiMode,
    List<Map<String, dynamic>>? generatedAIs,
    bool? isPublic,
    int? maxMembers,
    DateTime? createdAt,
    DateTime? recentActivity,
    DateTime? lastHumanPostAt,
    String? goal,
    String? coverImageUrl,
    String? coverImageStoragePath,
    String? iconImageUrl,
    String? iconImageStoragePath,
    int? memberCount,
    int? postCount,
    String? rules,
    bool? isDeleted,
  }) {
    return CircleModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      ownerId: ownerId ?? this.ownerId,
      subOwnerId: subOwnerId ?? this.subOwnerId,
      memberIds: memberIds ?? this.memberIds,
      aiMode: aiMode ?? this.aiMode,
      generatedAIs: generatedAIs ?? this.generatedAIs,
      isPublic: isPublic ?? this.isPublic,
      maxMembers: maxMembers ?? this.maxMembers,
      createdAt: createdAt ?? this.createdAt,
      recentActivity: recentActivity ?? this.recentActivity,
      lastHumanPostAt: lastHumanPostAt ?? this.lastHumanPostAt,
      goal: goal ?? this.goal,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      coverImageStoragePath:
          coverImageStoragePath ?? this.coverImageStoragePath,
      iconImageUrl: iconImageUrl ?? this.iconImageUrl,
      iconImageStoragePath: iconImageStoragePath ?? this.iconImageStoragePath,
      memberCount: memberCount ?? this.memberCount,
      postCount: postCount ?? this.postCount,
      rules: rules ?? this.rules,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
