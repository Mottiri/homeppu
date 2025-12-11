import 'package:cloud_firestore/cloud_firestore.dart';

// サブタスク（チェックリストアイテム）
class TaskItem {
  final String id;
  final String title;
  final bool isCompleted;

  TaskItem({required this.id, required this.title, this.isCompleted = false});

  Map<String, dynamic> toMap() {
    return {'id': id, 'title': title, 'isCompleted': isCompleted};
  }

  factory TaskItem.fromMap(Map<String, dynamic> map) {
    return TaskItem(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      isCompleted: map['isCompleted'] ?? false,
    );
  }

  TaskItem copyWith({String? id, String? title, bool? isCompleted}) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

class TaskModel {
  final String id;
  final String userId;
  final String content;
  final String emoji;
  final String type; // 'daily', 'todo', 'goal'
  final bool isCompleted;
  final bool isCompletedToday;
  final int streak;
  final DateTime? lastCompletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPublic;
  final List<String> shareToCircleIds;

  // New Fields
  final DateTime? scheduledAt; // 予定日時 (for 'todo')
  final String? googleCalendarEventId; // Googleカレンダー連携ID
  final int priority; // 0:低, 1:中, 2:高
  final List<TaskItem> subtasks; // サブタスク

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
    this.isPublic = false,
    this.shareToCircleIds = const [],
    this.scheduledAt,
    this.googleCalendarEventId,
    this.priority = 0,
    this.subtasks = const [],
  });

  factory TaskModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TaskModel.fromMap({...data, 'id': doc.id});
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
          ? (data['lastCompletedAt'] is Timestamp
                ? (data['lastCompletedAt'] as Timestamp).toDate()
                : DateTime.parse(data['lastCompletedAt'].toString()))
          : null,
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
      isPublic: data['isPublic'] ?? false,
      shareToCircleIds: List<String>.from(data['shareToCircleIds'] ?? []),
      scheduledAt: data['scheduledAt'] != null
          ? (data['scheduledAt'] is Timestamp
                ? (data['scheduledAt'] as Timestamp).toDate()
                : DateTime.parse(data['scheduledAt'].toString()))
          : null,
      googleCalendarEventId: data['googleCalendarEventId'],
      priority: data['priority'] ?? 0,
      subtasks:
          (data['subtasks'] as List<dynamic>?)
              ?.map((item) => TaskItem.fromMap(item))
              .toList() ??
          [],
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
      'isPublic': isPublic,
      'shareToCircleIds': shareToCircleIds,
      'scheduledAt': scheduledAt,
      'googleCalendarEventId': googleCalendarEventId,
      'priority': priority,
      'subtasks': subtasks.map((e) => e.toMap()).toList(),
    };
  }

  TaskModel copyWith({
    String? id,
    String? userId,
    String? content,
    String? emoji,
    String? type,
    bool? isCompleted,
    bool? isCompletedToday,
    int? streak,
    DateTime? lastCompletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPublic,
    List<String>? shareToCircleIds,
    DateTime? scheduledAt,
    String? googleCalendarEventId,
    int? priority,
    List<TaskItem>? subtasks,
  }) {
    return TaskModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      content: content ?? this.content,
      emoji: emoji ?? this.emoji,
      type: type ?? this.type,
      isCompleted: isCompleted ?? this.isCompleted,
      isCompletedToday: isCompletedToday ?? this.isCompletedToday,
      streak: streak ?? this.streak,
      lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPublic: isPublic ?? this.isPublic,
      shareToCircleIds: shareToCircleIds ?? this.shareToCircleIds,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      googleCalendarEventId:
          googleCalendarEventId ?? this.googleCalendarEventId,
      priority: priority ?? this.priority,
      subtasks: subtasks ?? this.subtasks,
    );
  }

  bool get isDaily => type == 'daily';
  bool get isTodo => type == 'todo';
  bool get isGoal => type == 'goal';

  // サブタスクの完了数
  int get completedSubtaskCount => subtasks.where((s) => s.isCompleted).length;
  // サブタスクの進捗率 (0.0 - 1.0)
  double get progress => subtasks.isEmpty
      ? (isCompleted ? 1.0 : 0.0)
      : completedSubtaskCount / subtasks.length;
}
