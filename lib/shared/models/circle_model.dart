import 'package:cloud_firestore/cloud_firestore.dart';

/// サークル（コミュニティ）モデル
class CircleModel {
  final String id;
  final String name;
  final String description;
  final String ownerId;
  final int iconIndex;          // プリセットアイコンのインデックス
  final bool allowAI;           // AIの参加を許可するか
  final List<String> memberIds;
  final int memberCount;
  final DateTime createdAt;
  final bool isPublic;

  CircleModel({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    this.iconIndex = 0,
    this.allowAI = true,
    this.memberIds = const [],
    this.memberCount = 0,
    required this.createdAt,
    this.isPublic = true,
  });

  factory CircleModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CircleModel(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      ownerId: data['ownerId'] ?? '',
      iconIndex: data['iconIndex'] ?? 0,
      allowAI: data['allowAI'] ?? true,
      memberIds: List<String>.from(data['memberIds'] ?? []),
      memberCount: data['memberCount'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isPublic: data['isPublic'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'ownerId': ownerId,
      'iconIndex': iconIndex,
      'allowAI': allowAI,
      'memberIds': memberIds,
      'memberCount': memberCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'isPublic': isPublic,
    };
  }

  CircleModel copyWith({
    String? id,
    String? name,
    String? description,
    String? ownerId,
    int? iconIndex,
    bool? allowAI,
    List<String>? memberIds,
    int? memberCount,
    DateTime? createdAt,
    bool? isPublic,
  }) {
    return CircleModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      ownerId: ownerId ?? this.ownerId,
      iconIndex: iconIndex ?? this.iconIndex,
      allowAI: allowAI ?? this.allowAI,
      memberIds: memberIds ?? this.memberIds,
      memberCount: memberCount ?? this.memberCount,
      createdAt: createdAt ?? this.createdAt,
      isPublic: isPublic ?? this.isPublic,
    );
  }
}


