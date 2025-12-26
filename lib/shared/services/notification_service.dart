import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// プッシュ通知サービス
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

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

    // ローカル通知として表示
    await _showLocalNotification(
      title: notification.title ?? '',
      body: notification.body ?? '',
      payload: message.data['postId'] ?? '',
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

  /// 通知タップ時の処理
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      // TODO: 投稿詳細画面に遷移
      debugPrint('通知タップ: postId=$payload');
    }
  }

  /// バックグラウンドから開いた時の処理
  void _handleNotificationOpen(RemoteMessage message) {
    final postId = message.data['postId'];
    if (postId != null) {
      // TODO: 投稿詳細画面に遷移
      debugPrint('通知から起動: postId=$postId');
    }
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
