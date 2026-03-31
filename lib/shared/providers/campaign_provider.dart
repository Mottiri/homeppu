import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/campaign_model.dart';
import '../services/campaign_service.dart';

final campaignServiceProvider =
    Provider<CampaignService>((ref) => CampaignService());

final unreadCampaignsProvider =
    FutureProvider<List<CampaignModel>>((ref) async {
  final service = ref.read(campaignServiceProvider);
  return service.getUnreadCampaigns();
});
