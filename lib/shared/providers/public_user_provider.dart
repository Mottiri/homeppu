import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/avatar_parts_model.dart';
import 'auth_provider.dart';

final publicUserAvatarPartsProvider =
    FutureProvider.family<AvatarParts?, String>((ref, userId) async {
  if (userId.isEmpty) {
    return null;
  }
  final firestore = ref.watch(firestoreProvider);
  final doc = await firestore.collection('publicUsers').doc(userId).get();
  if (!doc.exists) {
    return null;
  }
  return AvatarParts.fromMap(doc.data()?['avatarParts']);
});
