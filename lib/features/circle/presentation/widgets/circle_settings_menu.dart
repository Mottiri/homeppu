import 'package:flutter/material.dart';

import '../../../../core/constants/app_messages.dart';

class CircleSettingsMenu extends StatelessWidget {
  final bool isOwner;
  final bool isAdmin;
  final bool isSubOwner;
  final bool isPublic;
  final VoidCallback onEdit;
  final VoidCallback onRequests;
  final VoidCallback onDelete;

  const CircleSettingsMenu({
    super.key,
    required this.isOwner,
    required this.isAdmin,
    required this.isSubOwner,
    required this.isPublic,
    required this.onEdit,
    required this.onRequests,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final showMenu = isOwner || isAdmin || (isSubOwner && !isPublic);
    if (!showMenu) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
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
        child: const Icon(Icons.more_vert, size: 20),
      ),
      onSelected: (value) {
        if (value == 'delete') {
          onDelete();
        } else if (value == 'requests') {
          onRequests();
        } else if (value == 'edit') {
          onEdit();
        }
      },
      itemBuilder: (context) => [
        if (isOwner || isAdmin)
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                const Icon(
                  Icons.edit_outlined,
                  color: Color(0xFF00ACC1),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(AppMessages.label.edit),
              ],
            ),
          ),
        if (!isPublic)
          PopupMenuItem(
            value: 'requests',
            child: Row(
              children: [
                const Icon(
                  Icons.person_add_outlined,
                  color: Color(0xFF00ACC1),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(AppMessages.circle.joinRequestButton),
              ],
            ),
          ),
        if (isOwner || isAdmin)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  AppMessages.circle.deleteTitle,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
