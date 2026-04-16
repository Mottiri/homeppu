import 'package:cloud_firestore/cloud_firestore.dart';

class CampaignModel {
  final String id;
  final String title;
  final String body;
  final String? imagePath;
  final String? footerNote;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;

  const CampaignModel({
    required this.id,
    required this.title,
    required this.body,
    this.imagePath,
    this.footerNote,
    required this.startDate,
    required this.endDate,
    required this.isActive,
  });

  /// safe parse: 型不正時は null を返す（呼び出し側でスキップ）
  static CampaignModel? tryFromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final title = map['title'];
    final body = map['body'];
    final startDate = map['startDate'];
    final endDate = map['endDate'];
    final isActive = map['isActive'];

    if (id is! String || id.isEmpty) return null;
    if (title is! String) return null;
    if (body is! String) return null;
    if (startDate is! Timestamp) return null;
    if (endDate is! Timestamp) return null;
    if (isActive is! bool) return null;

    final imagePathRaw = map['imagePath'];
    if (imagePathRaw != null && imagePathRaw is! String) return null;
    final footerNoteRaw = map['footerNote'];
    if (footerNoteRaw != null && footerNoteRaw is! String) return null;

    final imagePath = switch (imagePathRaw) {
      final String value when value.trim().isEmpty => null,
      final String value => value.trim(),
      _ => null,
    };
    final footerNote = switch (footerNoteRaw) {
      final String value when value.trim().isEmpty => null,
      final String value => value,
      _ => null,
    };

    // UTC → JST(+9h) 変換。_nowJst() と同じ基準で比較するため。
    final startDateJst =
        startDate.toDate().toUtc().add(const Duration(hours: 9));
    final endDateJst =
        endDate.toDate().toUtc().add(const Duration(hours: 9));

    return CampaignModel(
      id: id,
      title: title,
      body: body,
      imagePath: imagePath,
      footerNote: footerNote,
      startDate: startDateJst,
      endDate: endDateJst,
      isActive: isActive,
    );
  }

  /// JST基準の現在時刻（端末タイムゾーン非依存）
  static DateTime _nowJst() {
    return DateTime.now().toUtc().add(const Duration(hours: 9));
  }

  /// 現在有効なキャンペーンか判定（JST基準）
  bool get isCurrentlyActive {
    final now = _nowJst();
    return isActive && !now.isBefore(startDate) && now.isBefore(endDate);
  }
}
