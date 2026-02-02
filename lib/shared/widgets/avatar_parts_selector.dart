import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/avatar_assets.dart';
import '../models/avatar_parts_model.dart';
import 'avatar_parts_widget.dart';

class AvatarPartsSelector extends StatelessWidget {
  final AvatarParts parts;
  final ValueChanged<AvatarParts> onChanged;
  final double previewSize;

  const AvatarPartsSelector({
    super.key,
    required this.parts,
    required this.onChanged,
    this.previewSize = 88,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: AvatarPartsWidget(
            parts: parts,
            size: previewSize,
          ),
        ),
        const SizedBox(height: 16),
        _buildPartRow(
          label: 'Hair',
          ids: AvatarAssets.hairIds,
          selectedId: parts.hairId,
          buildPreviewParts: (id) => parts.copyWith(hairId: id),
          onSelected: (id) => onChanged(parts.copyWith(hairId: id)),
        ),
        const SizedBox(height: 12),
        _buildPartRow(
          label: 'Brows',
          ids: AvatarAssets.eyebrowsIds,
          selectedId: parts.eyebrowsId,
          buildPreviewParts: (id) => parts.copyWith(eyebrowsId: id),
          onSelected: (id) => onChanged(parts.copyWith(eyebrowsId: id)),
        ),
        const SizedBox(height: 12),
        _buildPartRow(
          label: 'Eyes',
          ids: AvatarAssets.eyesIds,
          selectedId: parts.eyesId,
          buildPreviewParts: (id) => parts.copyWith(eyesId: id),
          onSelected: (id) => onChanged(parts.copyWith(eyesId: id)),
        ),
        const SizedBox(height: 12),
        _buildPartRow(
          label: 'Mouth',
          ids: AvatarAssets.mouthIds,
          selectedId: parts.mouthId,
          buildPreviewParts: (id) => parts.copyWith(mouthId: id),
          onSelected: (id) => onChanged(parts.copyWith(mouthId: id)),
        ),
      ],
    );
  }

  Widget _buildPartRow({
    required String label,
    required List<String> ids,
    required String selectedId,
    required AvatarParts Function(String id) buildPreviewParts,
    required ValueChanged<String> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: ids.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final id = ids[index];
              final isSelected = id == selectedId;
              return GestureDetector(
                onTap: () => onSelected(id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryLight
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                    border: isSelected
                        ? Border.all(color: AppColors.primary, width: 2)
                        : null,
                  ),
                  child: Center(
                    child: AvatarPartsWidget(
                      parts: buildPreviewParts(id),
                      size: 54,
                      backgroundColor: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
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
