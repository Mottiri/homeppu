import 'package:cloud_firestore/cloud_firestore.dart';

enum CircleAIMode { aiOnly, mix, humanOnly }

class CircleModel {
  final String id;
  final String name;
  final String description;
  final String category;
  final String ownerId;
  final List<String> memberIds;
  final CircleAIMode aiMode;
  final List<Map<String, dynamic>> generatedAIs; // AI persona data
  final bool isPublic;
  final int maxMembers;
  final DateTime createdAt;
  final DateTime? recentActivity;
  final String goal;
  final String? coverImageUrl;
  final String? iconImageUrl;
  final int memberCount;
  final int postCount;
  final String? rules; // サークルルール（500文字以内）

  CircleModel({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.ownerId,
    required this.memberIds,
    required this.aiMode,
    this.generatedAIs = const [],
    this.isPublic = true,
    this.maxMembers = 20,
    required this.createdAt,
    this.recentActivity,
    required this.goal,
    this.coverImageUrl,
    this.iconImageUrl,
    this.memberCount = 0,
    this.postCount = 0,
    this.rules,
  });

  factory CircleModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CircleModel(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      category: data['category'] ?? 'その他',
      ownerId: data['ownerId'] ?? '',
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
      goal: data['goal'] ?? '',
      coverImageUrl: data['coverImageUrl'],
      iconImageUrl: data['iconImageUrl'],
      memberCount: data['memberCount'] ?? 0,
      postCount: data['postCount'] ?? 0,
      rules: data['rules'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'category': category,
      'ownerId': ownerId,
      'memberIds': memberIds,
      'aiMode': aiMode.name,
      'generatedAIs': generatedAIs,
      'isPublic': isPublic,
      'maxMembers': maxMembers,
      'createdAt': Timestamp.fromDate(createdAt),
      'recentActivity': recentActivity != null
          ? Timestamp.fromDate(recentActivity!)
          : null,
      'goal': goal,
      'coverImageUrl': coverImageUrl,
      'iconImageUrl': iconImageUrl,
      'memberCount': memberCount,
      'postCount': postCount,
      'rules': rules,
    };
  }

  CircleModel copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    String? ownerId,
    List<String>? memberIds,
    CircleAIMode? aiMode,
    List<Map<String, dynamic>>? generatedAIs,
    bool? isPublic,
    int? maxMembers,
    DateTime? createdAt,
    DateTime? recentActivity,
    String? goal,
    String? coverImageUrl,
    String? iconImageUrl,
    int? memberCount,
    int? postCount,
    String? rules,
  }) {
    return CircleModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      ownerId: ownerId ?? this.ownerId,
      memberIds: memberIds ?? this.memberIds,
      aiMode: aiMode ?? this.aiMode,
      generatedAIs: generatedAIs ?? this.generatedAIs,
      isPublic: isPublic ?? this.isPublic,
      maxMembers: maxMembers ?? this.maxMembers,
      createdAt: createdAt ?? this.createdAt,
      recentActivity: recentActivity ?? this.recentActivity,
      goal: goal ?? this.goal,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      iconImageUrl: iconImageUrl ?? this.iconImageUrl,
      memberCount: memberCount ?? this.memberCount,
      postCount: postCount ?? this.postCount,
      rules: rules ?? this.rules,
    );
  }
}
