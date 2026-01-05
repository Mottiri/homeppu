import 'package:cloud_firestore/cloud_firestore.dart';

/// BAN履歴モデル
class BanRecordModel {
  final String type; // 'temporary' | 'permanent'
  final String reason; // BAN理由
  final DateTime bannedAt; // BAN日時
  final String bannedBy; // 実行した管理者のUID
  final DateTime? resolvedAt; // 解除日時
  final String? resolution; // 'cleared' | 'escalated' | null

  BanRecordModel({
    required this.type,
    required this.reason,
    required this.bannedAt,
    required this.bannedBy,
    this.resolvedAt,
    this.resolution,
  });

  factory BanRecordModel.fromFirestore(Map<String, dynamic> data) {
    return BanRecordModel(
      type: data['type'] ?? 'temporary',
      reason: data['reason'] ?? '',
      bannedAt: (data['bannedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      bannedBy: data['bannedBy'] ?? '',
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      resolution: data['resolution'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'type': type,
      'reason': reason,
      'bannedAt': Timestamp.fromDate(bannedAt),
      'bannedBy': bannedBy,
      if (resolvedAt != null) 'resolvedAt': Timestamp.fromDate(resolvedAt!),
      if (resolution != null) 'resolution': resolution,
    };
  }
}
