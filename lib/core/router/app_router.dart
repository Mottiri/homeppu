import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/home/presentation/screens/main_shell.dart';
import '../../features/post/presentation/screens/create_post_screen.dart';
import '../../features/post/presentation/screens/post_detail_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/settings_screen.dart';
import '../../features/circle/presentation/screens/circles_screen.dart';
import '../../features/circle/presentation/screens/circle_detail_screen.dart';
import '../../features/circle/presentation/screens/edit_circle_screen.dart';
import '../../features/circle/presentation/screens/create_circle_screen.dart';
import '../../shared/models/circle_model.dart';
import '../../features/circle/presentation/screens/join_requests_screen.dart';
import '../../features/circle/presentation/screens/members_list_screen.dart';
import '../../features/tasks/presentation/screens/tasks_screen.dart';
import '../../features/goals/presentation/screens/goal_list_screen.dart';
import '../../features/goals/presentation/screens/create_goal_screen.dart';
import '../../features/goals/presentation/screens/goal_detail_screen.dart';
import '../../features/goals/presentation/screens/completed_goals_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/admin/presentation/screens/admin_review_screen.dart';
import '../../features/admin/presentation/screens/admin_inquiry_list_screen.dart';
import '../../features/admin/presentation/screens/admin_inquiry_detail_screen.dart';
import '../../features/admin/presentation/screens/admin_reports_screen.dart';
import '../../features/admin/presentation/screens/admin_report_detail_screen.dart';
import '../../features/settings/presentation/screens/inquiry_list_screen.dart';
import '../../features/settings/presentation/screens/inquiry_form_screen.dart';
import '../../features/settings/presentation/screens/inquiry_detail_screen.dart';
import '../../shared/providers/auth_provider.dart';

/// アプリのルーター設定
final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/home',
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/onboarding';

      // 未ログインでauth以外にアクセス → ログイン画面へ
      if (!isLoggedIn && !isAuthRoute) {
        return '/onboarding';
      }

      // ログイン済みでauth画面にアクセス → ホームへ
      if (isLoggedIn && isAuthRoute) {
        return '/home';
      }

      return null;
    },
    routes: [
      // 認証関連
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),

      // メイン画面（シェルルート）
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/circles',
            name: 'circles',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              final forceRefresh = extra?['forceRefresh'] as bool? ?? false;
              return CirclesScreen(
                key: forceRefresh
                    ? ValueKey(
                        'circles_${DateTime.now().millisecondsSinceEpoch}',
                      )
                    : null,
              );
            },
          ),
          GoRoute(
            path: '/tasks',
            name: 'tasks',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              final highlightTaskId = extra?['highlightTaskId'] as String?;
              final targetDate = extra?['targetDate'] as DateTime?;
              final targetCategoryId = extra?['targetCategoryId'] as String?;
              final forceRefresh = extra?['forceRefresh'] as bool? ?? false;
              // forceRefresh または highlightTaskId がある場合は強制的に再作成
              return TasksScreen(
                key: (forceRefresh || highlightTaskId != null)
                    ? ValueKey('tasks_${DateTime.now().millisecondsSinceEpoch}')
                    : null,
                highlightTaskId: highlightTaskId,
                targetDate: targetDate,
                targetCategoryId: targetCategoryId,
              );
            },
          ),
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          // ShellRoute内のユーザープロフィール（ナビバー表示）
          GoRoute(
            path: '/user/:userId',
            name: 'userProfile',
            builder: (context, state) {
              final userId = state.pathParameters['userId']!;
              return ProfileScreen(userId: userId);
            },
          ),
        ],
      ),

      // 投稿作成
      GoRoute(
        path: '/create-post',
        name: 'createPost',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final circleId = extra?['circleId'] as String?;
          return CreatePostScreen(circleId: circleId);
        },
      ),

      // 投稿詳細
      GoRoute(
        path: '/post/:postId',
        name: 'postDetail',
        builder: (context, state) {
          final postId = state.pathParameters['postId']!;
          return PostDetailScreen(postId: postId);
        },
      ),

      // サークル詳細
      GoRoute(
        path: '/circle/:circleId',
        name: 'circleDetail',
        builder: (context, state) {
          final circleId = state.pathParameters['circleId']!;
          return CircleDetailScreen(circleId: circleId);
        },
      ),

      // サークル作成
      GoRoute(
        path: '/create-circle',
        name: 'createCircle',
        builder: (context, state) => const CreateCircleScreen(),
      ),

      // サークル編集
      GoRoute(
        path: '/circle/:circleId/edit',
        name: 'editCircle',
        builder: (context, state) {
          final circleId = state.pathParameters['circleId']!;
          final circle = state.extra as CircleModel;
          return EditCircleScreen(circleId: circleId, circle: circle);
        },
      ),

      // 参加申請管理
      GoRoute(
        path: '/circle/:circleId/requests',
        name: 'joinRequests',
        builder: (context, state) {
          final circleId = state.pathParameters['circleId']!;
          final extra = state.extra as Map<String, dynamic>?;
          final circleName = extra?['circleName'] as String? ?? '';
          return JoinRequestsScreen(circleId: circleId, circleName: circleName);
        },
      ),

      // メンバー一覧
      GoRoute(
        path: '/circle/:circleId/members',
        name: 'membersList',
        builder: (context, state) {
          final circleId = state.pathParameters['circleId']!;
          final extra = state.extra as Map<String, dynamic>;
          return MembersListScreen(
            circleId: circleId,
            circleName: extra['circleName'] as String,
            ownerId: extra['ownerId'] as String,
            memberIds: List<String>.from(extra['memberIds'] as List),
          );
        },
      ),

      // 設定
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),

      // 通知
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),

      // 目標作成
      GoRoute(
        path: '/goals/create',
        name: 'createGoal',
        builder: (context, state) => const CreateGoalScreen(),
      ),

      // 目標一覧
      GoRoute(
        path: '/goals',
        name: 'goals',
        builder: (context, state) => const GoalListScreen(),
      ),

      // 殿堂入り（達成した目標）
      GoRoute(
        path: '/goals/completed',
        name: 'completedGoals',
        builder: (context, state) => const CompletedGoalsScreen(),
      ),

      // 目標詳細
      GoRoute(
        path: '/goals/detail/:goalId',
        name: 'goalDetail',
        builder: (context, state) {
          final goalId = state.pathParameters['goalId']!;
          return GoalDetailScreen(goalId: goalId);
        },
      ),

      // 投稿詳細画面からの遷移用（ナビバーなし）
      GoRoute(
        path: '/profile/:userId',
        name: 'profileDetail',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          // ユニークなキーを使用してNavigatorキー重複を防止
          return ProfileScreen(
            key: ValueKey('profileDetail_$userId'),
            userId: userId,
          );
        },
      ),

      // 管理者用レビュー画面
      GoRoute(
        path: '/admin-review',
        name: 'adminReview',
        builder: (context, state) => const AdminReviewScreen(),
      ),

      // 問い合わせ一覧
      GoRoute(
        path: '/inquiry',
        name: 'inquiryList',
        builder: (context, state) => const InquiryListScreen(),
      ),

      // 問い合わせ新規作成
      GoRoute(
        path: '/inquiry/new',
        name: 'inquiryForm',
        builder: (context, state) => const InquiryFormScreen(),
      ),

      // 問い合わせ詳細
      GoRoute(
        path: '/inquiry/:inquiryId',
        name: 'inquiryDetail',
        builder: (context, state) {
          final inquiryId = state.pathParameters['inquiryId']!;
          return InquiryDetailScreen(inquiryId: inquiryId);
        },
      ),

      // 管理者用問い合わせ一覧
      GoRoute(
        path: '/admin/inquiries',
        name: 'adminInquiryList',
        builder: (context, state) => const AdminInquiryListScreen(),
      ),

      // 管理者用通報一覧
      GoRoute(
        path: '/admin/reports',
        name: 'adminReports',
        builder: (context, state) => const AdminReportsScreen(),
      ),

      // 管理者用通報詳細
      GoRoute(
        path: '/admin/reports/:reportId',
        name: 'adminReportDetail',
        builder: (context, state) {
          final reportId = state.pathParameters['reportId']!;
          return AdminReportDetailScreen(reportId: reportId);
        },
      ),

      // 管理者用ユーザープロフィール（ShellRoute外）
      GoRoute(
        path: '/admin/user/:userId',
        name: 'adminUserProfile',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return ProfileScreen(userId: userId);
        },
      ),

      // 管理者用問い合わせ詳細
      GoRoute(
        path: '/admin/inquiry/:inquiryId',
        name: 'adminInquiryDetail',
        builder: (context, state) {
          final inquiryId = state.pathParameters['inquiryId']!;
          return AdminInquiryDetailScreen(inquiryId: inquiryId);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🔍', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              'あれ？ページが見つからないよ',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('大丈夫、ホームに戻ろう！', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/home'),
              child: const Text('ホームへ戻る'),
            ),
          ],
        ),
      ),
    ),
  );
});
