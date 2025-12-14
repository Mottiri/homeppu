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
  Future<void> deleteGoal(String goalId) async {
    final batch = _firestore.batch();

    // 1. Delete the Goal
    batch.delete(_goalsCollection.doc(goalId));

    // 2. Delete all linked Tasks
    // Note: If there are more than 500 tasks, this needs pagination.
    // Assuming reasonable number for now.
    final linkedTasksSnapshot = await _tasksCollection
        .where('goalId', isEqualTo: goalId)
        .get();

    for (var doc in linkedTasksSnapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }

  // Toggle Complete
  Future<void> toggleComplete(
    GoalModel goal, {
    bool isCompleted = true,
    bool deleteFutureTasks = false,
  }) async {
    final batch = _firestore.batch();

    // 1. Update Goal Status
    final updatedGoal = goal.copyWith(
      completedAt: isCompleted ? DateTime.now() : null,
      forceClearCompletedAt: !isCompleted,
    );
    batch.update(_goalsCollection.doc(goal.id), updatedGoal.toMap());

    // 2. Delete Future Tasks (if requested and we are completing)
    if (isCompleted && deleteFutureTasks) {
      final now = DateTime.now();
      // Find future tasks linked to this goal
      final futureTasksSnapshot = await _tasksCollection
          .where('goalId', isEqualTo: goal.id)
          .where('scheduledAt', isGreaterThan: now)
          .get();

      for (var doc in futureTasksSnapshot.docs) {
        batch.delete(doc.reference);
      }
    }

    await batch.commit();
  }

  // Stream Active Goals
  Stream<List<GoalModel>> streamActiveGoals(String userId) {
    return _goalsCollection
        .where('userId', isEqualTo: userId)
        .where('completedAt', isNull: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => GoalModel.fromFirestore(doc))
              .toList();
        });
  }

  // Stream Completed Goals (Archive)
  Stream<List<GoalModel>> streamCompletedGoals(String userId) {
    return _goalsCollection
        .where('userId', isEqualTo: userId)
        .where('completedAt', isNull: false)
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => GoalModel.fromFirestore(doc))
              .toList();
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
}
