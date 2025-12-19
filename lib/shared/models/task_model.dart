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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskItem &&
        other.id == id &&
        other.title == title &&
        other.isCompleted == isCompleted;
  }

  @override
  int get hashCode => id.hashCode ^ title.hashCode ^ isCompleted.hashCode;
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
  final String? categoryId; // カスタムカテゴリID

  // Recurrence Fields
  final String? recurrenceGroupId; // 繰り返しグループID
  final int? recurrenceInterval; // 繰り返しの間隔
  final String? recurrenceUnit; // 'daily', 'weekly', 'monthly', 'yearly'
  final List<int>? recurrenceDaysOfWeek; // 週次の場合の曜日 (1=Mon ... 7=Sun)
  final DateTime? recurrenceEndDate; // 繰り返しの終了日
  // Attachments & Memo
  final String? memo;
  final List<String> attachmentUrls;
  final String? goalId;

  // Reminders - [{value: 30, unit: 'minutes'}, ...]
  final List<Map<String, dynamic>> reminders;

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
    this.categoryId,
    this.recurrenceGroupId,
    this.recurrenceInterval,
    this.recurrenceUnit,
    this.recurrenceDaysOfWeek,
    this.recurrenceEndDate,
    this.memo,
    this.attachmentUrls = const [],
    this.goalId,
    this.reminders = const [],
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
          (data['subtasks'] as List<dynamic>?)?.map((item) {
            if (item is Map) {
              return TaskItem.fromMap(Map<String, dynamic>.from(item));
            }
            return TaskItem(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              title: '',
            );
          }).toList() ??
          [],
      categoryId: data['categoryId'],
      recurrenceGroupId: data['recurrenceGroupId'],
      recurrenceInterval: data['recurrenceInterval'],
      recurrenceUnit: data['recurrenceUnit'],
      recurrenceDaysOfWeek: data['recurrenceDaysOfWeek'] != null
          ? List<int>.from(data['recurrenceDaysOfWeek'])
          : null,
      recurrenceEndDate: data['recurrenceEndDate'] != null
          ? (data['recurrenceEndDate'] is Timestamp
                ? (data['recurrenceEndDate'] as Timestamp).toDate()
                : DateTime.parse(data['recurrenceEndDate'].toString()))
          : null,
      memo: data['memo'],
      attachmentUrls: List<String>.from(data['attachmentUrls'] ?? []),
      goalId: data['goalId'],
      reminders:
          (data['reminders'] as List<dynamic>?)
              ?.map((r) => Map<String, dynamic>.from(r as Map))
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
      'categoryId': categoryId,
      'recurrenceGroupId': recurrenceGroupId,
      'recurrenceInterval': recurrenceInterval,
      'recurrenceUnit': recurrenceUnit,
      'recurrenceDaysOfWeek': recurrenceDaysOfWeek,
      'recurrenceEndDate': recurrenceEndDate,
      'memo': memo,
      'attachmentUrls': attachmentUrls,
      'goalId': goalId,
      'reminders': reminders,
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
    String? categoryId,
    String? recurrenceGroupId,
    int? recurrenceInterval,
    String? recurrenceUnit,
    List<int>? recurrenceDaysOfWeek,
    DateTime? recurrenceEndDate,
    String? memo,
    List<String>? attachmentUrls,
    String? goalId,
    List<Map<String, dynamic>>? reminders,
    bool clearRecurrence = false, // 繰り返し設定をクリアするフラグ
    bool clearCategoryId = false, // カテゴリをnullに戻すフラグ
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
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      // recurrenceGroupIdはupdateTaskでクエリに使用するため、ここではクリアしない
      recurrenceGroupId: recurrenceGroupId ?? this.recurrenceGroupId,
      recurrenceInterval: clearRecurrence
          ? null
          : (recurrenceInterval ?? this.recurrenceInterval),
      recurrenceUnit: clearRecurrence
          ? null
          : (recurrenceUnit ?? this.recurrenceUnit),
      recurrenceDaysOfWeek: clearRecurrence
          ? null
          : (recurrenceDaysOfWeek ?? this.recurrenceDaysOfWeek),
      recurrenceEndDate: clearRecurrence
          ? null
          : (recurrenceEndDate ?? this.recurrenceEndDate),
      memo: memo ?? this.memo,
      attachmentUrls: attachmentUrls ?? this.attachmentUrls,
      goalId: goalId ?? this.goalId,
      reminders: reminders ?? this.reminders,
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
