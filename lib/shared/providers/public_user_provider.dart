import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/avatar_parts_model.dart';
import 'auth_provider.dart';

final publicUserDocProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) async {
  if (userId.isEmpty) {
    return null;
  }
  final firestore = ref.watch(firestoreProvider);
  final doc = await firestore.collection('publicUsers').doc(userId).get();
  if (!doc.exists) {
    return null;
  }
  return doc.data();
});

final publicUserAvatarPartsProvider =
    Provider.family<AvatarParts?, String>((ref, userId) {
  final data = ref.watch(publicUserDocProvider(userId)).valueOrNull;
  return AvatarParts.fromMap(data?['avatarParts']);
});

final publicUserDisplayNameProvider =
    Provider.family<String?, String>((ref, userId) {
  final data = ref.watch(publicUserDocProvider(userId)).valueOrNull;
  return data?['displayName'] as String?;
});
