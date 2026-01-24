import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/circle_model.dart';
import 'circle_members_bar.dart';
import 'circle_settings_menu.dart';

class CircleHeader extends StatelessWidget {
  final CircleModel circle;
  final String icon;
  final bool isOwner;
  final bool isAdmin;
  final bool isSubOwner;
  final VoidCallback onShowRules;
  final VoidCallback onShowMembers;
  final VoidCallback onEdit;
  final VoidCallback onRequests;
  final VoidCallback onDelete;

  const CircleHeader({
    super.key,
    required this.circle,
    required this.icon,
    required this.isOwner,
    required this.isAdmin,
    required this.isSubOwner,
    required this.onShowRules,
    required this.onShowMembers,
    required this.onEdit,
    required this.onRequests,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final showMenu = isOwner || isAdmin || (isSubOwner && !circle.isPublic);

    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: Colors.white,
      leading: IconButton(
        onPressed: () => context.pop(),
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
              ),
            ],
          ),
          child: const Icon(Icons.arrow_back_rounded, size: 20),
        ),
      ),
      actions: showMenu
          ? [
              Container(
                margin: const EdgeInsets.only(right: 8),
                child: CircleSettingsMenu(
                  isOwner: isOwner,
                  isAdmin: isAdmin,
                  isSubOwner: isSubOwner,
                  isPublic: circle.isPublic,
                  onEdit: onEdit,
                  onRequests: onRequests,
                  onDelete: onDelete,
                ),
              ),
            ]
          : null,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            circle.coverImageUrl != null
                ? Image.network(
                    circle.coverImageUrl!,
                    fit: BoxFit.cover,
                  )
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primary.withValues(alpha: 0.7),
                          AppColors.primaryLight,
                        ],
                      ),
                    ),
                  ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.3),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: circle.iconImageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.network(
                              circle.iconImageUrl!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Center(
                            child: Text(
                              icon,
                              style: const TextStyle(fontSize: 36),
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                circle.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isOwner)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.9),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.workspace_premium,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        CircleMembersBar(
                          memberCount: circle.memberIds.length,
                          hasRules:
                              circle.rules != null && circle.rules!.isNotEmpty,
                          onMembersTap: onShowMembers,
                          onRulesTap: onShowRules,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
