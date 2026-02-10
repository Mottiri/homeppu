import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';

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
      assetPath: (map['assetPath'] ?? '').toString(),
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

  const StampSheetPlacement({
    required this.docId,
    required this.sheetId,
    required this.slotId,
    required this.stampId,
  });

  factory StampSheetPlacement.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return StampSheetPlacement(
      docId: doc.id,
      sheetId: (data['sheetId'] ?? '').toString(),
      slotId: (data['slotId'] ?? '').toString(),
      stampId: (data['stampId'] ?? '').toString(),
    );
  }
}

class StampApplyResult {
  final bool consumed;
  final int remainingCredits;

  const StampApplyResult({
    required this.consumed,
    required this.remainingCredits,
  });
}

class StampSheetService {
  static const String defaultSheetId = 'default';
  static const String _defaultSheetAssetPath =
      'assets/stamp_sheets/default_common.png';
  static const String _defaultLayoutAssetPath =
      'assets/stamp_sheets/layouts/default.json';

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  StampSheetService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  Future<List<StampSheetDefinition>> fetchCatalog() async {
    final catalogDoc =
        await _firestore.collection('settings').doc('stampSheetCatalog').get();
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

  Stream<List<StampSheetPlacement>> watchPlacements(
    String userId,
    String sheetId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('stampSheet')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(StampSheetPlacement.fromDoc)
              .where((placement) => placement.sheetId == sheetId)
              .toList(),
        );
  }

  Future<void> setActiveSheet(String sheetId) async {
    final callable = _functions.httpsCallable('setActiveStampSheet');
    await callable.call({'sheetId': sheetId});
  }

  Future<StampApplyResult> applyStampToSlot({
    required String sheetId,
    required String slotId,
    required String stampId,
  }) async {
    final callable = _functions.httpsCallable('applyStampToSheetSlot');
    final result = await callable.call({
      'sheetId': sheetId,
      'slotId': slotId,
      'stampId': stampId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return StampApplyResult(
      consumed: data['consumed'] == true,
      remainingCredits: (data['remainingCredits'] as num?)?.toInt() ?? 0,
    );
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
