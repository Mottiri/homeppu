import 'package:cloud_functions/cloud_functions.dart';
import '../models/task_model.dart';

class TaskService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-northeast1',
  );

  /// タスクを作成
  Future<String> createTask({
    required String content,
    required String emoji,
    required String type,
    DateTime? scheduledAt,
    int priority = 0,
    String? googleCalendarEventId,
  }) async {
    final callable = _functions.httpsCallable('createTask');
    final result = await callable.call({
      'content': content,
      'emoji': emoji,
      'type': type,
      'scheduledAt': scheduledAt?.toIso8601String(),
      'priority': priority,
      'googleCalendarEventId': googleCalendarEventId,
    });
    return result.data['taskId'];
  }

  /// タスクを更新
  Future<void> updateTask(TaskModel task) async {
    final callable = _functions.httpsCallable('updateTask');
    await callable.call({
      'taskId': task.id,
      'content': task.content,
      'emoji': task.emoji,
      'type': task.type,
      'scheduledAt': task.scheduledAt?.toIso8601String(),
      'priority': task.priority,
      'googleCalendarEventId': task.googleCalendarEventId,
      'subtasks': task.subtasks.map((e) => e.toMap()).toList(),
    });
  }

  /// タスクを完了
  Future<TaskCompleteResult> completeTask(String taskId) async {
    final callable = _functions.httpsCallable('completeTask');
    final result = await callable.call({'taskId': taskId});
    return TaskCompleteResult(
      success: result.data['success'] ?? false,
      virtueGain: result.data['virtueGain'] ?? 0,
      newVirtue: result.data['newVirtue'] ?? 0,
      streak: result.data['streak'] ?? 0,
      streakBonus: result.data['streakBonus'] ?? 0,
    );
  }

  /// タスクを削除
  Future<void> deleteTask(String taskId) async {
    final callable = _functions.httpsCallable('deleteTask');
    await callable.call({'taskId': taskId});
  }

  /// タスクの完了を取り消し（徳ポイントも減らす）
  Future<TaskUncompleteResult> uncompleteTask(String taskId) async {
    final callable = _functions.httpsCallable('uncompleteTask');
    final result = await callable.call({'taskId': taskId});
    return TaskUncompleteResult(
      success: result.data['success'] ?? false,
      virtueLoss: result.data['virtueLoss'] ?? 0,
      newVirtue: result.data['newVirtue'] ?? 0,
      message: result.data['message'],
    );
  }

  /// タスク一覧を取得
  Future<List<TaskModel>> getTasks({String? type}) async {
    final callable = _functions.httpsCallable('getTasks');
    final result = await callable.call({'type': type});
    final tasks = (result.data['tasks'] as List)
        .map((task) => TaskModel.fromMap(Map<String, dynamic>.from(task)))
        .toList();
    return tasks;
  }
}

class TaskCompleteResult {
  final bool success;
  final int virtueGain;
  final int newVirtue;
  final int streak;
  final int streakBonus;

  TaskCompleteResult({
    required this.success,
    required this.virtueGain,
    required this.newVirtue,
    required this.streak,
    required this.streakBonus,
  });
}

class TaskUncompleteResult {
  final bool success;
  final int virtueLoss;
  final int newVirtue;
  final String? message;

  TaskUncompleteResult({
    required this.success,
    required this.virtueLoss,
    required this.newVirtue,
    this.message,
  });
}
