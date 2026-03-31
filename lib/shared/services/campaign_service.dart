import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/campaign_model.dart';

class CampaignService {
  static const String _dismissedKeyPrefix = 'campaign_dismissed_';
  static const int maxDisplayPerSession = 3;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<CampaignModel>> getActiveCampaigns() async {
    try {
      final doc = await _firestore.doc('settings/campaigns').get();
      if (!doc.exists) return [];
      final data = doc.data();
      if (data == null) return [];

      final rawList = data['items'];
      if (rawList is! List) return [];

      final campaigns = <CampaignModel>[];
      for (final item in rawList) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final campaign = CampaignModel.tryFromMap(map);
        if (campaign == null) continue;
        if (!campaign.isCurrentlyActive) continue;
        campaigns.add(campaign);
      }
      return campaigns;
    } catch (e) {
      debugPrint('キャンペーン取得エラー: $e');
      return [];
    }
  }

  Future<void> dismiss(String campaignId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_dismissedKeyPrefix$campaignId', true);
  }

  Future<List<CampaignModel>> getUnreadCampaigns() async {
    final campaigns = await getActiveCampaigns();
    final prefs = await SharedPreferences.getInstance();
    return campaigns.where((c) {
      return !(prefs.getBool('$_dismissedKeyPrefix${c.id}') ?? false);
    }).toList();
  }
}
