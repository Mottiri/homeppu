import 'package:cloud_firestore/cloud_firestore.dart';

class TaskModel {
  final String id;
  final String userId;
  final String content;
  final String emoji;
  final String type; // 'daily' or 'goal'
  final bool isCompleted;
  final bool isCompletedToday;
  final int streak;
  final DateTime? lastCompletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  TaskModel({
    required this.id,
    required this.userId,
    required this.content,
    required this.emoji,
    required this.type,
    required this.isCompleted,
    this.isCompletedToday = false,
    this.streak = 0,
    this.lastCompletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TaskModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TaskModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      content: data['content'] ?? '',
      emoji: data['emoji'] ?? '✨',
      type: data['type'] ?? 'daily',
      isCompleted: data['isCompleted'] ?? false,
      isCompletedToday: data['isCompletedToday'] ?? false,
      streak: data['streak'] ?? 0,
      lastCompletedAt: data['lastCompletedAt'] != null
          ? (data['lastCompletedAt'] as Timestamp).toDate()
          : null,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  factory TaskModel.fromMap(Map<String, dynamic> data) {
    return TaskModel(
      id: data['id'] ?? '',
      userId: data['userId'] ?? '',
      content: data['content'] ?? '',
      emoji: data['emoji'] ?? '✨',
      type: data['type'] ?? 'daily',
      isCompleted: data['isCompleted'] ?? false,
      isCompletedToday: data['isCompletedToday'] ?? false,
      streak: data['streak'] ?? 0,
      lastCompletedAt: data['lastCompletedAt'] != null
          ? DateTime.parse(data['lastCompletedAt'])
          : null,
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'])
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? DateTime.parse(data['updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'content': content,
      'emoji': emoji,
      'type': type,
      'isCompleted': isCompleted,
      'streak': streak,
      'lastCompletedAt': lastCompletedAt,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  bool get isDaily => type == 'daily';
  bool get isGoal => type == 'goal';
}


