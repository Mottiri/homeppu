import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationPayload {
  final String type;
  final String? postId;
  final String? circleId;
  final String? inquiryId;
  final String? reportId;
  final String? contentId;

  NotificationPayload({
    required this.type,
    this.postId,
    this.circleId,
    this.inquiryId,
    this.reportId,
    this.contentId,
  });

  factory NotificationPayload.fromJson(Map<String, dynamic> json) {
    return NotificationPayload(
      type: json['type'] as String? ?? 'system',
      postId: json['postId'] as String?,
      circleId: json['circleId'] as String?,
      inquiryId: json['inquiryId'] as String?,
      reportId: json['reportId'] as String?,
      contentId: json['contentId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (postId != null) 'postId': postId,
      if (circleId != null) 'circleId': circleId,
      if (inquiryId != null) 'inquiryId': inquiryId,
      if (reportId != null) 'reportId': reportId,
      if (contentId != null) 'contentId': contentId,
    };
  }

  String encode() => jsonEncode(toJson());

  static NotificationPayload? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      if (payload.startsWith('{')) {
        return NotificationPayload.fromJson(
          jsonDecode(payload) as Map<String, dynamic>,
        );
      }
      return NotificationPayload(type: 'comment', postId: payload);
    } catch (e) {
      debugPrint('Failed to decode payload: $e');
      return null;
    }
  }
}

typedef NotificationTapCallback = void Function(NotificationPayload payload);
typedef ForegroundNotificationCallback =
    void Function(NotificationPayload payload, String title, String body);

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  NotificationTapCallback? _onNotificationTap;
  ForegroundNotificationCallback? _onForegroundNotification;

  void setNotificationTapCallback(NotificationTapCallback callback) {
    _onNotificationTap = callback;
  }

  void setForegroundNotificationCallback(
    ForegroundNotificationCallback callback,
  ) {
    _onForegroundNotification = callback;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      debugPrint('Notification permission denied');
      return;
    }

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

    await _updateFcmToken();
    _messaging.onTokenRefresh.listen(_saveFcmToken);
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _handleNotificationOpen(initialMessage);
      });
    }

    _isInitialized = true;
  }

  Future<void> _updateFcmToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _saveFcmToken(token);
      }
    } catch (e) {
      debugPrint('Failed to refresh FCM token: $e');
    }
  }

  Future<void> _saveFcmToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('Saved FCM token');
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint(
      'Foreground push received: ${message.notification?.title}',
    );

    final notification = message.notification;
    if (notification == null) return;

    final payload = NotificationPayload(
      type: message.data['type'] as String? ?? 'system',
      postId: message.data['postId'] as String?,
      circleId: message.data['circleId'] as String?,
      inquiryId: message.data['inquiryId'] as String?,
      reportId: message.data['reportId'] as String?,
      contentId: message.data['contentId'] as String?,
    );

    _onForegroundNotification?.call(
      payload,
      notification.title ?? '',
      notification.body ?? '',
    );

    await _showLocalNotification(
      title: notification.title ?? '',
      body: notification.body ?? '',
      payload: payload.encode(),
    );
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'default_channel',
      'デフォルト通知',
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

  void _onNotificationTapped(NotificationResponse response) {
    final payload = NotificationPayload.decode(response.payload);
    if (payload != null) {
      debugPrint('Notification tapped: type=${payload.type}');
      _onNotificationTap?.call(payload);
    }
  }

  void _handleNotificationOpen(RemoteMessage message) {
    debugPrint('Push opened: data=${message.data}');

    final payload = NotificationPayload(
      type: message.data['type'] as String? ?? 'system',
      postId: message.data['postId'] as String?,
      circleId: message.data['circleId'] as String?,
      inquiryId: message.data['inquiryId'] as String?,
      reportId: message.data['reportId'] as String?,
      contentId: message.data['contentId'] as String?,
    );

    _onNotificationTap?.call(payload);
  }

  Future<void> clearFcmToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'fcmToken': FieldValue.delete(),
    });
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
    'Background push received: ${message.notification?.title}',
  );
}
