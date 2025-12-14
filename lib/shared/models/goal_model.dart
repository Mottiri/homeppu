import 'package:cloud_firestore/cloud_firestore.dart';

class GoalModel {
  final String id;
  final String userId;
  final String title;
  final String? description;
  final DateTime? deadline;
  final int colorValue; // ARGB int value
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt; // If not null, goal is completed (Archived)
  final bool isPublic;

  GoalModel({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.deadline,
    required this.colorValue,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.isPublic = false, // Defaults to private, but tasks can inherit this
  });

  bool get isCompleted => completedAt != null;

  factory GoalModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GoalModel.fromMap({...data, 'id': doc.id});
  }

  factory GoalModel.fromMap(Map<String, dynamic> data) {
    return GoalModel(
      id: data['id'] ?? '',
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'],
      deadline: data['deadline'] != null
          ? (data['deadline'] is Timestamp
                ? (data['deadline'] as Timestamp).toDate()
                : DateTime.parse(data['deadline'].toString()))
          : null,
      colorValue: data['colorValue'] ?? 0xFF2196F3, // Default Blue
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] is Timestamp
                ? (data['createdAt'] as Timestamp).toDate()
                : DateTime.parse(data['createdAt'].toString()))
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] is Timestamp
                ? (data['updatedAt'] as Timestamp).toDate()
                : DateTime.parse(data['updatedAt'].toString()))
          : DateTime.now(),
      completedAt: data['completedAt'] != null
          ? (data['completedAt'] is Timestamp
                ? (data['completedAt'] as Timestamp).toDate()
                : DateTime.parse(data['completedAt'].toString()))
          : null,
      isPublic: data['isPublic'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'description': description,
      'deadline': deadline,
      'colorValue': colorValue,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'completedAt': completedAt,
      'isPublic': isPublic,
    };
  }

  GoalModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    DateTime? deadline,
    int? colorValue,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool? isPublic,
    bool forceClearCompletedAt = false, // Helper to un-complete
  }) {
    return GoalModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      deadline: deadline ?? this.deadline,
      colorValue: colorValue ?? this.colorValue,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: forceClearCompletedAt
          ? null
          : (completedAt ?? this.completedAt),
      isPublic: isPublic ?? this.isPublic,
    );
  }
}
