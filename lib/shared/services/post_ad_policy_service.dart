import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';

class PostAdPolicyService {
  static const String _pendingKeyPrefix = 'post_ad_pending_count_';
  static const String _shownTodayKeyPrefix = 'post_ad_shown_today_';
  static const String _dayKeyPrefix = 'post_ad_day_';
  static const String _noticeSkipKeyPrefix = 'post_ad_notice_skip_';

  Future<bool> shouldShowAdOnThisPost(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await _syncDayBoundary(prefs, userId);
    final shownToday = prefs.getInt(_key(_shownTodayKeyPrefix, userId)) ?? 0;

    final pendingKey = _key(_pendingKeyPrefix, userId);
    final pending = prefs.getInt(pendingKey) ?? 0;
    final nextPending = pending + 1;

    if (nextPending < AppConstants.postInterstitialAdFrequency) {
      await prefs.setInt(pendingKey, nextPending);
      if (kDebugMode) {
        debugPrint(
          '[PostAdPolicy] skip: pending=$nextPending/${AppConstants.postInterstitialAdFrequency}',
        );
      }
      return false;
    }

    // 3回目以降は、実際に表示成功するまで再試行する。
    await prefs.setInt(pendingKey, AppConstants.postInterstitialAdFrequency);
    if (kDebugMode) {
      debugPrint(
        '[PostAdPolicy] show eligible: pending=$nextPending shownToday=$shownToday',
      );
    }
    return true;
  }

  Future<void> markAdShown(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await _syncDayBoundary(prefs, userId);
    final shownKey = _key(_shownTodayKeyPrefix, userId);
    final nextShown = (prefs.getInt(shownKey) ?? 0) + 1;
    await prefs.setInt(shownKey, nextShown);
    await prefs.setInt(_key(_pendingKeyPrefix, userId), 0);
    if (kDebugMode) {
      debugPrint('[PostAdPolicy] mark shown: shownToday=$nextShown');
    }
  }

  Future<bool> shouldShowNoticeDialog(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_key(_noticeSkipKeyPrefix, userId)) ?? false);
  }

  Future<void> setNoticeSkip(String userId, bool skip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_noticeSkipKeyPrefix, userId), skip);
  }

  Future<String> debugState(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await _syncDayBoundary(prefs, userId);
    final pending = prefs.getInt(_key(_pendingKeyPrefix, userId)) ?? 0;
    final shownToday = prefs.getInt(_key(_shownTodayKeyPrefix, userId)) ?? 0;
    final day = prefs.getString(_key(_dayKeyPrefix, userId)) ?? '-';
    final skipNotice =
        prefs.getBool(_key(_noticeSkipKeyPrefix, userId)) ?? false;
    return 'pending=$pending shownToday=$shownToday day=$day skipNotice=$skipNotice';
  }

  Future<void> _syncDayBoundary(SharedPreferences prefs, String userId) async {
    final today = _todayKey();
    final dayKey = _key(_dayKeyPrefix, userId);
    final savedDay = prefs.getString(dayKey);
    if (savedDay == today) return;

    await prefs.setString(dayKey, today);
    await prefs.setInt(_key(_shownTodayKeyPrefix, userId), 0);
    await prefs.setInt(_key(_pendingKeyPrefix, userId), 0);
  }

  String _key(String prefix, String userId) => '$prefix$userId';

  String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }
}
