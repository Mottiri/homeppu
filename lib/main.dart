import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';

import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/constants/app_constants.dart';
import 'shared/services/notification_service.dart';

/// グローバルナビゲーションキー（通知タップ時のナビゲーション用）
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase初期化
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // バックグラウンド通知ハンドラーを設定
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // 通知サービス初期化
  await NotificationService().initialize();

  // ロケールデータの初期化 (DateFormat用)
  await initializeDateFormatting('ja');

  runApp(const ProviderScope(child: HomeppuApp()));
}

class HomeppuApp extends ConsumerStatefulWidget {
  const HomeppuApp({super.key});

  @override
  ConsumerState<HomeppuApp> createState() => _HomeppuAppState();
}

class _HomeppuAppState extends ConsumerState<HomeppuApp> {
  @override
  void initState() {
    super.initState();
    // コールバック登録を遅延実行（ルーターの準備を待つ）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupNotificationCallback();
    });
  }

  void _setupNotificationCallback() {
    NotificationService().setNotificationTapCallback((payload) {
      final router = ref.read(appRouterProvider);
      _handleNotificationNavigation(router, payload);
    });
  }

  void _handleNotificationNavigation(
    GoRouter router,
    NotificationPayload payload,
  ) {
    debugPrint('通知ナビゲーション: type=${payload.type}');

    switch (payload.type) {
      // 投稿関連
      case 'comment':
      case 'reaction':
        if (payload.postId != null) {
          router.push('/post/${payload.postId}');
        }
        break;

      // サークル関連
      case 'join_request_received':
        if (payload.circleId != null) {
          router.push(
            '/circle/${payload.circleId}/requests',
            extra: {'circleName': ''},
          );
        }
        break;
      case 'join_request_approved':
        if (payload.circleId != null) {
          router.push('/circle/${payload.circleId}');
        }
        break;
      case 'join_request_rejected':
      case 'circle_deleted':
        router.go('/circles');
        break;

      // タスク関連
      case 'task_reminder':
      case 'task_scheduled':
        if (payload.taskId != null && payload.scheduledAt != null) {
          final scheduledAt = DateTime.tryParse(payload.scheduledAt!);
          router.go(
            '/tasks',
            extra: {
              'highlightTaskId': payload.taskId,
              'highlightRequestId': DateTime.now().millisecondsSinceEpoch,
              'targetDate': scheduledAt,
              'forceRefresh': true,
            },
          );
        } else {
          router.go('/tasks');
        }
        break;

      // 問い合わせ関連（ユーザー向け）
      case 'inquiry_reply':
      case 'inquiry_status_changed':
      case 'inquiry_deletion_warning':
        if (payload.inquiryId != null) {
          router.push('/inquiry/${payload.inquiryId}');
        }
        break;

      // 問い合わせ関連（管理者向け）
      case 'inquiry_received':
      case 'inquiry_user_reply':
        if (payload.inquiryId != null) {
          router.push('/admin/inquiry/${payload.inquiryId}');
        }
        break;

      // 管理者向け通報
      case 'admin_report':
        if (payload.contentId != null) {
          router.push('/admin/reports/content/${payload.contentId}');
        } else if (payload.reportId != null) {
          router.push('/admin/reports/${payload.reportId}');
        } else {
          router.push('/admin/reports');
        }
        break;

      // 投稿削除・非表示
      case 'post_deleted':
        router.go('/notifications');
        break;
      case 'post_hidden':
        if (payload.postId != null) {
          router.push('/post/${payload.postId}');
        }
        break;

      // デフォルト
      default:
        router.go('/notifications');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja'), // 日本語
      ],
      builder: (context, child) {
        return MediaQuery(
          // システムフォントスケールを制限（読みやすさ維持）
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.2),
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
