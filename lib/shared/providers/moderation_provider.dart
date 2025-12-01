import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/moderation_service.dart';

/// モデレーションサービスプロバイダー
final moderationServiceProvider = Provider<ModerationService>((ref) {
  return ModerationService();
});

/// 徳ポイント状態プロバイダー（自動更新）
final virtueStatusProvider = FutureProvider.autoDispose<VirtueStatus>((ref) async {
  final service = ref.watch(moderationServiceProvider);
  return service.getVirtueStatus();
});

/// 徳ポイント履歴プロバイダー
final virtueHistoryProvider = FutureProvider.autoDispose<List<VirtueHistoryItem>>((ref) async {
  final service = ref.watch(moderationServiceProvider);
  return service.getVirtueHistory();
});
