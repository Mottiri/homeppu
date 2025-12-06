import 'package:cloud_functions/cloud_functions.dart';

class FollowService {
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  /// ユーザーをフォローする
  Future<void> followUser(String targetUserId) async {
    final callable = _functions.httpsCallable('followUser');
    await callable.call({'targetUserId': targetUserId});
  }

  /// フォローを解除する
  Future<void> unfollowUser(String targetUserId) async {
    final callable = _functions.httpsCallable('unfollowUser');
    await callable.call({'targetUserId': targetUserId});
  }

  /// フォロー状態を確認する
  Future<bool> getFollowStatus(String targetUserId) async {
    final callable = _functions.httpsCallable('getFollowStatus');
    final result = await callable.call({'targetUserId': targetUserId});
    return result.data['isFollowing'] ?? false;
  }
}


