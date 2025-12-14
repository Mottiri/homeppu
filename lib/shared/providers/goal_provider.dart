import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/goal_service.dart';

final goalServiceProvider = Provider<GoalService>((ref) {
  return GoalService();
});
