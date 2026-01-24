import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/widgets/avatar_selector.dart';

class ProfileHeader extends StatelessWidget {
  final UserModel user;
  final bool isOwnProfile;
  final String fallbackHeaderImage;
  final Color primaryAccent;
  final Color secondaryAccent;
  final VoidCallback? onBack;
  final VoidCallback? onOpenSettings;
  final Widget? adminAction;

  const ProfileHeader({
    super.key,
    required this.user,
    required this.isOwnProfile,
    required this.fallbackHeaderImage,
    required this.primaryAccent,
    required this.secondaryAccent,
    this.onBack,
    this.onOpenSettings,
    this.adminAction,
  });

  @override
  Widget build(BuildContext context) {
    final headerUrl = user.headerImageUrl;

    return SliverToBoxAdapter(
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRect(
                child: SizedBox(
                  width: double.infinity,
                  height: 180,
                  child: headerUrl != null
                      ? Image.network(
                          headerUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Image.asset(
                            fallbackHeaderImage,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Image.asset(
                          fallbackHeaderImage,
                          fit: BoxFit.cover,
                        ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFDF8F3),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                ),
              ),
              if (!isOwnProfile && onBack != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    onPressed: onBack,
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black26,
                    ),
                  ),
                ),
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    if (adminAction != null) adminAction!,
                    if (isOwnProfile && onOpenSettings != null)
                      IconButton(
                        onPressed: onOpenSettings,
                        icon: const Icon(
                          Icons.settings_outlined,
                          color: Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black26,
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                bottom: -55,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [primaryAccent, secondaryAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryAccent.withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: AvatarWidget(
                        avatarIndex: user.avatarIndex,
                        size: 100,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 60, 16, 0),
            child: Column(
              children: [
                Text(
                  user.displayName,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                if (user.bio != null && user.bio!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      user.bio!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
