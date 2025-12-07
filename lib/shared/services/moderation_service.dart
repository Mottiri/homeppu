import 'package:cloud_functions/cloud_functions.dart';
import '../models/post_model.dart';

/// モデレーション結果
class ModerationResult {
  final bool isNegative;
  final String category;
  final double confidence;
  final String reason;
  final String suggestion;

  ModerationResult({
    required this.isNegative,
    required this.category,
    required this.confidence,
    required this.reason,
    required this.suggestion,
  });

  factory ModerationResult.fromJson(Map<String, dynamic> json) {
    return ModerationResult(
      isNegative: json['isNegative'] ?? false,
      category: json['category'] ?? 'none',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      reason: json['reason'] ?? '',
      suggestion: json['suggestion'] ?? '',
    );
  }
}

/// 徳ポイント状態
class VirtueStatus {
  final int virtue;
  final bool isBanned;
  final int warningThreshold;
  final int maxVirtue;

  VirtueStatus({
    required this.virtue,
    required this.isBanned,
    required this.warningThreshold,
    required this.maxVirtue,
  });

  factory VirtueStatus.fromJson(Map<String, dynamic> json) {
    return VirtueStatus(
      virtue: json['virtue'] ?? 100,
      isBanned: json['isBanned'] ?? false,
      warningThreshold: json['warningThreshold'] ?? 30,
      maxVirtue: json['maxVirtue'] ?? 100,
    );
  }

  /// 徳ポイントの割合（0.0〜1.0）
  double get virtueRatio => virtue / maxVirtue;

  /// 警告が必要かどうか
  bool get needsWarning => virtue <= warningThreshold;
}

/// 徳ポイント履歴
class VirtueHistoryItem {
  final String id;
  final int change;
  final String reason;
  final int newVirtue;
  final DateTime createdAt;

  VirtueHistoryItem({
    required this.id,
    required this.change,
    required this.reason,
    required this.newVirtue,
    required this.createdAt,
  });

  factory VirtueHistoryItem.fromJson(Map<String, dynamic> json) {
    return VirtueHistoryItem(
      id: json['id'] ?? '',
      change: json['change'] ?? 0,
      reason: json['reason'] ?? '',
      newVirtue: json['newVirtue'] ?? 0,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
    );
  }
}

/// 通報理由
enum ReportReason {
  harassment('harassment', '誹謗中傷'),
  spam('spam', 'スパム・宣伝'),
  inappropriate('inappropriate', '不適切な内容'),
  other('other', 'その他');

  const ReportReason(this.value, this.label);
  final String value;
  final String label;
}

/// モデレーションサービス
/// Cloud Functionsを呼び出してコンテンツモデレーションを行う
class ModerationService {
  final FirebaseFunctions _functions;

  ModerationService() 
      : _functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  /// モデレーション付き投稿作成
  /// ネガティブな内容の場合はエラーをスローし、徳ポイントが減少する
  Future<String> createPostWithModeration({
    required String content,
    required String userDisplayName,
    required int userAvatarIndex,
    required String postMode,
    String? circleId,
    List<MediaItem>? mediaItems,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        'createPostWithModeration',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );
      
      final result = await callable.call({
        'content': content,
        'userDisplayName': userDisplayName,
        'userAvatarIndex': userAvatarIndex,
        'postMode': postMode,
        'circleId': circleId,
        'mediaItems': mediaItems?.map((item) => item.toMap()).toList(),
      });

      return result.data['postId'] as String;
    } on FirebaseFunctionsException catch (e) {
      // モデレーションで拒否された場合
      throw ModerationException(
        message: e.message ?? 'ネガティブな内容が検出されました',
        code: e.code,
      );
    }
  }

  /// モデレーション付きコメント作成
  Future<String> createCommentWithModeration({
    required String postId,
    required String content,
    required String userDisplayName,
    required int userAvatarIndex,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        'createCommentWithModeration',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      
      final result = await callable.call({
        'postId': postId,
        'content': content,
        'userDisplayName': userDisplayName,
        'userAvatarIndex': userAvatarIndex,
      });

      return result.data['commentId'] as String;
    } on FirebaseFunctionsException catch (e) {
      throw ModerationException(
        message: e.message ?? 'ネガティブな内容が検出されました',
        code: e.code,
      );
    }
  }

  /// コンテンツを通報
  Future<void> reportContent({
    required String contentId,
    required String contentType, // "post" | "comment"
    required String reason,
    required String targetUserId,
  }) async {
    try {
      final callable = _functions.httpsCallable('reportContent');
      await callable.call({
        'contentId': contentId,
        'contentType': contentType,
        'reason': reason,
        'targetUserId': targetUserId,
      });
    } on FirebaseFunctionsException catch (e) {
      throw ModerationException(
        message: e.message ?? '通報に失敗しました',
        code: e.code,
      );
    }
  }

  /// 徳ポイント状態を取得
  Future<VirtueStatus> getVirtueStatus() async {
    try {
      final callable = _functions.httpsCallable('getVirtueStatus');
      final result = await callable.call();
      return VirtueStatus.fromJson(Map<String, dynamic>.from(result.data as Map));
    } catch (e) {
      // エラー時はデフォルト値を返す
      return VirtueStatus(
        virtue: 100,
        isBanned: false,
        warningThreshold: 30,
        maxVirtue: 100,
      );
    }
  }

  /// 徳ポイント履歴を取得
  Future<List<VirtueHistoryItem>> getVirtueHistory() async {
    try {
      final callable = _functions.httpsCallable('getVirtueHistory');
      final result = await callable.call();
      final historyData = result.data['history'] as List<dynamic>;
      
      return historyData
          .map((item) => VirtueHistoryItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (e) {
      return [];
    }
  }
}

/// モデレーション例外
class ModerationException implements Exception {
  final String message;
  final String code;

  ModerationException({
    required this.message,
    required this.code,
  });

  @override
  String toString() => message;

  /// BAN状態かどうか
  bool get isBanned => code == 'permission-denied';

  /// ネガティブコンテンツ検出か
  bool get isNegativeContent => code == 'invalid-argument';
}
