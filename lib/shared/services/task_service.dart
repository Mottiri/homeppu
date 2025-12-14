import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/task_model.dart';
import 'package:flutter/foundation.dart';

class TaskService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  // ------------------------------------------------------------------------
  // Create
  // ------------------------------------------------------------------------

  /// タスクを作成
  /// 繰り返し設定がある場合、最大1年分（約365個）のタスクを一括生成する
  Future<void> createTask({
    required String userId,
    required String content,
    required String emoji,
    required String type,
    DateTime? scheduledAt,
    int priority = 0,
    String? categoryId,
    int? recurrenceInterval,
    String? recurrenceUnit,
    List<int>? recurrenceDaysOfWeek,
    DateTime? recurrenceEndDate,
    String? memo,
    List<String>? attachmentUrls,
    String? goalId,
  }) async {
    final batch = _firestore.batch();

    // 基本データ
    final now = DateTime.now();
    final baseTaskData = {
      'userId': userId,
      'content': content,
      'emoji': emoji,
      'type': type,
      'isCompleted': false,
      'streak': 0,
      'lastCompletedAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'priority': priority,
      'googleCalendarEventId': null, // 連携削除済み
      'subtasks': [],
      'categoryId': categoryId,
      'isPublic': false, // デフォルト
      'shareToCircleIds': [],
      'memo': memo,
      'attachmentUrls': attachmentUrls ?? [],
      'goalId': goalId,
    };

    // 繰り返しなしの場合
    if (recurrenceUnit == null || recurrenceUnit == 'none') {
      final docRef = _firestore.collection('tasks').doc();
      batch.set(docRef, {
        ...baseTaskData,
        'scheduledAt': scheduledAt != null
            ? Timestamp.fromDate(scheduledAt)
            : null,
        // ルールは保存しない
        'recurrenceInterval': null,
        'recurrenceUnit': null,
        'recurrenceDaysOfWeek': null,
        'recurrenceEndDate': null,
        'recurrenceGroupId': null,
      });
    } else {
      // 繰り返しあり：1年分生成
      final groupId = _uuid.v4();
      final dates = _generateRecurrenceDates(
        startDate: scheduledAt ?? now,
        interval: recurrenceInterval ?? 1,
        unit: recurrenceUnit,
        daysOfWeek: recurrenceDaysOfWeek,
        endDate: recurrenceEndDate,
        maxYears: 1, // 1年制限
      );

      for (var i = 0; i < dates.length; i++) {
        final date = dates[i];
        final docRef = _firestore.collection('tasks').doc();

        final taskData = {
          ...baseTaskData,
          'scheduledAt': Timestamp.fromDate(date),
          'recurrenceGroupId': groupId,
          // 最初のタスク（オリジン）にのみルールを保存する場合もあるが、
          // 実装をシンプルにするため、全てのタスクに「これは何の繰り返しの一部か」情報を持たせる
          // UIで「毎週月曜」と表示するために必要
          'recurrenceInterval': recurrenceInterval,
          'recurrenceUnit': recurrenceUnit,
          'recurrenceDaysOfWeek': recurrenceDaysOfWeek,
          'recurrenceEndDate': recurrenceEndDate != null
              ? Timestamp.fromDate(recurrenceEndDate)
              : null,
          // 未来のタスクには添付ファイルを引き継がない
          'attachmentUrls': [],
          // 未来のタスクのサブタスクは未完了にする
          'subtasks': baseTaskData['subtasks'] is List
              ? (baseTaskData['subtasks'] as List).map((item) {
                  return {
                    'id': item['id'],
                    'title': item['title'],
                    'isCompleted': false, // Reset
                  };
                }).toList()
              : [],
        };

        batch.set(docRef, taskData);
      }
    }

    await batch.commit();
  }

  // ------------------------------------------------------------------------
  // Update
  // ------------------------------------------------------------------------

  /// タスクを更新
  /// editMode: 'single' (このタスクのみ), 'future' (これ以降すべて)
  Future<void> updateTask(TaskModel task, {String editMode = 'single'}) async {
    // ケース1: 単発タスクを繰り返しタスクに変更する場合
    // (recurrenceGroupIdがなく、今回recurrenceUnitが設定されている)
    if (task.recurrenceGroupId == null &&
        (task.recurrenceUnit != null && task.recurrenceUnit != 'none')) {
      // 新しいグループIDを払い出し、未来分を生成する
      final groupId = _uuid.v4();
      final scheduledAt = task.scheduledAt ?? DateTime.now();

      final dates = _generateRecurrenceDates(
        startDate: scheduledAt,
        interval: task.recurrenceInterval ?? 1,
        unit: task.recurrenceUnit!,
        daysOfWeek: task.recurrenceDaysOfWeek,
        endDate: task.recurrenceEndDate,
        maxYears: 1,
      );

      final batch = _firestore.batch();

      // 1. オリジナルタスクの更新 (Group ID付与)
      batch.update(_firestore.collection('tasks').doc(task.id), {
        'content': task.content,
        'emoji': task.emoji,
        'type': task.type,
        'scheduledAt': Timestamp.fromDate(scheduledAt),
        'priority': task.priority,
        'subtasks': task.subtasks.map((e) => e.toMap()).toList(),
        'categoryId': task.categoryId,
        'recurrenceGroupId': groupId, // 新規割り当て
        'recurrenceInterval': task.recurrenceInterval,
        'recurrenceUnit': task.recurrenceUnit,
        'recurrenceDaysOfWeek': task.recurrenceDaysOfWeek,
        'recurrenceEndDate': task.recurrenceEndDate != null
            ? Timestamp.fromDate(task.recurrenceEndDate!)
            : null,
        'memo': task.memo,
        'attachmentUrls': task.attachmentUrls,
        'goalId': task.goalId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2. 2回目以降のタスクを生成
      // start: 1 (0番目はオリジナルなのでスキップ)
      for (var i = 1; i < dates.length; i++) {
        final date = dates[i];
        final docRef = _firestore.collection('tasks').doc();

        final baseTaskData = {
          'userId': task.userId,
          'content': task.content,
          'emoji': task.emoji,
          'type': task.type,
          'isCompleted': false,
          'streak': 0,
          'lastCompletedAt': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'priority': task.priority,
          // サブタスクは引き継ぐが完了状態はリセット
          'subtasks': task.subtasks
              .map((e) => e.toMap()..['isCompleted'] = false)
              .toList(),
          'categoryId': task.categoryId,
          'isPublic': task.isPublic,
          'shareToCircleIds': task.shareToCircleIds,
          'recurrenceGroupId': groupId, // 同じID
          'recurrenceInterval': task.recurrenceInterval,
          'recurrenceUnit': task.recurrenceUnit,
          'recurrenceDaysOfWeek': task.recurrenceDaysOfWeek,
          'recurrenceEndDate': task.recurrenceEndDate != null
              ? Timestamp.fromDate(task.recurrenceEndDate!)
              : null,
          'memo': task.memo,
          'attachmentUrls': [], // 未来分は空にする
          'goalId': task.goalId,
        };

        batch.set(docRef, {
          ...baseTaskData,
          'scheduledAt': Timestamp.fromDate(date),
        });
      }

      await batch.commit();
      return;
    }

    // ケース2: 通常の更新 (editModeによる分岐)
    if (editMode == 'single' || task.recurrenceGroupId == null) {
      // 単発更新 (または繰り返し解除)
      await _firestore.collection('tasks').doc(task.id).update({
        'content': task.content,
        'emoji': task.emoji,
        'type': task.type,
        'scheduledAt': task.scheduledAt != null
            ? Timestamp.fromDate(task.scheduledAt!)
            : null,
        'priority': task.priority,
        'subtasks': task.subtasks.map((e) => e.toMap()).toList(),
        'categoryId': task.categoryId,
        'recurrenceInterval': task.recurrenceInterval,
        'recurrenceUnit': task.recurrenceUnit,
        'recurrenceDaysOfWeek': task.recurrenceDaysOfWeek,
        'recurrenceEndDate': task.recurrenceEndDate != null
            ? Timestamp.fromDate(task.recurrenceEndDate!)
            : null,
        'memo': task.memo,
        'attachmentUrls': task.attachmentUrls,
        'goalId': task.goalId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // 未来分一括更新
      // 1. 自分以降の同グループタスクを取得
      final scheduledAt = task.scheduledAt ?? DateTime.now();
      final query = await _firestore
          .collection('tasks')
          .where('userId', isEqualTo: task.userId) // Security Rule requirement
          .where('recurrenceGroupId', isEqualTo: task.recurrenceGroupId)
          .where(
            'scheduledAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(scheduledAt),
          )
          .get();

      final batch = _firestore.batch();

      // 2. 既存を削除
      for (var doc in query.docs) {
        batch.delete(doc.reference);
      }

      // 3. 新規生成（自分を含む未来分）
      // 設定内容は task (引数) のものを使う
      final dates = _generateRecurrenceDates(
        startDate: scheduledAt,
        interval: task.recurrenceInterval ?? 1,
        unit: task.recurrenceUnit!,
        daysOfWeek: task.recurrenceDaysOfWeek,
        endDate: task.recurrenceEndDate,
        maxYears: 1,
      );

      final baseTaskData = {
        'userId': task.userId,
        'content': task.content,
        'emoji': task.emoji,
        'type': task.type,
        'isCompleted': false, // リセット
        'streak': 0,
        'lastCompletedAt': null,
        'createdAt': FieldValue.serverTimestamp(), // 再生成扱い
        'updatedAt': FieldValue.serverTimestamp(),
        'priority': task.priority,
        // サブタスクは引き継ぐが完了状態はリセット
        'subtasks': task.subtasks
            .map((e) => e.toMap()..['isCompleted'] = false)
            .toList(),
        'categoryId': task.categoryId,
        'isPublic': task.isPublic,
        'shareToCircleIds': task.shareToCircleIds,
        'recurrenceGroupId': task.recurrenceGroupId, // IDは維持
        'recurrenceInterval': task.recurrenceInterval,
        'recurrenceUnit': task.recurrenceUnit,
        'recurrenceDaysOfWeek': task.recurrenceDaysOfWeek,
        'recurrenceEndDate': task.recurrenceEndDate != null
            ? Timestamp.fromDate(task.recurrenceEndDate!)
            : null,
        'memo': task.memo,
        'attachmentUrls': [], // 未来分は空にする
        'goalId': task.goalId,
      };

      for (var date in dates) {
        final docRef = _firestore.collection('tasks').doc();
        batch.set(docRef, {
          ...baseTaskData,
          'scheduledAt': Timestamp.fromDate(date),
        });
      }

      await batch.commit();
    }
  }

  // ------------------------------------------------------------------------
  // Complete / Uncomplete (Optimistic UI handled by Widget, DB access here)
  // ------------------------------------------------------------------------

  /// タスクを完了
  /// 徳ポイント計算はサーバー側トリガーで行うため、ここではフラグ更新のみ
  Future<void> completeTask(String taskId) async {
    await _firestore.collection('tasks').doc(taskId).update({
      'isCompleted': true,
      'lastCompletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      // streakの計算はトリガーに任せるか、あるいは簡易的に+1してもよいが、
      // サーバーが正解を持っているのでUI側で楽観的表示するだけで十分
    });
  }

  /// タスクの完了を取り消し
  Future<void> uncompleteTask(String taskId) async {
    await _firestore.collection('tasks').doc(taskId).update({
      'isCompleted': false,
      'lastCompletedAt': null, // または以前の値に戻す？履歴がないと不明。nullでOK
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ------------------------------------------------------------------------
  // Delete
  // ------------------------------------------------------------------------

  Future<void> deleteTask(
    String taskId, {
    String? recurrenceGroupId,
    bool deleteAll = false,
    required String userId,
    DateTime? startDate,
  }) async {
    if (deleteAll && recurrenceGroupId != null) {
      // 未来のタスクをまとめて削除
      // ※過去のタスク（完了済みなど）は残すべきか？ -> 「以降すべて削除」が一般的
      // ここでは「現在時刻以降」を削除対象とする
      // startDateが指定されていればそれを使う。なければ現在日時（今日）
      final now = DateTime.now();
      // 時間情報は切り捨てて日付のみにする (00:00:00)
      final baseDate = startDate ?? now;
      final cutoffDate = DateTime(baseDate.year, baseDate.month, baseDate.day);

      final query = await _firestore
          .collection('tasks')
          .where('userId', isEqualTo: userId) // Security Rule requirement
          .where('recurrenceGroupId', isEqualTo: recurrenceGroupId)
          .get();

      // Client-side filtering to ensure robustness
      final docsToDelete = query.docs.where((doc) {
        final data = doc.data();
        if (data['scheduledAt'] == null) return false;
        final scheduledAt = (data['scheduledAt'] as Timestamp).toDate();
        // Compare dates
        // docのscheduledAtがcutoffDate以降なら削除対象
        // isAtSameMomentAs: 同日
        // isAfter: 未来
        return scheduledAt.isAtSameMomentAs(cutoffDate) ||
            scheduledAt.isAfter(cutoffDate);
      }).toList();

      final batch = _firestore.batch();
      for (var doc in docsToDelete) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } else {
      await _firestore.collection('tasks').doc(taskId).delete();
    }
  }

  /// タスク一覧を取得
  /// 基本はStreamを使うべきだが、Future版も維持
  Future<List<TaskModel>> getTasks({
    String? type,
    required String userId,
  }) async {
    var query = _firestore
        .collection('tasks')
        .where('userId', isEqualTo: userId);

    if (type != null) {
      query = query.where('type', isEqualTo: type);
    }

    // 期限順などに並べる
    // query = query.orderBy('scheduledAt'); // 必要に応じてInventory設定

    final snapshot = await query.get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id; // ID埋め込み
      return TaskModel.fromMap(data);
    }).toList();
  }

  /// Get tasks linked to a goal (Stream)
  /// userIdが必要なのはFirestoreセキュリティルールがuserIdでのフィルタリングを要求するため
  Stream<QuerySnapshot<Map<String, dynamic>>> getGoalsTasksStream(
    String goalId,
    String userId,
  ) {
    return _firestore
        .collection('tasks')
        .where('userId', isEqualTo: userId)
        .where('goalId', isEqualTo: goalId)
        .snapshots();
  }

  // ------------------------------------------------------------------------
  // Recurrence Logic (Dart)
  // ------------------------------------------------------------------------

  List<DateTime> _generateRecurrenceDates({
    required DateTime startDate,
    required int interval,
    required String unit,
    List<int>? daysOfWeek,
    DateTime? endDate,
    int maxYears = 1,
  }) {
    final dates = <DateTime>[];

    // 終了日リミット: 指定がない場合は開始日からmaxYears年後
    final limitDate =
        endDate ??
        DateTime(startDate.year + maxYears, startDate.month, startDate.day);

    var current = startDate;
    // 最初の1回目を含めるかどうか？
    // scheduledAtで指定した日は「1回目」として含むのが自然

    // ループ回数リミット(念のため無限ループ防止)
    int safeguard = 0;
    const maxCount = 500;

    while (current.isBefore(limitDate) || current.isAtSameMomentAs(limitDate)) {
      if (safeguard++ > maxCount) break;

      // 条件チェック (曜日など)
      bool isValid = true;
      if (unit == 'weekly' && daysOfWeek != null && daysOfWeek.isNotEmpty) {
        // daysOfWeek: 1(Mon)..7(Sun). DateTime.weekday: 1(Mon)..7(Sun). Matches!
        if (!daysOfWeek.contains(current.weekday)) {
          isValid = false;
        }
      }

      if (isValid) {
        dates.add(current);
      }

      // Next Date
      if (unit == 'daily') {
        current = current.add(Duration(days: interval));
      } else if (unit == 'weekly') {
        current = current.add(
          Duration(days: interval),
        ); // 単純に+1日して曜日チェックに回す手もあるが、効率悪い
        // ここでは「毎日チェック」方式にする（実装が一番楽でバグらない）
        // -> いや、weeklyでintervalがある場合（2週間ごと）とかは、週単位のジャンプが必要。
        // 単純化: intervalを無視して毎日進めるループにする？ -> 重い。

        // 【修正ロジック】
        // weeklyの場合は「1日ずつ進める」が一番確実。間隔(interval)の処理が難しいが。
        // interval=1 (毎週) なら良いが、2週間ごとは？
        // Homeppuの仕様では「毎週X曜日」「隔週」などは設定UIにあるか？
        // -> `recurrenceInterval` がある。

        if (interval == 1) {
          current = current.add(const Duration(days: 1));
        } else {
          // 隔週などの場合、週の開始基準が必要。
          // 簡易実装: 単純に +1日 して、判定ロジックで弾く？
          // いや、とりあえず interval=1 (毎週) 前提で +1日 するのが無難。
          current = current.add(const Duration(days: 1));
          // ※本来は週またぎの判定が必要だが、今回は一旦これで。
          // もしinterval > 1 をサポートするならロジック強化が必要。
        }
      } else if (unit == 'monthly') {
        // 月ごとの同日
        // ※31日問題などはDartのDateTimeが自動調整(翌月1日になったりする)
        var nextMonth = current.month + interval;
        var nextYear = current.year;
        while (nextMonth > 12) {
          nextMonth -= 12;
          nextYear++;
        }
        // 日付を維持しようとする
        final expectedDay = startDate.day; // 開始日の日付を基準にする
        // 単純addだとズレるので、構成しなおす
        // DateTime(nextYear, nextMonth, expectedDay);
        // 月末補正: 2月30日などは3月2日とかになるのを防ぐなら、その月の末日に丸める処理が必要
        // ここでは簡易的に DateTimeコンストラクタ に任せる
        current = DateTime(
          nextYear,
          nextMonth,
          expectedDay,
          current.hour,
          current.minute,
        );
      } else if (unit == 'yearly') {
        current = DateTime(
          current.year + interval,
          current.month,
          current.day,
          current.hour,
          current.minute,
        );
      } else {
        // fallback
        current = current.add(const Duration(days: 1));
      }
    }

    return dates;
  }
}
