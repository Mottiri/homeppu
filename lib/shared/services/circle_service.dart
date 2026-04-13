import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/constants/app_constants.dart';
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

  // サークル検索（Cloud Functions callable経由）
  // queryが空の場合はブラウズモード（フィルター/ソートのみ）
  Future<({
    List<CircleModel> circles,
    List<CircleModel> privateOwnerCircles,
    bool hasMore,
    Map<String, dynamic>? nextCursor,
    bool joinedTruncated,
  })> searchCircles(
    String? query, {
    required String userId,
    String? category,
    Map<String, dynamic>? cursor,
    int limit = 20,
    bool joinedOnly = false,
    String? sortBy,
    bool? hasSpace,
  }) async {
    final functions = FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);
    final callable = functions.httpsCallable('searchCircles');

    final result = await callable.call({
      if (query?.isNotEmpty == true) 'query': query,
      if (category != null && category != '全て') 'category': category,
      'limit': limit,
      if (joinedOnly) 'joinedOnly': true,
      'cursor': ?cursor,
      'sortBy': ?sortBy,
      if (hasSpace == true) 'hasSpace': true,
    });

    final data = Map<String, dynamic>.from(result.data as Map);
    final hasMore = data['hasMore'] as bool? ?? false;
    final rawCursor = data['nextCursor'];
    final nextCursor = rawCursor != null
        ? Map<String, dynamic>.from(rawCursor as Map)
        : null;

    CircleModel parseCircle(dynamic item) {
      final json = Map<String, dynamic>.from(item as Map);
      return CircleModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        category: json['category'] as String,
        ownerId: json['ownerId'] as String,
        subOwnerId: json['subOwnerId'] as String?,
        aiMode: CircleAIMode.values.firstWhere(
          (e) => e.name == (json['aiMode'] ?? 'mix'),
          orElse: () => CircleAIMode.mix,
        ),
        isPublic: json['isPublic'] as bool? ?? true,
        memberCount: json['memberCount'] as int? ?? 0,
        maxMembers: json['maxMembers'] as int? ?? 20,
        postCount: json['postCount'] as int? ?? 0,
        iconImageUrl: json['iconImageUrl'] as String?,
        coverImageUrl: json['coverImageUrl'] as String?,
        goal: json['goal'] as String? ?? '',
        recentActivity:
            DateTime.tryParse(json['recentActivity'] as String? ?? ''),
        lastHumanPostAt:
            DateTime.tryParse(json['lastHumanPostAt'] as String? ?? ''),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        memberIds: [],
      );
    }

    final circlesList = data['circles'] as List? ?? [];
    final circles = circlesList.map(parseCircle).toList();

    final privateList = data['privateOwnerCircles'] as List? ?? [];
    final privateOwnerCircles = privateList.map(parseCircle).toList();

    final joinedTruncated = data['joinedTruncated'] as bool? ?? false;

    return (
      circles: circles,
      privateOwnerCircles: privateOwnerCircles,
      hasMore: hasMore,
      nextCursor: nextCursor,
      joinedTruncated: joinedTruncated,
    );
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
    required CircleAIMode aiMode,
    required String goal,
    bool isPublic = true,
    String? rules,
  }) async {
    final functions = FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);
    final callable = functions.httpsCallable('createCircle');
    final result = await callable.call({
      'name': name,
      'description': description,
      'category': category,
      'aiMode': aiMode.name,
      'goal': goal,
      'isPublic': isPublic,
      'rules': ?rules,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['circleId'] as String;
  }

  // サークル参加
  Future<void> joinCircle(String circleId) async {
    final functions = FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);
    final callable = functions.httpsCallable('joinCircle');

    await callable.call({'circleId': circleId});
  }

  Future<bool> startCircleBrowseTrial() async {
    final functions = FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);
    final callable = functions.httpsCallable('startCircleBrowseTrial');
    final result = await callable.call();
    final data = Map<String, dynamic>.from(result.data as Map);
    return data['allowed'] == true;
  }

  Future<void> endCircleBrowseTrial() async {
    final functions = FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);
    final callable = functions.httpsCallable('endCircleBrowseTrial');
    await callable.call();
  }

  // サークル退会
  Future<void> leaveCircle(String circleId) async {
    final functions = FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);
    final callable = functions.httpsCallable('leaveCircle');

    await callable.call({'circleId': circleId});
  }

  // サークル更新（Firestore直接 — 画像URL等の非テキストフィールド用）
  Future<void> updateCircle(String circleId, Map<String, dynamic> data) async {
    await _firestore.collection('circles').doc(circleId).update(data);
  }

  // サークル編集（Cloud Functions経由 — テキストモデレーション付き）
  Future<void> updateCircleWithModeration({
    required String circleId,
    required String name,
    required String description,
    required String category,
    required String goal,
    required bool isPublic,
    String? rules,
  }) async {
    final functions = FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);
    final callable = functions.httpsCallable('updateCircle');
    await callable.call({
      'circleId': circleId,
      'name': name,
      'description': description,
      'category': category,
      'goal': goal,
      'isPublic': isPublic,
      'rules': rules,
    });
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
    final functions = FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);
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
    final functions = FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);
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
    final functions = FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);
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
    final functions = FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);
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
