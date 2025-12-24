import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/name_part_model.dart';

/// 名前パーツサービス
class NamePartsService {
  final FirebaseFunctions _functions;

  NamePartsService()
    : _functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  /// 名前パーツマスタを初期化（管理者用）
  Future<void> initializeNameParts() async {
    try {
      final callable = _functions.httpsCallable('initializeNameParts');
      final result = await callable.call();
      debugPrint('名前パーツ初期化: ${result.data}');
    } catch (e) {
      debugPrint('名前パーツ初期化エラー: $e');
      rethrow;
    }
  }

  /// 名前パーツ一覧を取得
  Future<NamePartsResult> getNameParts() async {
    try {
      final callable = _functions.httpsCallable('getNameParts');
      final result = await callable.call();
      final data = result.data as Map<String, dynamic>;

      final prefixes = (data['prefixes'] as List)
          .map((p) => NamePartModel.fromMap(Map<String, dynamic>.from(p)))
          .toList();

      final suffixes = (data['suffixes'] as List)
          .map((s) => NamePartModel.fromMap(Map<String, dynamic>.from(s)))
          .toList();

      return NamePartsResult(
        prefixes: prefixes,
        suffixes: suffixes,
        currentPrefixId: data['currentPrefix'],
        currentSuffixId: data['currentSuffix'],
      );
    } catch (e) {
      debugPrint('名前パーツ取得エラー: $e');
      rethrow;
    }
  }

  /// ユーザー名を更新
  Future<UpdateNameResult> updateUserName({
    required String prefixId,
    required String suffixId,
  }) async {
    try {
      final callable = _functions.httpsCallable('updateUserName');
      final result = await callable.call({
        'prefixId': prefixId,
        'suffixId': suffixId,
      });
      final data = result.data as Map<String, dynamic>;

      return UpdateNameResult(
        success: data['success'] ?? false,
        displayName: data['displayName'] ?? '',
        message: data['message'] ?? '',
      );
    } catch (e) {
      debugPrint('名前更新エラー: $e');
      rethrow;
    }
  }
}

/// 名前パーツ取得結果
class NamePartsResult {
  final List<NamePartModel> prefixes;
  final List<NamePartModel> suffixes;
  final String? currentPrefixId;
  final String? currentSuffixId;

  NamePartsResult({
    required this.prefixes,
    required this.suffixes,
    this.currentPrefixId,
    this.currentSuffixId,
  });
}

/// 名前更新結果
class UpdateNameResult {
  final bool success;
  final String displayName;
  final String message;

  UpdateNameResult({
    required this.success,
    required this.displayName,
    required this.message,
  });
}
