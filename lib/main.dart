import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/constants/app_constants.dart';
import 'shared/services/app_check_service.dart';
import 'shared/services/notification_service.dart';
import 'shared/services/subscription_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await AppCheckService.initialize();
  await MobileAds.instance.initialize();

  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null) {
    await SubscriptionService.instance.logIn(currentUser.uid);
  }

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await NotificationService().initialize();

  await initializeDateFormatting('ja');
  timeago.setLocaleMessages('ja', timeago.JaMessages());

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
    debugPrint('Notification tap: type=${payload.type}');

    switch (payload.type) {
      case 'comment':
      case 'reaction':
        if (payload.postId != null) {
          router.push('/post/${payload.postId}');
        }
        break;

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
      case 'circle_settings_changed':
      case 'circle_ghost_warning':
        if (payload.circleId != null) {
          router.push('/circle/${payload.circleId}');
        } else {
          router.go('/circles');
        }
        break;
      case 'circle_ghost_deleted':
        router.go('/circles');
        break;

      case 'inquiry_reply':
      case 'inquiry_status_changed':
      case 'inquiry_deletion_warning':
        if (payload.inquiryId != null) {
          router.push('/inquiry/${payload.inquiryId}');
        }
        break;

      case 'inquiry_received':
      case 'inquiry_user_reply':
        if (payload.inquiryId != null) {
          router.push('/admin/inquiry/${payload.inquiryId}');
        }
        break;

      case 'admin_report':
        if (payload.contentId != null) {
          router.push('/admin/reports/content/${payload.contentId}');
        } else {
          router.push('/admin/reports');
        }
        break;
      case 'review_needed':
        router.push('/admin-review');
        break;

      case 'post_deleted':
        router.go('/notifications');
        break;
      case 'post_hidden':
        if (payload.postId != null) {
          router.push('/post/${payload.postId}');
        }
        break;

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
        Locale('ja'),
      ],
      builder: (context, child) {
        return MediaQuery(
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

