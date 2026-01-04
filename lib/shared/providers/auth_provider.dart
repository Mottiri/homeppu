import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../../core/constants/app_constants.dart';

/// FirebaseAuthインスタンス
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

/// Firestoreインスタンス
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

/// 認証状態の監視
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// 現在のユーザー情報
final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  final firestore = ref.watch(firestoreProvider);

  return authState.when(
    data: (user) {
      if (user == null) return Stream.value(null);
      return firestore.collection('users').doc(user.uid).snapshots().map((doc) {
        if (!doc.exists) return null;
        return UserModel.fromFirestore(doc);
      });
    },
    loading: () => Stream.value(null),
    error: (e, _) => Stream.value(null),
  );
});

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
    String? namePrefix,
    String? nameSuffix,
  }) async {
    try {
      debugPrint('AuthService: Starting signUp for email: $email');

      final credential = await _auth.createUserWithEmailAndPassword(
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
          virtue: AppConstants.virtueInitial,
          namePrefix: namePrefix,
          nameSuffix: nameSuffix,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        debugPrint('AuthService: UserModel created, saving to Firestore...');
        debugPrint('AuthService: UserModel data: ${user.toFirestore()}');

        await _firestore
            .collection('users')
            .doc(credential.user!.uid)
            .set(user.toFirestore());

        debugPrint('AuthService: User saved to Firestore successfully');

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
    }
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
    String? postMode,
    Map<String, bool>? notificationSettings,
    Map<String, bool>? autoPostSettings,
  }) async {
    final updates = <String, dynamic>{'updatedAt': Timestamp.now()};

    if (displayName != null) updates['displayName'] = displayName;
    if (bio != null) updates['bio'] = bio;
    if (avatarIndex != null) updates['avatarIndex'] = avatarIndex;
    if (postMode != null) updates['postMode'] = postMode;
    if (notificationSettings != null) {
      updates['notificationSettings'] = notificationSettings;
    }
    if (autoPostSettings != null) {
      updates['autoPostSettings'] = autoPostSettings;
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
