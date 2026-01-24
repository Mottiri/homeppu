import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

class ProfileActions extends StatelessWidget {
  final bool isFollowing;
  final bool isFollowLoading;
  final Color primaryAccent;
  final Color secondaryAccent;
  final VoidCallback onToggleFollow;
  final VoidCallback onMessage;

  const ProfileActions({
    super.key,
    required this.isFollowing,
    required this.isFollowLoading,
    required this.primaryAccent,
    required this.secondaryAccent,
    required this.onToggleFollow,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: isFollowing
                      ? null
                      : LinearGradient(
                          colors: [primaryAccent, secondaryAccent],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                  color: isFollowing ? Colors.grey.shade200 : null,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: ElevatedButton(
                  onPressed: isFollowLoading ? null : onToggleFollow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor:
                        isFollowing ? AppColors.textPrimary : Colors.white,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: isFollowLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          isFollowing ? 'フォロー中' : 'フォロー',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryAccent, secondaryAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: IconButton(
                onPressed: onMessage,
                icon: const Icon(
                  Icons.mail_outline,
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
