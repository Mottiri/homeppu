import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
      return firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .map((doc) {
            if (!doc.exists) return null;
            return UserModel.fromFirestore(doc);
          });
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
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
      print('AuthService: Starting signUp for email: $email');
      
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      print('AuthService: Firebase Auth user created: ${credential.user?.uid}');
      
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
        
        print('AuthService: UserModel created, saving to Firestore...');
        print('AuthService: UserModel data: ${user.toFirestore()}');
        
        await _firestore
            .collection('users')
            .doc(credential.user!.uid)
            .set(user.toFirestore());
        
        print('AuthService: User saved to Firestore successfully');
        
        return user;
      }
      return null;
    } catch (e, stackTrace) {
      print('AuthService: Error during signUp: $e');
      print('AuthService: Stack trace: $stackTrace');
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
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': Timestamp.now(),
    };
    
    if (displayName != null) updates['displayName'] = displayName;
    if (bio != null) updates['bio'] = bio;
    if (avatarIndex != null) updates['avatarIndex'] = avatarIndex;
    if (postMode != null) updates['postMode'] = postMode;
    
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


