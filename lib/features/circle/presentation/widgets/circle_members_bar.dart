import 'package:flutter/material.dart';

import '../../../../core/constants/app_messages.dart';

class CircleMembersBar extends StatelessWidget {
  final int memberCount;
  final bool hasRules;
  final VoidCallback onMembersTap;
  final VoidCallback onRulesTap;

  const CircleMembersBar({
    super.key,
    required this.memberCount,
    required this.hasRules,
    required this.onMembersTap,
    required this.onRulesTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onMembersTap,
          child: _buildTag(
            Icons.people_outline,
            '$memberCount${AppMessages.circle.memberCountSuffix}',
            showArrow: true,
          ),
        ),
        if (hasRules) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRulesTap,
            child: _buildTag(
              Icons.description_outlined,
              AppMessages.circle.ruleLabel,
              showArrow: true,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTag(IconData icon, String text, {bool showArrow = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[700]),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          if (showArrow) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 14, color: Colors.grey[500]),
          ],
        ],
      ),
    );
  }
}
