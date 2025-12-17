import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/circle_model.dart';

final circleServiceProvider = Provider((ref) => CircleService());

class CircleService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // カテゴリ一覧
  static const List<String> categories = [
    '全て',
    '勉強',
    'ダイエット',
    '運動',
    '趣味',
    '仕事',
    '資格',
    '読書',
    '語学',
    'プログラミング',
    '音楽',
    'その他',
  ];

  // サークル一覧を取得
  Stream<List<CircleModel>> streamCircles({String? category}) {
    // シンプルなクエリでデータを取得し、クライアント側でソート
    return _firestore.collection('circles').snapshots().map((snapshot) {
      var circles = snapshot.docs
          .map((doc) => CircleModel.fromFirestore(doc))
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
  Stream<List<CircleModel>> streamPublicCircles({
    String? category,
    String? userId,
  }) {
    // シンプルなクエリでデータを取得し、クライアント側でフィルター・ソート
    return _firestore.collection('circles').snapshots().map((snapshot) {
      var circles = snapshot.docs
          .map((doc) => CircleModel.fromFirestore(doc))
          .where(
            (c) =>
                c.aiMode != CircleAIMode.aiOnly || // AIモードでない
                c.ownerId == userId,
          ) // または自分が作成者
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

  // サークル検索
  Future<List<CircleModel>> searchCircles(String query) async {
    // Firestoreは部分一致検索をサポートしないため、
    // 名前の前方一致で検索
    final snapshot = await _firestore
        .collection('circles')
        .where('isPublic', isEqualTo: true)
        .where('name', isGreaterThanOrEqualTo: query)
        .where('name', isLessThanOrEqualTo: '$query\uf8ff')
        .limit(20)
        .get();

    return snapshot.docs.map((doc) => CircleModel.fromFirestore(doc)).toList();
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
    );

    await docRef.set(circle.toFirestore());
    return docRef.id;
  }

  // サークル参加
  Future<void> joinCircle(String circleId, String userId) async {
    await _firestore.collection('circles').doc(circleId).update({
      'memberIds': FieldValue.arrayUnion([userId]),
      'memberCount': FieldValue.increment(1),
    });
  }

  // サークル退会
  Future<void> leaveCircle(String circleId, String userId) async {
    await _firestore.collection('circles').doc(circleId).update({
      'memberIds': FieldValue.arrayRemove([userId]),
      'memberCount': FieldValue.increment(-1),
    });
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
              .toList();
        });
  }

  // サークル更新
  Future<void> updateCircle(String circleId, Map<String, dynamic> data) async {
    await _firestore.collection('circles').doc(circleId).update(data);
  }

  // 参加申請を送信
  Future<void> sendJoinRequest(String circleId, String userId) async {
    await _firestore.collection('circleJoinRequests').add({
      'circleId': circleId,
      'userId': userId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
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

  // 参加申請を承認
  Future<void> approveJoinRequest(
    String requestId,
    String circleId,
    String userId,
  ) async {
    await _firestore.collection('circleJoinRequests').doc(requestId).update({
      'status': 'approved',
    });
    await joinCircle(circleId, userId);
  }

  // 参加申請を拒否
  Future<void> rejectJoinRequest(String requestId) async {
    await _firestore.collection('circleJoinRequests').doc(requestId).update({
      'status': 'rejected',
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

  // 投稿カウントをインクリメント
  Future<void> incrementPostCount(String circleId) async {
    await _firestore.collection('circles').doc(circleId).update({
      'postCount': FieldValue.increment(1),
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
}
