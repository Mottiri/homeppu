import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/circle_model.dart';
import '../models/post_model.dart';

final circleServiceProvider = Provider((ref) => CircleService());

class CircleService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // カテゴリとアイコンのマッピング（唯一の定義元）
  static const Map<String, String> categoryIcons = {
    '全て': '📋',
    '勉強': '📚',
    'ダイエット': '🥗',
    '運動': '💪',
    '趣味': '🎨',
    '仕事': '💼',
    '資格': '📝',
    '読書': '📖',
    '語学': '🌍',
    '音楽': '🎵',
    'その他': '⭐',
  };

  // カテゴリ一覧（categoryIconsのキーから生成）
  static List<String> get categories => categoryIcons.keys.toList();

  // サークル一覧を取得
  Stream<List<CircleModel>> streamCircles({String? category}) {
    // シンプルなクエリでデータを取得し、クライアント側でソート
    return _firestore.collection('circles').snapshots().map((snapshot) {
      var circles = snapshot.docs
          .map((doc) => CircleModel.fromFirestore(doc))
          .where((c) => !c.isDeleted) // ソフトデリート済みは除外
          .toList();

      // カテゴリフィルター
      if (category != null && category != '全て') {
        circles = circles.where((c) => c.category == category).toList();
      }

      // 作成日でソート（降順）
      circles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return circles;
    });
  }

  // サークル一覧を取得（AIモードは作成者のみ表示）
  // セキュリティルールに合わせてORクエリを使用
  Stream<List<CircleModel>> streamPublicCircles({
    String? category,
    required String userId,
  }) {
    // ORクエリ: 公開サークル(mix/humanOnly) OR 自分が作成したサークル
    final query = _firestore
        .collection('circles')
        .where(
          Filter.or(
            Filter('aiMode', whereIn: ['mix', 'humanOnly']),
            Filter('ownerId', isEqualTo: userId),
          ),
        );

    return query.snapshots().map((snapshot) {
      var circles = snapshot.docs
          .map((doc) => CircleModel.fromFirestore(doc))
          .where((c) => !c.isDeleted) // ソフトデリート済みは除外
          .toList();

      // カテゴリフィルター
      if (category != null && category != '全て') {
        circles = circles.where((c) => c.category == category).toList();
      }

      // 作成日でソート（降順）
      circles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return circles;
    });
  }

  // サークル一覧を取得（Future版 - プル更新用）
  // セキュリティルールに合わせてORクエリを使用
  Future<List<CircleModel>> getPublicCircles({
    String? category,
    required String userId,
  }) async {
    // ORクエリ: 公開サークル(mix/humanOnly) OR 自分が作成したサークル
    final snapshot = await _firestore
        .collection('circles')
        .where(
          Filter.or(
            Filter('aiMode', whereIn: ['mix', 'humanOnly']),
            Filter('ownerId', isEqualTo: userId),
          ),
        )
        .get();

    var circles = snapshot.docs
        .map((doc) => CircleModel.fromFirestore(doc))
        .where((c) => !c.isDeleted) // ソフトデリート済みは除外
        .toList();

    // カテゴリフィルター
    if (category != null && category != '全て') {
      circles = circles.where((c) => c.category == category).toList();
    }

    // 作成日でソート（降順）
    circles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return circles;
  }

  // サークル一覧を取得（ページネーション対応）
  // セキュリティルールに合わせてORクエリを使用
  // 管理者の場合は全サークルを取得
  Future<({List<CircleModel> circles, DocumentSnapshot? lastDoc, bool hasMore})>
  getPublicCirclesPaginated({
    String? category,
    required String userId,
    bool isAdmin = false,
    DocumentSnapshot? lastDocument,
    int limit = 10,
  }) async {
    debugPrint(
      'getPublicCirclesPaginated: userId=$userId, isAdmin=$isAdmin, category=$category',
    );
    try {
      Query query;

      if (isAdmin) {
        // 管理者は全サークルを取得
        query = _firestore
            .collection('circles')
            .orderBy('createdAt', descending: true)
            .limit(limit + 1);
      } else {
        // 一般ユーザー: 公開サークル(mix/humanOnly) OR 自分が作成したサークル
        query = _firestore
            .collection('circles')
            .where(
              Filter.or(
                Filter('aiMode', whereIn: ['mix', 'humanOnly']),
                Filter('ownerId', isEqualTo: userId),
              ),
            )
            .orderBy('createdAt', descending: true)
            .limit(limit + 1);
      }

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      debugPrint('getPublicCirclesPaginated: クエリ実行中...');
      final snapshot = await query.get();
      debugPrint('getPublicCirclesPaginated: ${snapshot.docs.length}件取得');

      // hasMoreの判定（limit+1件取得できたら次がある）
      final hasMore = snapshot.docs.length > limit;
      final docs = hasMore ? snapshot.docs.sublist(0, limit) : snapshot.docs;

      var circles = docs
          .map(
            (doc) => CircleModel.fromFirestore(
              doc as DocumentSnapshot<Map<String, dynamic>>,
            ),
          )
          .where((c) => !c.isDeleted) // ソフトデリート済みは除外
          .toList();

      // カテゴリフィルター
      if (category != null && category != '全て') {
        circles = circles.where((c) => c.category == category).toList();
      }

      return (
        circles: circles,
        lastDoc: docs.isNotEmpty ? docs.last : null,
        hasMore: hasMore,
      );
    } catch (e, stackTrace) {
      debugPrint('getPublicCirclesPaginated エラー: $e');
      debugPrint('スタックトレース: $stackTrace');
      rethrow;
    }
  }

  // サークル検索
  // セキュリティルールに合わせてORクエリを使用
  Future<List<CircleModel>> searchCircles(
    String query, {
    required String userId,
  }) async {
    // Firestoreは部分一致検索をサポートしないため、クライアント側でフィルター
    // ORクエリ: 公開サークル(mix/humanOnly) OR 自分が作成したサークル
    final snapshot = await _firestore
        .collection('circles')
        .where(
          Filter.or(
            Filter('aiMode', whereIn: ['mix', 'humanOnly']),
            Filter('ownerId', isEqualTo: userId),
          ),
        )
        .get();

    // クライアント側で名前フィルター
    final lowerQuery = query.toLowerCase();
    return snapshot.docs
        .map((doc) => CircleModel.fromFirestore(doc))
        .where((c) => !c.isDeleted)
        .where((c) => c.name.toLowerCase().contains(lowerQuery))
        .take(20)
        .toList();
  }

  // サークル詳細を取得
  Stream<CircleModel?> streamCircle(String circleId) {
    return _firestore.collection('circles').doc(circleId).snapshots().map((
      doc,
    ) {
      if (!doc.exists) return null;
      return CircleModel.fromFirestore(doc);
    });
  }

  // サークル作成
  Future<String> createCircle({
    required String name,
    required String description,
    required String category,
    required String ownerId,
    required CircleAIMode aiMode,
    required String goal,
    bool isPublic = true,
    String? coverImageUrl,
    String? iconImageUrl,
    String? rules,
  }) async {
    final docRef = _firestore.collection('circles').doc();

    final circle = CircleModel(
      id: docRef.id,
      name: name,
      description: description,
      category: category,
      ownerId: ownerId,
      memberIds: [ownerId], // 作成者は自動参加
      aiMode: aiMode,
      goal: goal,
      isPublic: isPublic,
      createdAt: DateTime.now(),
      coverImageUrl: coverImageUrl,
      iconImageUrl: iconImageUrl,
      memberCount: 1,
      postCount: 0,
      rules: rules,
    );

    await docRef.set(circle.toFirestore());
    return docRef.id;
  }

  // サークル参加
  Future<void> joinCircle(String circleId) async {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
    final callable = functions.httpsCallable('joinCircle');

    await callable.call({'circleId': circleId});
  }

  Future<bool> startCircleBrowseTrial() async {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
    final callable = functions.httpsCallable('startCircleBrowseTrial');
    final result = await callable.call();
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['allowed'] == true;
  }

  Future<void> endCircleBrowseTrial() async {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
    final callable = functions.httpsCallable('endCircleBrowseTrial');
    await callable.call();
  }

  // サークル退会
  Future<void> leaveCircle(String circleId) async {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
    final callable = functions.httpsCallable('leaveCircle');

    await callable.call({'circleId': circleId});
  }

  // ユーザーが参加しているサークル一覧
  Stream<List<CircleModel>> streamMyCircles(String userId) {
    return _firestore
        .collection('circles')
        .where('memberIds', arrayContains: userId)
        .orderBy('recentActivity', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => CircleModel.fromFirestore(doc))
              .where((c) => !c.isDeleted) // ソフトデリート済みは除外
              .toList();
        });
  }

  // サークル更新
  Future<void> updateCircle(String circleId, Map<String, dynamic> data) async {
    await _firestore.collection('circles').doc(circleId).update(data);
  }

  // 申請中かどうかをチェック
  Future<bool> hasPendingRequest(String circleId, String userId) async {
    final snapshot = await _firestore
        .collection('circleJoinRequests')
        .where('circleId', isEqualTo: circleId)
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  // 参加申請を送信（Cloud Function経由）
  Future<void> sendJoinRequest(String circleId, String userId) async {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
    final callable = functions.httpsCallable('sendJoinRequest');

    await callable.call({'circleId': circleId});
  }

  // 参加申請一覧を取得（管理者用）
  Stream<List<Map<String, dynamic>>> streamJoinRequests(String circleId) {
    return _firestore
        .collection('circleJoinRequests')
        .where('circleId', isEqualTo: circleId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
        });
  }

  // 複数サークルの申請数をまとめて取得（オーナー用）
  Stream<Map<String, int>> streamPendingRequestCounts(List<String> circleIds) {
    if (circleIds.isEmpty) {
      return Stream.value({});
    }

    return _firestore
        .collection('circleJoinRequests')
        .where('circleId', whereIn: circleIds)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final counts = <String, int>{};
          for (final doc in snapshot.docs) {
            final circleId = doc.data()['circleId'] as String;
            counts[circleId] = (counts[circleId] ?? 0) + 1;
          }
          return counts;
        });
  }

  // 参加申請を承認（Cloud Function経由）
  Future<void> approveJoinRequest(
    String requestId,
    String circleId,
    String circleName,
  ) async {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
    final callable = functions.httpsCallable('approveJoinRequest');

    await callable.call({
      'requestId': requestId,
      'circleId': circleId,
      'circleName': circleName,
    });
  }

  // 参加申請を拒否（Cloud Function経由）
  Future<void> rejectJoinRequest(
    String requestId,
    String circleId,
    String circleName,
  ) async {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
    final callable = functions.httpsCallable('rejectJoinRequest');

    await callable.call({
      'requestId': requestId,
      'circleId': circleId,
      'circleName': circleName,
    });
  }

  // メンバーかどうかをチェック
  bool isMember(CircleModel circle, String userId) {
    return circle.memberIds.contains(userId);
  }

  // オーナーかどうかをチェック
  bool isOwner(CircleModel circle, String userId) {
    return circle.ownerId == userId;
  }

  // 副オーナーかどうかをチェック
  bool isSubOwner(CircleModel circle, String userId) {
    return circle.subOwnerId == userId;
  }

  // オーナーまたは副オーナーかどうかをチェック
  bool isOwnerOrSubOwner(CircleModel circle, String userId) {
    return isOwner(circle, userId) || isSubOwner(circle, userId);
  }

  // 副オーナーを任命（オーナーのみ実行可能）+ 通知送信
  Future<void> setSubOwner(
    String circleId,
    String subOwnerId, {
    required String circleName,
    required String ownerName,
    required int ownerAvatarIndex,
    required String ownerId,
  }) async {
    await _firestore.collection('circles').doc(circleId).update({
      'subOwnerId': subOwnerId,
    });

    // 任命されたユーザーに通知を送信
    await _firestore
        .collection('users')
        .doc(subOwnerId)
        .collection('notifications')
        .add({
          'type': 'sub_owner_appointed',
          'senderId': ownerId,
          'senderName': ownerName,
          'senderAvatarUrl': ownerAvatarIndex.toString(),
          'title': '副オーナーに任命されました',
          'body': '$circleName の副オーナーに任命されました',
          'circleName': circleName,
          'circleId': circleId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  // 副オーナーを解任（オーナーのみ実行可能）+ 通知送信
  Future<void> removeSubOwner(
    String circleId, {
    required String subOwnerId,
    required String circleName,
    required String ownerName,
    required int ownerAvatarIndex,
    required String ownerId,
  }) async {
    await _firestore.collection('circles').doc(circleId).update({
      'subOwnerId': null,
    });

    // 解任されたユーザーに通知を送信
    await _firestore
        .collection('users')
        .doc(subOwnerId)
        .collection('notifications')
        .add({
          'type': 'sub_owner_removed',
          'senderId': ownerId,
          'senderName': ownerName,
          'senderAvatarUrl': ownerAvatarIndex.toString(),
          'title': '副オーナーから解任されました',
          'body': '$circleName の副オーナーから解任されました',
          'circleName': circleName,
          'circleId': circleId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  /// サークルを削除（Cloud Function経由）
  /// 関連データ（投稿、コメント、リアクション、申請）も削除
  /// メンバーに通知を送信
  Future<void> deleteCircle({required String circleId, String? reason}) async {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
    final callable = functions.httpsCallable('deleteCircle');

    await callable.call({'circleId': circleId, 'reason': reason});
  }

  // 投稿をピン留め/解除
  Future<void> togglePinPost(String postId, bool isPinned) async {
    try {
      await _firestore.collection('posts').doc(postId).update({
        'isPinned': isPinned,
        'isPinnedTop': isPinned ? false : false, // ピン解除時はトップも解除
      });
    } catch (e) {
      rethrow;
    }
  }

  // トップ表示を設定（既存のトップを解除して新しいトップを設定）
  Future<void> setTopPinnedPost(String circleId, String postId) async {
    final batch = _firestore.batch();

    // 既存のトップピンを解除
    final existingTop = await _firestore
        .collection('posts')
        .where('circleId', isEqualTo: circleId)
        .where('isPinnedTop', isEqualTo: true)
        .get();

    for (final doc in existingTop.docs) {
      batch.update(doc.reference, {'isPinnedTop': false});
    }

    // 新しいトップを設定
    batch.update(_firestore.collection('posts').doc(postId), {
      'isPinned': true,
      'isPinnedTop': true,
    });

    await batch.commit();
  }

  // ピン留め投稿を取得
  Stream<List<PostModel>> streamPinnedPosts(String circleId) {
    return _firestore
        .collection('posts')
        .where('circleId', isEqualTo: circleId)
        .where('isPinned', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final posts = snapshot.docs
              .map((doc) => PostModel.fromFirestore(doc))
              .toList();
          // クライアント側でソート：トップピン優先、次に作成日降順
          posts.sort((a, b) {
            if (a.isPinnedTop && !b.isPinnedTop) return -1;
            if (!a.isPinnedTop && b.isPinnedTop) return 1;
            return b.createdAt.compareTo(a.createdAt);
          });
          return posts;
        });
  }
}
