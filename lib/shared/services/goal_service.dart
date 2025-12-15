import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/goal_model.dart';
import '../models/task_model.dart';

class GoalService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection Reference
  CollectionReference<Map<String, dynamic>> get _goalsCollection =>
      _firestore.collection('goals');

  CollectionReference<Map<String, dynamic>> get _tasksCollection =>
      _firestore.collection('tasks');

  // Create
  Future<void> createGoal(GoalModel goal) async {
    await _goalsCollection.doc(goal.id).set(goal.toMap());
  }

  // Update
  Future<void> updateGoal(GoalModel goal) async {
    await _goalsCollection.doc(goal.id).update(goal.toMap());
  }

  // Delete (Cascade)
  Future<void> deleteGoal(String goalId, String userId) async {
    final batch = _firestore.batch();

    // 1. Delete the Goal
    batch.delete(_goalsCollection.doc(goalId));

    // 2. Delete all linked Tasks
    // userIdフィルターを追加してセキュリティルールを満たす
    try {
      final linkedTasksSnapshot = await _tasksCollection
          .where('userId', isEqualTo: userId)
          .where('goalId', isEqualTo: goalId)
          .get();

      for (var doc in linkedTasksSnapshot.docs) {
        batch.delete(doc.reference);
      }
    } catch (e) {
      // タスク削除に失敗してもgoal削除は続行
      print('Warning: Could not delete linked tasks: $e');
    }

    await batch.commit();
  }

  // Toggle Complete
  Future<void> toggleComplete(
    GoalModel goal, {
    bool isCompleted = true,
    bool deleteFutureTasks = false,
  }) async {
    // 1. Update Goal Status
    final updatedGoal = goal.copyWith(
      completedAt: isCompleted ? DateTime.now() : null,
      forceClearCompletedAt: !isCompleted,
    );
    await _goalsCollection.doc(goal.id).update(updatedGoal.toMap());

    // 2. Delete Future Tasks (if requested and we are completing)
    if (isCompleted && deleteFutureTasks) {
      try {
        final now = Timestamp.now();
        // userIdフィルターを追加してセキュリティルールを満たす
        final futureTasksSnapshot = await _tasksCollection
            .where('userId', isEqualTo: goal.userId)
            .where('goalId', isEqualTo: goal.id)
            .where('scheduledAt', isGreaterThan: now)
            .get();

        print(
          'DEBUG: Found ${futureTasksSnapshot.docs.length} future tasks to delete',
        );

        if (futureTasksSnapshot.docs.isNotEmpty) {
          final batch = _firestore.batch();
          for (var doc in futureTasksSnapshot.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
          print(
            'DEBUG: Deleted ${futureTasksSnapshot.docs.length} future tasks',
          );
        }
      } catch (e) {
        // エラーの場合はログ出力（目標完了は成功済み）
        print('Error: Could not delete future tasks: $e');
      }
    }
  }

  // Stream Active Goals
  Stream<List<GoalModel>> streamActiveGoals(String userId) {
    return _goalsCollection
        .where('userId', isEqualTo: userId)
        .where('completedAt', isNull: true)
        .snapshots()
        .map((snapshot) {
          final goals = snapshot.docs
              .map((doc) => GoalModel.fromFirestore(doc))
              .toList();
          // orderでソート（クライアント側でソート）
          goals.sort((a, b) => a.order.compareTo(b.order));
          return goals;
        });
  }

  // Stream Completed Goals (Archive)
  Stream<List<GoalModel>> streamCompletedGoals(String userId) {
    // Firestoreのnullクエリは制限があるため、クライアント側でフィルタリング
    return _goalsCollection.where('userId', isEqualTo: userId).snapshots().map((
      snapshot,
    ) {
      final goals = snapshot.docs
          .map((doc) => GoalModel.fromFirestore(doc))
          .where((goal) => goal.completedAt != null) // クライアント側フィルタ
          .toList();
      // 完了日時で降順ソート
      goals.sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
      return goals;
    });
  }

  // Stream Single Goal
  Stream<DocumentSnapshot<Map<String, dynamic>>> getGoalStream(String goalId) {
    return _goalsCollection.doc(goalId).snapshots();
  }

  // Get Progress (Saturation Logic Helper)
  // Returns tuple: [completedCount, totalCount]
  Future<List<int>> getGoalProgress(String goalId) async {
    final tasksSnapshot = await _tasksCollection
        .where('goalId', isEqualTo: goalId)
        .get();

    final total = tasksSnapshot.docs.length;
    if (total == 0) return [0, 0];

    final completed = tasksSnapshot.docs
        .map((doc) => TaskModel.fromFirestore(doc))
        .where((t) => t.isCompleted)
        .length;

    return [completed, total];
  }

  // 目標の並び替え
  Future<void> reorderGoals(List<GoalModel> goals) async {
    final batch = _firestore.batch();
    for (var i = 0; i < goals.length; i++) {
      batch.update(_goalsCollection.doc(goals[i].id), {'order': i});
    }
    await batch.commit();
  }
}
