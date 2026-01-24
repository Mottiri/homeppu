import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../shared/models/circle_model.dart';

class CircleActions extends StatelessWidget {
  final CircleModel circle;
  final bool isMember;
  final bool isOwner;
  final bool hasPendingRequest;
  final bool isJoining;
  final bool isLoggedIn;
  final VoidCallback? onLeave;
  final VoidCallback onJoin;
  final VoidCallback onLogin;

  const CircleActions({
    super.key,
    required this.circle,
    required this.isMember,
    required this.isOwner,
    required this.hasPendingRequest,
    required this.isJoining,
    required this.isLoggedIn,
    required this.onLeave,
    required this.onJoin,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            circle.description,
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.grey[700],
            ),
          ),
          if (circle.goal.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Text('🎯', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      circle.goal,
                      style: TextStyle(
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: !isLoggedIn
                ? ElevatedButton(
                    onPressed: onLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  child: Text(AppMessages.circle.loginToJoin),
                  )
                : isMember
                    ? OutlinedButton(
                        onPressed: isOwner ? null : onLeave,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.grey[300]!,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppMessages.circle.joinedLabel,
                              style: TextStyle(
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : hasPendingRequest && !circle.isPublic
                        ? OutlinedButton(
                            onPressed: null,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: Colors.grey[300]!,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.hourglass_empty,
                                  color: Colors.grey[500],
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  AppMessages.circle.requestPendingLabel,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ElevatedButton(
                            onPressed: isJoining ? null : onJoin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: isJoining
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.person_add, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        circle.isPublic
                                            ? AppMessages.circle.joinButton
                                            : AppMessages.circle
                                                .joinRequestButton,
                                      ),
                                    ],
                                  ),
                          ),
          ),
        ],
      ),
    );
  }
}
