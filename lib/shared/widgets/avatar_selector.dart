import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// プリセットアバターのリスト
const List<String> presetAvatars = [
  '😊', '🌸', '🐱', '🐶', '🦊', '🐰', '🐻', '🐼',
  '🦁', '🐯', '🐨', '🐷', '🐸', '🐵', '🦄', '🐙',
  '🌻', '🌺', '🌷', '🌹', '🍀', '🌈', '⭐', '🌙',
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
    return Column(
      children: [
        // 選択中のアバター（大きく表示）
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
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
        Text(
          'アバターを選んでね',
          style: Theme.of(context).textTheme.bodySmall,
        ),
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
                    shape: BoxShape.circle,
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

  const AvatarWidget({
    super.key,
    required this.avatarIndex,
    this.size = 40,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final safeIndex = avatarIndex.clamp(0, presetAvatars.length - 1);
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.primaryLight.withOpacity(0.5),
        shape: BoxShape.circle,
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


