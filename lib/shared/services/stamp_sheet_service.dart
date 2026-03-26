import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_constants.dart';

class StampSheetDefinition {
  final String id;
  final String assetPath;
  final String rarity;
  final int displayOrder;
  final bool isActive;
  final String layoutAssetPath;

  const StampSheetDefinition({
    required this.id,
    required this.assetPath,
    required this.rarity,
    required this.displayOrder,
    required this.isActive,
    required this.layoutAssetPath,
  });

  String get unlockKey => 'sheet_$id';

  bool get isCommon => rarity == 'common';

  factory StampSheetDefinition.fromMap(
    Map<String, dynamic> map, {
    required String layoutAssetPath,
  }) {
    return StampSheetDefinition(
      id: (map['id'] ?? '').toString(),
      assetPath: (map['assetPath'] ?? '').toString().replaceAll('.png', '.webp'),
      rarity: (map['rarity'] ?? 'common').toString(),
      displayOrder: (map['displayOrder'] as num?)?.toInt() ?? 9999,
      isActive: map['isActive'] != false,
      layoutAssetPath: layoutAssetPath,
    );
  }
}

class StampSheetSlot {
  final String slotId;
  final double x;
  final double y;
  final double w;
  final double h;

  const StampSheetSlot({
    required this.slotId,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  factory StampSheetSlot.fromMap(Map<String, dynamic> map) {
    double toDouble(dynamic value, double fallback) {
      if (value is num) return value.toDouble();
      return fallback;
    }

    return StampSheetSlot(
      slotId: (map['slotId'] ?? '').toString(),
      x: toDouble(map['x'], 0),
      y: toDouble(map['y'], 0),
      w: toDouble(map['w'], 0.2),
      h: toDouble(map['h'], 0.2),
    );
  }
}

class StampSheetLayout {
  final String sheetId;
  final int version;
  final double aspectRatio;
  final List<StampSheetSlot> slots;

  const StampSheetLayout({
    required this.sheetId,
    required this.version,
    required this.aspectRatio,
    required this.slots,
  });
}

class StampSheetPlacement {
  final String docId;
  final String sheetId;
  final String slotId;
  final String stampId;
  final int pageIndex;
  final bool isNewFormat;

  const StampSheetPlacement({
    required this.docId,
    required this.sheetId,
    required this.slotId,
    required this.stampId,
    required this.pageIndex,
    this.isNewFormat = false,
  });

  /// doc ID の新旧フォーマットを判別してパース
  /// 新: {sheetId}_p{N}_{slotId}  →  pageIndex = N, isNewFormat = true
  /// 旧: {sheetId}_{slotId}       →  pageIndex = 0, isNewFormat = false
  static final _newFormatRegex = RegExp(r'_p(\d+)_');

  factory StampSheetPlacement.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const {};
    final docId = doc.id;
    final match = _newFormatRegex.firstMatch(docId);
    final int pageIdx;
    final bool newFmt;
    if (match != null) {
      pageIdx = int.tryParse(match.group(1) ?? '0') ?? 0;
      newFmt = true;
    } else {
      pageIdx = (data['pageIndex'] as num?)?.toInt() ?? 0;
      newFmt = false;
    }
    return StampSheetPlacement(
      docId: docId,
      sheetId: (data['sheetId'] ?? '').toString(),
      slotId: (data['slotId'] ?? '').toString(),
      stampId: (data['stampId'] ?? '').toString(),
      pageIndex: pageIdx,
      isNewFormat: newFmt,
    );
  }
}

class StampSnapshotEntry {
  final int pageIndex;
  final String sheetId;
  final String slotId;
  final String stampId;

  const StampSnapshotEntry({
    required this.pageIndex,
    required this.sheetId,
    required this.slotId,
    required this.stampId,
  });

  Map<String, dynamic> toMap() => {
    'pageIndex': pageIndex,
    'sheetId': sheetId,
    'slotId': slotId,
    'stampId': stampId,
  };
}

class StampSnapshotSyncResult {
  final int credits;
  final int version;
  final int entries;

  const StampSnapshotSyncResult({
    required this.credits,
    required this.version,
    required this.entries,
  });

  factory StampSnapshotSyncResult.fromMap(Map<String, dynamic> map) {
    int asInt(dynamic value, int fallback) {
      if (value is num) return value.toInt();
      return fallback;
    }

    return StampSnapshotSyncResult(
      credits: asInt(map['credits'], 0),
      version: asInt(map['version'], 0),
      entries: asInt(map['entries'], 0),
    );
  }
}

class StampSheetArchive {
  final String id;
  final String sheetId;
  final DateTime? completedAt;
  final Map<String, String> bySlot;

  const StampSheetArchive({
    required this.id,
    required this.sheetId,
    required this.completedAt,
    required this.bySlot,
  });

  factory StampSheetArchive.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final placementsRaw = data['placements'];
    final bySlot = <String, String>{};
    if (placementsRaw is List) {
      for (final raw in placementsRaw) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final slotId = (map['slotId'] ?? '').toString();
        final stampId = (map['stampId'] ?? '').toString();
        if (slotId.isEmpty || stampId.isEmpty) continue;
        bySlot[slotId] = stampId;
      }
    }
    final completedAtRaw = data['completedAt'];
    DateTime? completedAt;
    if (completedAtRaw is Timestamp) {
      completedAt = completedAtRaw.toDate();
    }
    return StampSheetArchive(
      id: doc.id,
      sheetId: (data['sheetId'] ?? '').toString(),
      completedAt: completedAt,
      bySlot: bySlot,
    );
  }
}

class StampSheetService {
  static const String defaultSheetId = 'default';
  static const String _defaultSheetAssetPath =
      'assets/stamp_sheets/autumn_common.webp';
  static const String _defaultLayoutAssetPath =
      'assets/stamp_sheets/layouts/autumn.json';

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  StampSheetService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);

  Future<List<StampSheetDefinition>> fetchCatalog() async {
    final catalogDoc = await _firestore
        .collection('settings')
        .doc('stampSheetCatalog')
        .get();
    final layoutDoc = await _firestore
        .collection('settings')
        .doc('stampSheetLayoutCatalog')
        .get();

    final layoutBySheetId = <String, String>{};
    final layoutsRaw = layoutDoc.data()?['layouts'];
    if (layoutsRaw is List) {
      for (final raw in layoutsRaw) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        if (map['isActive'] == false) continue;
        final sheetId = (map['sheetId'] ?? '').toString();
        final assetPath = (map['layoutAssetPath'] ?? '').toString();
        if (sheetId.isEmpty || assetPath.isEmpty) continue;
        layoutBySheetId[sheetId] = assetPath;
      }
    }

    final sheets = <StampSheetDefinition>[];
    final sheetsRaw = catalogDoc.data()?['sheets'];
    if (sheetsRaw is List) {
      for (final raw in sheetsRaw) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final sheetId = (map['id'] ?? '').toString();
        if (sheetId.isEmpty) continue;
        final layoutAssetPath =
            layoutBySheetId[sheetId] ??
            'assets/stamp_sheets/layouts/$sheetId.json';
        final sheet = StampSheetDefinition.fromMap(
          map,
          layoutAssetPath: layoutAssetPath,
        );
        if (!sheet.isActive) continue;
        if (sheet.assetPath.isEmpty) continue;
        sheets.add(sheet);
      }
    }

    if (sheets.isEmpty) {
      return const [
        StampSheetDefinition(
          id: defaultSheetId,
          assetPath: _defaultSheetAssetPath,
          rarity: 'common',
          displayOrder: 0,
          isActive: true,
          layoutAssetPath: _defaultLayoutAssetPath,
        ),
      ];
    }

    sheets.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return sheets;
  }

  Future<StampSheetLayout> loadLayout(StampSheetDefinition sheet) async {
    try {
      final text = await rootBundle.loadString(sheet.layoutAssetPath);
      final raw = jsonDecode(text);
      if (raw is! Map<String, dynamic>) {
        return _fallbackLayout(sheet.id);
      }
      final slotsRaw = raw['slots'];
      if (slotsRaw is! List) {
        return _fallbackLayout(sheet.id);
      }
      final slots = slotsRaw
          .whereType<Map>()
          .map((e) => StampSheetSlot.fromMap(Map<String, dynamic>.from(e)))
          .where((slot) => slot.slotId.isNotEmpty)
          .toList();
      if (slots.isEmpty) {
        return _fallbackLayout(sheet.id);
      }
      return StampSheetLayout(
        sheetId: (raw['sheetId'] ?? sheet.id).toString(),
        version: (raw['version'] as num?)?.toInt() ?? 1,
        aspectRatio: (raw['aspectRatio'] as num?)?.toDouble() ?? 0.8,
        slots: slots,
      );
    } catch (_) {
      return _fallbackLayout(sheet.id);
    }
  }

  StampSheetLayout _fallbackLayout(String sheetId) {
    return const StampSheetLayout(
      sheetId: defaultSheetId,
      version: 1,
      aspectRatio: 0.8,
      slots: [
        StampSheetSlot(slotId: 'slot_01', x: 0.15, y: 0.20, w: 0.20, h: 0.20),
        StampSheetSlot(slotId: 'slot_02', x: 0.40, y: 0.20, w: 0.20, h: 0.20),
        StampSheetSlot(slotId: 'slot_03', x: 0.65, y: 0.20, w: 0.20, h: 0.20),
        StampSheetSlot(slotId: 'slot_04', x: 0.15, y: 0.50, w: 0.20, h: 0.20),
        StampSheetSlot(slotId: 'slot_05', x: 0.40, y: 0.50, w: 0.20, h: 0.20),
        StampSheetSlot(slotId: 'slot_06', x: 0.65, y: 0.50, w: 0.20, h: 0.20),
      ],
    ).copyWithSheetId(sheetId);
  }

  /// 全ページの配置データを取得し、ページごとにグループ化して返す。
  /// 旧/新format が混在する場合、同一 pageIndex+slotId で新形式を優先。
  Stream<Map<int, List<StampSheetPlacement>>> watchAllPlacementsByPage(
    String userId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('stampSheet')
        .snapshots()
        .map((snapshot) {
          final all = snapshot.docs
              .map(StampSheetPlacement.fromDoc)
              .where((p) => p.sheetId.isNotEmpty && p.slotId.isNotEmpty)
              .toList();

          // 新形式を優先: 同一(pageIndex, slotId)で旧・新が共存 → 新のみ採用
          final newFormatKeys = <String>{};
          for (final p in all) {
            if (p.isNewFormat) {
              newFormatKeys.add('${p.pageIndex}_${p.slotId}');
            }
          }

          final byPage = <int, List<StampSheetPlacement>>{};
          for (final p in all) {
            final key = '${p.pageIndex}_${p.slotId}';
            if (!p.isNewFormat && newFormatKeys.contains(key)) continue;
            byPage.putIfAbsent(p.pageIndex, () => <StampSheetPlacement>[]);
            byPage[p.pageIndex]!.add(p);
          }
          return byPage;
        });
  }

  Future<void> setActiveSheet(String sheetId) async {
    final callable = _functions.httpsCallable('setActiveStampSheet');
    await callable.call({'sheetId': sheetId});
  }

  Future<StampSnapshotSyncResult> syncSnapshot({
    required int baseVersion,
    required List<StampSnapshotEntry> entries,
  }) async {
    final callable = _functions.httpsCallable('syncStampSheetSnapshot');
    final result = await callable.call({
      'baseVersion': baseVersion,
      'entries': entries.map((e) => e.toMap()).toList(),
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return StampSnapshotSyncResult.fromMap(data);
  }

  Future<void> archiveAndStartNextSheet({
    required String currentSheetId,
    required String nextSheetId,
  }) async {
    final callable = _functions.httpsCallable('archiveAndStartNextStampSheet');
    await callable.call({
      'currentSheetId': currentSheetId,
      'nextSheetId': nextSheetId,
    });
  }

  Stream<List<StampSheetArchive>> watchArchives(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('stampSheetArchives')
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(StampSheetArchive.fromDoc).toList());
  }
}

extension on StampSheetLayout {
  StampSheetLayout copyWithSheetId(String sheetId) {
    return StampSheetLayout(
      sheetId: sheetId,
      version: version,
      aspectRatio: aspectRatio,
      slots: slots,
    );
  }
}
