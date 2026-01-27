import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 通知タップ時のペイロード
class NotificationPayload {
  final String type;
  final String? postId;
  final String? circleId;
  final String? taskId;
  final String? goalId;
  final String? inquiryId;
  final String? reportId;
  final String? contentId;
  final String? scheduledAt;

  NotificationPayload({
    required this.type,
    this.postId,
    this.circleId,
    this.taskId,
    this.goalId,
    this.inquiryId,
    this.reportId,
    this.contentId,
    this.scheduledAt,
  });

  factory NotificationPayload.fromJson(Map<String, dynamic> json) {
    return NotificationPayload(
      type: json['type'] as String? ?? 'system',
      postId: json['postId'] as String?,
      circleId: json['circleId'] as String?,
      taskId: json['taskId'] as String?,
      goalId: json['goalId'] as String?,
      inquiryId: json['inquiryId'] as String?,
      reportId: json['reportId'] as String?,
      contentId: json['contentId'] as String?,
      scheduledAt: json['scheduledAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (postId != null) 'postId': postId,
      if (circleId != null) 'circleId': circleId,
      if (taskId != null) 'taskId': taskId,
      if (goalId != null) 'goalId': goalId,
      if (inquiryId != null) 'inquiryId': inquiryId,
      if (reportId != null) 'reportId': reportId,
      if (contentId != null) 'contentId': contentId,
      if (scheduledAt != null) 'scheduledAt': scheduledAt,
    };
  }

  String encode() => jsonEncode(toJson());

  static NotificationPayload? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      // JSON形式かどうかを確認
      if (payload.startsWith('{')) {
        return NotificationPayload.fromJson(jsonDecode(payload));
      }
      // 旧形式（postIdのみ）への互換性対応
      return NotificationPayload(type: 'comment', postId: payload);
    } catch (e) {
      debugPrint('Failed to decode payload: $e');
      return null;
    }
  }
}

/// 通知タップ時のコールバック型
typedef NotificationTapCallback = void Function(NotificationPayload payload);

/// プッシュ通知サービス
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  NotificationTapCallback? _onNotificationTap;

  /// 通知タップ時のコールバックを登録
  void setNotificationTapCallback(NotificationTapCallback callback) {
    _onNotificationTap = callback;
  }

  /// 初期化
  Future<void> initialize() async {
    if (_isInitialized) return;

    // 通知許可をリクエスト
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('通知許可: 許可されました');
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
      debugPrint('通知許可: 仮許可されました');
    } else {
      debugPrint('通知許可: 拒否されました');
      return;
    }

    // ローカル通知の初期化
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // FCMトークンを取得してFirestoreに保存
    await _updateFcmToken();

    // トークンリフレッシュを監視
    _messaging.onTokenRefresh.listen(_saveFcmToken);

    // フォアグラウンドでのメッセージ受信
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // バックグラウンドからアプリを開いた時
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

    // アプリが終了状態から起動された場合の通知を確認
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      // 少し遅延させてルーターの準備を待つ
      Future.delayed(const Duration(milliseconds: 500), () {
        _handleNotificationOpen(initialMessage);
      });
    }

    _isInitialized = true;
  }

  /// FCMトークンを更新
  Future<void> _updateFcmToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _saveFcmToken(token);
      }
    } catch (e) {
      debugPrint('FCMトークン取得エラー: $e');
    }
  }

  /// FCMトークンをFirestoreに保存
  Future<void> _saveFcmToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('FCMトークンを保存しました');
  }

  /// フォアグラウンドメッセージ処理
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('フォアグラウンド通知受信: ${message.notification?.title}');

    final notification = message.notification;
    if (notification == null) return;

    // ペイロードを作成
    final payload = NotificationPayload(
      type: message.data['type'] as String? ?? 'system',
      postId: message.data['postId'] as String?,
      circleId: message.data['circleId'] as String?,
      taskId: message.data['taskId'] as String?,
      goalId: message.data['goalId'] as String?,
      inquiryId: message.data['inquiryId'] as String?,
      reportId: message.data['reportId'] as String?,
      contentId: message.data['contentId'] as String?,
      scheduledAt: message.data['scheduledAt'] as String?,
    );

    // ローカル通知として表示
    await _showLocalNotification(
      title: notification.title ?? '',
      body: notification.body ?? '',
      payload: payload.encode(),
    );
  }

  /// ローカル通知を表示
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'default_channel',
      'デフォルト',
      channelDescription: '一般的な通知',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// 通知タップ時の処理（ローカル通知用）
  void _onNotificationTapped(NotificationResponse response) {
    final payload = NotificationPayload.decode(response.payload);
    if (payload != null) {
      debugPrint('通知タップ: type=${payload.type}, postId=${payload.postId}');
      _onNotificationTap?.call(payload);
    }
  }

  /// バックグラウンドから開いた時の処理（FCM通知用）
  void _handleNotificationOpen(RemoteMessage message) {
    debugPrint('通知から起動: data=${message.data}');

    final payload = NotificationPayload(
      type: message.data['type'] as String? ?? 'system',
      postId: message.data['postId'] as String?,
      circleId: message.data['circleId'] as String?,
      taskId: message.data['taskId'] as String?,
      goalId: message.data['goalId'] as String?,
      inquiryId: message.data['inquiryId'] as String?,
      reportId: message.data['reportId'] as String?,
      contentId: message.data['contentId'] as String?,
      scheduledAt: message.data['scheduledAt'] as String?,
    );

    _onNotificationTap?.call(payload);
  }

  /// FCMトークンをクリア（ログアウト時）
  Future<void> clearFcmToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'fcmToken': FieldValue.delete(),
    });
  }
}

/// バックグラウンドメッセージハンドラー（トップレベル関数）
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('バックグラウンド通知受信: ${message.notification?.title}');
}
