import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../models/avatar_parts_model.dart';
import '../../core/constants/app_constants.dart';
import '../services/subscription_service.dart';
import '../services/reaction_sync_service.dart';
import '../services/reaction_limit_service.dart';

/// FirebaseAuthインスタンス
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

/// Firestoreインスタンス
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

/// 認証状態の監視（emailVerifiedの更新も拾う）
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).userChanges();
});

/// 現在のユーザー情報
final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  final firestore = ref.watch(firestoreProvider);

  return authState.when(
    data: (user) {
      if (user == null) return Stream.value(null);
      return firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .asyncMap((doc) async {
            if (doc.exists) {
              return UserModel.fromFirestore(doc);
            }
            // Self-heal: auth user exists but users/{uid} is missing.
            await _bootstrapMissingUserDoc(firestore, user);
            final reloaded = await firestore
                .collection('users')
                .doc(user.uid)
                .get();
            if (!reloaded.exists) return null;
            return UserModel.fromFirestore(reloaded);
          });
    },
    loading: () => Stream.value(null),
    error: (e, _) => Stream.value(null),
  );
});

Future<void> _bootstrapMissingUserDoc(
  FirebaseFirestore firestore,
  User user,
) async {
  final displayName = (user.displayName != null && user.displayName!.trim().isNotEmpty)
      ? user.displayName!.trim()
      : 'ゲスト';
  final now = DateTime.now();
  final model = UserModel(
    uid: user.uid,
    email: user.email ?? '',
    displayName: displayName,
    virtue: AppConstants.virtueInitial,
    createdAt: now,
    updatedAt: now,
  );
  try {
    await firestore.collection('users').doc(user.uid).set(model.toFirestore());
    debugPrint('AuthProvider: bootstrapped missing users/${user.uid}');
  } catch (e, st) {
    debugPrint('AuthProvider: failed to bootstrap users/${user.uid}: $e');
    debugPrint('$st');
  }
}

/// 現在のユーザーが管理者かどうか
final isAdminProvider = StreamProvider<bool>((ref) {
  final authState = ref.watch(authStateProvider);

  return authState.when(
    data: (user) async* {
      if (user == null) {
        yield false;
        return;
      }

      // Custom Claimsから管理者フラグを取得
      final idTokenResult = await user.getIdTokenResult(
        true,
      ); // forceRefresh: true
      final isAdmin = idTokenResult.claims?['admin'] == true;
      yield isAdmin;
    },
    loading: () => Stream.value(false),
    error: (e, _) => Stream.value(false),
  );
});

/// 認証サービス
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthService(this._auth, this._firestore);

  /// メールでサインアップ
  Future<UserModel?> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    int avatarIndex = 0,
    AvatarParts? avatarParts,
    String? namePrefix,
    String? nameSuffix,
  }) async {
    UserCredential? credential;
    try {
      debugPrint('AuthService: Starting signUp for email: $email');

      credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      debugPrint(
        'AuthService: Firebase Auth user created: ${credential.user?.uid}',
      );

      if (credential.user != null) {
        final user = UserModel(
          uid: credential.user!.uid,
          email: email,
          displayName: displayName,
          avatarIndex: avatarIndex,
          avatarParts: avatarParts,
          virtue: AppConstants.virtueInitial,
          namePrefix: namePrefix,
          nameSuffix: nameSuffix,
          tutorialPhase1Completed: false,
          tutorialPhase2Completed: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        debugPrint('AuthService: UserModel created, saving to Firestore...');
        debugPrint('AuthService: UserModel data: ${user.toFirestore()}');

        try {
          await _firestore
              .collection('users')
              .doc(credential.user!.uid)
              .set(user.toFirestore());
        } catch (e, st) {
          debugPrint('AuthService: Firestore user doc creation failed: $e');
          debugPrint('AuthService: Firestore user doc stack trace: $st');
          // Rollback auth user to prevent orphan account without users/{uid}.
          try {
            await credential.user!.delete();
            debugPrint(
              'AuthService: Rolled back auth user ${credential.user!.uid}',
            );
          } catch (rollbackError, rollbackSt) {
            debugPrint('AuthService: Failed to rollback auth user: $rollbackError');
            debugPrint('$rollbackSt');
          }
          rethrow;
        }

        debugPrint('AuthService: User saved to Firestore successfully');

        await SubscriptionService.instance.logIn(credential.user!.uid);

        return user;
      }
      return null;
    } catch (e, stackTrace) {
      debugPrint('AuthService: Error during signUp: $e');
      debugPrint('AuthService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// メールでログイン
  Future<User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (credential.user != null) {
        await SubscriptionService.instance.logIn(credential.user!.uid);
      }
      return credential.user;
    } catch (e) {
      rethrow;
    }
  }

  /// ログアウト
  Future<void> signOut() async {
    // FCMトークンをクリアしてプッシュ通知を停止
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'fcmToken': FieldValue.delete()});
      } catch (e) {
        // トークン削除失敗は無視してログアウト続行
        debugPrint('FCMトークン削除失敗: $e');
      }
      ReactionSyncService.clearForUser(user.uid);
      await ReactionLimitService.clearForUser(user.uid);
    }
    await SubscriptionService.instance.logOut();
    await _auth.signOut();
  }

  /// パスワードリセット
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// ユーザー情報の更新
  Future<void> updateUserProfile({
    required String uid,
    String? displayName,
    String? bio,
    int? avatarIndex,
    AvatarParts? avatarParts,
    String? postMode,
    Map<String, bool>? notificationSettings,
    Map<String, dynamic>? extraUpdates,
  }) async {
    final updates = <String, dynamic>{'updatedAt': Timestamp.now()};

    if (displayName != null) updates['displayName'] = displayName;
    if (bio != null) updates['bio'] = bio;
    if (avatarIndex != null) updates['avatarIndex'] = avatarIndex;
    if (avatarParts != null) updates['avatarParts'] = avatarParts.toMap();
    if (postMode != null) updates['postMode'] = postMode;
    if (notificationSettings != null) {
      updates['notificationSettings'] = notificationSettings;
    }
    if (extraUpdates != null) {
      updates.addAll(extraUpdates);
    }

    await _firestore.collection('users').doc(uid).update(updates);
  }
}

/// 認証サービスプロバイダー
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    ref.watch(firebaseAuthProvider),
    ref.watch(firestoreProvider),
  );
});
