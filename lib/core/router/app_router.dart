import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/email_verification_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/home/presentation/screens/main_shell.dart';
import '../../features/post/presentation/screens/create_post_screen.dart';
import '../../features/post/presentation/screens/post_detail_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/settings_screen.dart';
import '../../features/profile/presentation/screens/avatar_edit_screen.dart';
import '../../features/profile/presentation/screens/about_app_screen.dart';
import '../../features/profile/presentation/screens/legal_document_screen.dart';
import '../../features/profile/presentation/screens/subscription_screen.dart';
import '../../features/circle/presentation/screens/circles_screen.dart';
import '../../features/circle/presentation/screens/circle_detail_screen.dart';
import '../../features/circle/presentation/screens/edit_circle_screen.dart';
import '../../features/circle/presentation/screens/create_circle_screen.dart';
import '../../shared/models/circle_model.dart';
import '../../features/circle/presentation/screens/join_requests_screen.dart';
import '../../features/circle/presentation/screens/members_list_screen.dart';
import '../../features/stamps/presentation/screens/stamp_sheet_screen.dart';
import '../../features/stamps/presentation/screens/stamp_sheet_archives_screen.dart';
import '../../features/stamps/presentation/screens/stamp_sheet_catalog_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/admin/presentation/screens/admin_review_screen.dart';
import '../../features/admin/presentation/screens/admin_inquiry_list_screen.dart';
import '../../features/admin/presentation/screens/admin_inquiry_detail_screen.dart';
import '../../features/admin/presentation/screens/admin_reports_screen.dart';
import '../../features/admin/presentation/screens/admin_report_content_screen.dart';
import '../../features/settings/presentation/screens/inquiry_list_screen.dart';
import '../../features/settings/presentation/screens/inquiry_form_screen.dart';
import '../../features/settings/presentation/screens/inquiry_detail_screen.dart';
import '../../features/admin/presentation/screens/ban_appeal_screen.dart';
import '../../features/admin/presentation/screens/admin_ban_users_screen.dart';
import '../../shared/models/avatar_parts_model.dart';
import '../../shared/providers/auth_provider.dart';
import '../constants/app_messages.dart';
import '../constants/avatar_assets.dart';

class AuthStateNotifier extends ChangeNotifier {
  AuthStateNotifier(this._ref) {
    _ref.listen(authStateProvider, (previous, next) {
      notifyListeners();
    });
  }
  final Ref _ref;
}

final _authStateNotifierProvider = Provider<AuthStateNotifier>((ref) {
  return AuthStateNotifier(ref);
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.watch(_authStateNotifierProvider);

  return GoRouter(
    initialLocation: '/home',
    debugLogDiagnostics: true,
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final currentUser = ref.read(firebaseAuthProvider).currentUser;
      final isLoggedIn = currentUser != null;
      final isVerified = currentUser?.emailVerified ?? false;

      final location = state.uri.path;
      final isPublicAuthRoute =
          location.startsWith('/login') ||
          location.startsWith('/register') ||
          location.startsWith('/onboarding');
      final isVerifyRoute = location.startsWith('/email-verify');

      if (!isLoggedIn) {
        debugPrint(
          '[ROUTER] Not logged in: location=$location, isVerifyRoute=$isVerifyRoute, isPublicAuthRoute=$isPublicAuthRoute',
        );
        if (isVerifyRoute) {
          debugPrint('[ROUTER] 竊・Redirecting to /register');
          return '/register';
        }
        if (!isPublicAuthRoute) {
          debugPrint('[ROUTER] 竊・Redirecting to /onboarding');
          return '/onboarding';
        }
        return null;
      }

      if (isLoggedIn && !isVerified) {
        if (!isVerifyRoute) return '/email-verify';
        return null;
      }

      if (isLoggedIn && isVerified && (isPublicAuthRoute || isVerifyRoute)) {
        return '/home';
      }

      return null;
    },
    routes: [
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
      GoRoute(
        path: '/email-verify',
        name: 'emailVerify',
        builder: (context, state) => const EmailVerificationScreen(),
      ),

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
            path: '/stamps',
            name: 'stamps',
            builder: (context, state) => const StampSheetScreen(),
          ),
          GoRoute(
            path: '/stamps/catalog',
            name: 'stampCatalog',
            builder: (context, state) => const StampSheetCatalogScreen(),
          ),
          GoRoute(
            path: '/stamps/archives',
            name: 'stampArchives',
            builder: (context, state) => const StampSheetArchivesScreen(),
          ),
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (context, state) => const ProfileScreen(),
          ),
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

      GoRoute(
        path: '/create-post',
        name: 'createPost',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final circleId = extra?['circleId'] as String?;
          return CreatePostScreen(circleId: circleId);
        },
      ),

      GoRoute(
        path: '/post/:postId',
        name: 'postDetail',
        builder: (context, state) {
          final postId = state.pathParameters['postId']!;
          return PostDetailScreen(postId: postId);
        },
      ),

      GoRoute(
        path: '/circle/:circleId',
        name: 'circleDetail',
        builder: (context, state) {
          final circleId = state.pathParameters['circleId']!;
          return CircleDetailScreen(circleId: circleId);
        },
      ),

      GoRoute(
        path: '/create-circle',
        name: 'createCircle',
        builder: (context, state) => const CreateCircleScreen(),
      ),

      GoRoute(
        path: '/circle/:circleId/edit',
        name: 'editCircle',
        builder: (context, state) {
          final circleId = state.pathParameters['circleId']!;
          final circle = state.extra as CircleModel;
          return EditCircleScreen(circleId: circleId, circle: circle);
        },
      ),

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
            subOwnerId: extra['subOwnerId'] as String?,
            memberIds: List<String>.from(extra['memberIds'] as List),
          );
        },
      ),

      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/about',
        name: 'about',
        builder: (context, state) => const AboutAppScreen(),
      ),
      GoRoute(
        path: '/help',
        name: 'help',
        builder: (context, state) => LegalDocumentScreen(
          title: AppMessages.profile.helpTitle,
          assetPath: 'docs/HELP.md',
        ),
      ),
      GoRoute(
        path: '/terms',
        name: 'terms',
        builder: (context, state) => LegalDocumentScreen(
          title: AppMessages.profile.termsTitle,
          assetPath: 'docs/TERMS_OF_SERVICE.md',
        ),
      ),
      GoRoute(
        path: '/privacy',
        name: 'privacy',
        builder: (context, state) => LegalDocumentScreen(
          title: AppMessages.profile.privacyPolicyTitle,
          assetPath: 'docs/PRIVACY_POLICY.md',
        ),
      ),
      GoRoute(
        path: '/premium',
        name: 'premium',
        builder: (context, state) => const SubscriptionScreen(),
      ),
      GoRoute(
        path: '/avatar-edit',
        name: 'avatarEdit',
        builder: (context, state) {
          final parts = state.extra is AvatarParts
              ? state.extra! as AvatarParts
              : AvatarAssets.defaultParts();
          return AvatarEditScreen(initialParts: parts);
        },
      ),

      GoRoute(
        path: '/notifications',
        name: 'notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),

      GoRoute(
        path: '/profile/:userId',
        name: 'profileDetail',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return ProfileScreen(
            key: ValueKey('profileDetail_$userId'),
            userId: userId,
          );
        },
      ),

      GoRoute(
        path: '/admin-review',
        name: 'adminReview',
        builder: (context, state) => const AdminReviewScreen(),
      ),

      GoRoute(
        path: '/inquiry',
        name: 'inquiryList',
        builder: (context, state) => const InquiryListScreen(),
      ),

      GoRoute(
        path: '/inquiry/new',
        name: 'inquiryForm',
        builder: (context, state) => const InquiryFormScreen(),
      ),

      GoRoute(
        path: '/inquiry/:inquiryId',
        name: 'inquiryDetail',
        builder: (context, state) {
          final inquiryId = state.pathParameters['inquiryId']!;
          return InquiryDetailScreen(inquiryId: inquiryId);
        },
      ),

      GoRoute(
        path: '/admin/inquiries',
        name: 'adminInquiryList',
        builder: (context, state) => const AdminInquiryListScreen(),
      ),

      GoRoute(
        path: '/admin/reports',
        name: 'adminReports',
        builder: (context, state) => const AdminReportsScreen(),
      ),

      GoRoute(
        path: '/admin/reports/content/:contentId',
        name: 'adminReportContent',
        builder: (context, state) {
          final contentId = state.pathParameters['contentId']!;
          return AdminReportContentScreen(contentId: contentId);
        },
      ),

      GoRoute(
        path: '/admin/user/:userId',
        name: 'adminUserProfile',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return ProfileScreen(userId: userId);
        },
      ),

      GoRoute(
        path: '/admin/inquiry/:inquiryId',
        name: 'adminInquiryDetail',
        builder: (context, state) {
          final inquiryId = state.pathParameters['inquiryId']!;
          return AdminInquiryDetailScreen(inquiryId: inquiryId);
        },
      ),

      GoRoute(
        path: '/admin/ban-users',
        name: 'adminBanUsers',
        builder: (context, state) => const AdminBanUsersScreen(),
      ),

      GoRoute(
        path: '/ban-appeal',
        name: 'banAppeal',
        builder: (context, state) {
          final extra = state.extra;
          String? appealId;
          String? targetUserId;

          if (extra is String) {
            appealId = extra;
          } else if (extra is Map<String, dynamic>) {
            appealId = extra['appealId'] as String?;
            targetUserId = extra['targetUserId'] as String?;
          }

          return BanAppealScreen(
            appealId: appealId,
            targetUserId: targetUserId,
          );
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('剥', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              AppMessages.error.notFoundTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              AppMessages.error.notFoundDescription,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/home'),
              child: Text(AppMessages.label.backToHome),
            ),
          ],
        ),
      ),
    ),
  );
});
