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
import '../../features/tasks/presentation/screens/tasks_screen.dart';
import '../../shared/providers/auth_provider.dart';

/// アプリのルーター設定
final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  
  return GoRouter(
    initialLocation: '/home',
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation == '/login' || 
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
            builder: (context, state) => const CirclesScreen(),
          ),
          GoRoute(
            path: '/tasks',
            name: 'tasks',
            builder: (context, state) => const TasksScreen(),
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
        builder: (context, state) => const CreatePostScreen(),
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
      
      // 設定
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      
      // 投稿詳細画面からの遷移用（ナビバーなし）
      GoRoute(
        path: '/profile/:userId',
        name: 'profileDetail',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return ProfileScreen(userId: userId);
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '🔍',
              style: TextStyle(fontSize: 64),
            ),
            const SizedBox(height: 16),
            Text(
              'あれ？ページが見つからないよ',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '大丈夫、ホームに戻ろう！',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
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

