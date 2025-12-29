import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 問い合わせカテゴリ
enum InquiryCategory {
  bug('bug', '🐛 バグ報告'),
  feature('feature', '💡 機能要望'),
  account('account', '👤 アカウント関連'),
  other('other', '📝 その他');

  const InquiryCategory(this.value, this.label);
  final String value;
  final String label;

  static InquiryCategory fromValue(String value) {
    return InquiryCategory.values.firstWhere(
      (c) => c.value == value,
      orElse: () => InquiryCategory.other,
    );
  }
}

/// 問い合わせステータス
enum InquiryStatus {
  open('open', '未対応'),
  inProgress('in_progress', '対応中'),
  resolved('resolved', '解決済み');

  const InquiryStatus(this.value, this.label);
  final String value;
  final String label;

  static InquiryStatus fromValue(String value) {
    return InquiryStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => InquiryStatus.open,
    );
  }
}

/// 問い合わせモデル
class InquiryModel {
  final String id;
  final String userId;
  final String userDisplayName;
  final int userAvatarIndex;
  final InquiryCategory category;
  final String subject;
  final InquiryStatus status;
  final bool hasUnreadReply;
  final bool hasUnreadMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  InquiryModel({
    required this.id,
    required this.userId,
    required this.userDisplayName,
    required this.userAvatarIndex,
    required this.category,
    required this.subject,
    required this.status,
    required this.hasUnreadReply,
    required this.hasUnreadMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InquiryModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return InquiryModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      userDisplayName: data['userDisplayName'] ?? '',
      userAvatarIndex: data['userAvatarIndex'] ?? 0,
      category: InquiryCategory.fromValue(data['category'] ?? 'other'),
      subject: data['subject'] ?? '',
      status: InquiryStatus.fromValue(data['status'] ?? 'open'),
      hasUnreadReply: data['hasUnreadReply'] ?? false,
      hasUnreadMessage: data['hasUnreadMessage'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// 問い合わせメッセージモデル
class InquiryMessageModel {
  final String id;
  final String senderId;
  final String senderName;
  final String senderType; // "user" or "admin"
  final String content;
  final String? imageUrl;
  final DateTime createdAt;

  InquiryMessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderType,
    required this.content,
    this.imageUrl,
    required this.createdAt,
  });

  factory InquiryMessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return InquiryMessageModel(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      senderType: data['senderType'] ?? 'user',
      content: data['content'] ?? '',
      imageUrl: data['imageUrl'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  bool get isAdmin => senderType == 'admin';
}

/// 問い合わせサービス
class InquiryService {
  static final InquiryService _instance = InquiryService._internal();
  factory InquiryService() => _instance;
  InquiryService._internal();

  final _firestore = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
  final _auth = FirebaseAuth.instance;

  /// 自分の問い合わせ一覧を取得
  Stream<List<InquiryModel>> getMyInquiries() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return Stream.value([]);

    return _firestore
        .collection('inquiries')
        .where('userId', isEqualTo: userId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => InquiryModel.fromFirestore(doc))
              .toList(),
        );
  }

  /// 問い合わせ詳細を取得
  Stream<InquiryModel?> getInquiry(String inquiryId) {
    return _firestore
        .collection('inquiries')
        .doc(inquiryId)
        .snapshots()
        .map((doc) => doc.exists ? InquiryModel.fromFirestore(doc) : null);
  }

  /// 問い合わせのメッセージ一覧を取得
  Stream<List<InquiryMessageModel>> getMessages(String inquiryId) {
    return _firestore
        .collection('inquiries')
        .doc(inquiryId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => InquiryMessageModel.fromFirestore(doc))
              .toList(),
        );
  }

  /// 新規問い合わせを作成
  Future<String> createInquiry({
    required InquiryCategory category,
    required String subject,
    required String content,
    String? imageUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('ログインが必要です');

    final callable = _functions.httpsCallable('createInquiry');
    final result = await callable.call({
      'category': category.value,
      'subject': subject,
      'content': content,
      'imageUrl': imageUrl,
    });

    return result.data['inquiryId'] as String;
  }

  /// メッセージを送信
  Future<void> sendMessage({
    required String inquiryId,
    required String content,
    String? imageUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('ログインが必要です');

    final callable = _functions.httpsCallable('sendInquiryMessage');
    await callable.call({
      'inquiryId': inquiryId,
      'content': content,
      'imageUrl': imageUrl,
    });
  }

  /// 未読返信をクリア（ユーザーが詳細画面を開いた時）
  Future<void> markAsRead(String inquiryId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('inquiries').doc(inquiryId).update({
      'hasUnreadReply': false,
    });
  }

  /// 未読の問い合わせ数を取得
  Stream<int> getUnreadCount() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return Stream.value(0);

    return _firestore
        .collection('inquiries')
        .where('userId', isEqualTo: userId)
        .where('hasUnreadReply', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // ========== 管理者用メソッド ==========

  /// 全問い合わせ一覧を取得（管理者用）
  Stream<List<InquiryModel>> getAllInquiries({InquiryStatus? statusFilter}) {
    Query query = _firestore
        .collection('inquiries')
        .orderBy('updatedAt', descending: true);

    if (statusFilter != null) {
      query = query.where('status', isEqualTo: statusFilter.value);
    }

    return query.snapshots().map(
      (snapshot) =>
          snapshot.docs.map((doc) => InquiryModel.fromFirestore(doc)).toList(),
    );
  }

  /// ステータスを変更（管理者用）- Cloud Functionsで通知送信
  Future<void> updateStatus(String inquiryId, InquiryStatus status) async {
    final callable = _functions.httpsCallable('updateInquiryStatus');
    await callable.call({'inquiryId': inquiryId, 'status': status.value});
  }

  /// 返信を送信（管理者用）
  Future<void> sendAdminReply({
    required String inquiryId,
    required String content,
  }) async {
    final callable = _functions.httpsCallable('sendInquiryReply');
    await callable.call({'inquiryId': inquiryId, 'content': content});
  }

  /// 未読メッセージをクリア（管理者が詳細画面を開いた時）
  Future<void> markAsReadByAdmin(String inquiryId) async {
    await _firestore.collection('inquiries').doc(inquiryId).update({
      'hasUnreadMessage': false,
    });
  }
}
