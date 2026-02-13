import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../models/avatar_parts_model.dart';
import 'avatar_parts_widget.dart';

/// プリセットアバターのリスト
const List<String> presetAvatars = [
  '😊',
  '🌸',
  '🐱',
  '🐶',
  '🦊',
  '🐰',
  '🐻',
  '🐼',
  '🦁',
  '🐯',
  '🐨',
  '🐷',
  '🐸',
  '🐵',
  '🦄',
  '🐙',
  '🌻',
  '🌺',
  '🌷',
  '🌹',
  '🍀',
  '🌈',
  '⭐',
  '🌙',
];

/// アバター選択ウィジェット
class AvatarSelector extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double size;

  const AvatarSelector({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    final previewRadius = BorderRadius.circular(size * 0.28);
    return Column(
      children: [
        // 選択中のアバター（大きく表示）
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: previewRadius,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Text(
              presetAvatars[selectedIndex],
              style: TextStyle(fontSize: size * 0.5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('アバターを選んでね', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),

        // アバターグリッド
        SizedBox(
          height: 160,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: presetAvatars.length,
            itemBuilder: (context, index) {
              final isSelected = index == selectedIndex;
              return GestureDetector(
                onTap: () => onSelected(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryLight
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                    border: isSelected
                        ? Border.all(color: AppColors.primary, width: 3)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      presetAvatars[index],
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// アバター表示ウィジェット（単体）
class AvatarWidget extends StatelessWidget {
  final int avatarIndex;
  final double size;
  final Color? backgroundColor;
  final AvatarParts? avatarParts;
  final BorderRadius? borderRadius;
  final String? imageUrl;

  const AvatarWidget({
    super.key,
    required this.avatarIndex,
    this.size = 40,
    this.backgroundColor,
    this.avatarParts,
    this.borderRadius,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius =
        borderRadius ?? BorderRadius.circular(size * 0.28);

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _buildFallbackAvatar(effectiveBorderRadius),
        ),
      );
    }

    if (avatarParts != null) {
      return AvatarPartsWidget(
        parts: avatarParts!,
        size: size,
        backgroundColor: backgroundColor,
        borderRadius: effectiveBorderRadius,
      );
    }
    return _buildFallbackAvatar(effectiveBorderRadius);
  }

  Widget _buildFallbackAvatar(BorderRadius effectiveBorderRadius) {
    final safeIndex = avatarIndex.clamp(0, presetAvatars.length - 1);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.primaryLight.withValues(alpha: 0.5),
        borderRadius: effectiveBorderRadius,
      ),
      child: Center(
        child: Text(
          presetAvatars[safeIndex],
          style: TextStyle(fontSize: size * 0.5),
        ),
      ),
    );
  }
}
