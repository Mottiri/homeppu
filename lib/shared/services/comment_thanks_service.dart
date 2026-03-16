import 'package:cloud_functions/cloud_functions.dart';
import '../../core/constants/app_constants.dart';

class CommentThanksResult {
  final bool alreadyThanked;
  final int credits;

  const CommentThanksResult({
    required this.alreadyThanked,
    required this.credits,
  });
}

class CommentThanksService {
  final FirebaseFunctions _functions;

  CommentThanksService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);

  Future<CommentThanksResult> likeCommentAsPostOwner(String commentId) async {
    final callable = _functions.httpsCallable('likeCommentAsPostOwner');
    final result = await callable.call({'commentId': commentId});
    final data = Map<String, dynamic>.from(result.data as Map);
    return CommentThanksResult(
      alreadyThanked: data['alreadyThanked'] == true,
      credits: (data['credits'] as num?)?.toInt() ?? 0,
    );
  }
}
