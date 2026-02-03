import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/avatar_assets.dart';
import '../../../../shared/models/avatar_parts_model.dart';
import '../../../../shared/widgets/avatar_parts_widget.dart';

enum _AvatarPartCategory { hair, eyebrows, eyes, mouth }

class AvatarEditScreen extends StatefulWidget {
  final AvatarParts initialParts;

  const AvatarEditScreen({
    super.key,
    required this.initialParts,
  });

  @override
  State<AvatarEditScreen> createState() => _AvatarEditScreenState();
}

class _AvatarEditScreenState extends State<AvatarEditScreen> {
  late AvatarParts _parts;
  _AvatarPartCategory _category = _AvatarPartCategory.hair;

  @override
  void initState() {
    super.initState();
    _parts = widget.initialParts;
  }

  List<String> get _currentIds {
    switch (_category) {
      case _AvatarPartCategory.hair:
        return AvatarAssets.hairIds;
      case _AvatarPartCategory.eyebrows:
        return AvatarAssets.eyebrowsIds;
      case _AvatarPartCategory.eyes:
        return AvatarAssets.eyesIds;
      case _AvatarPartCategory.mouth:
        return AvatarAssets.mouthIds;
    }
  }

  String get _selectedId {
    switch (_category) {
      case _AvatarPartCategory.hair:
        return _parts.hairId;
      case _AvatarPartCategory.eyebrows:
        return _parts.eyebrowsId;
      case _AvatarPartCategory.eyes:
        return _parts.eyesId;
      case _AvatarPartCategory.mouth:
        return _parts.mouthId;
    }
  }

  AvatarParts _withPart(String id) {
    switch (_category) {
      case _AvatarPartCategory.hair:
        return _parts.copyWith(hairId: id);
      case _AvatarPartCategory.eyebrows:
        return _parts.copyWith(eyebrowsId: id);
      case _AvatarPartCategory.eyes:
        return _parts.copyWith(eyesId: id);
      case _AvatarPartCategory.mouth:
        return _parts.copyWith(mouthId: id);
    }
  }

  String _categoryLabel(_AvatarPartCategory category) {
    switch (category) {
      case _AvatarPartCategory.hair:
        return '髪';
      case _AvatarPartCategory.eyebrows:
        return '眉';
      case _AvatarPartCategory.eyes:
        return '目';
      case _AvatarPartCategory.mouth:
        return '口';
    }
  }

  String _categoryAssetPath(_AvatarPartCategory category) {
    switch (category) {
      case _AvatarPartCategory.hair:
        return AvatarAssets.hairPath(_parts.hairId);
      case _AvatarPartCategory.eyebrows:
        return AvatarAssets.eyebrowsPath(_parts.eyebrowsId);
      case _AvatarPartCategory.eyes:
        return AvatarAssets.eyesPath(_parts.eyesId);
      case _AvatarPartCategory.mouth:
        return AvatarAssets.mouthPath(_parts.mouthId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('アバター編集'),
        actions: [
          TextButton(
            onPressed: () => context.pop(_parts),
            child: const Text('完了'),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildPreview(),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildPartsGrid()),
                      const SizedBox(width: 12),
                      _buildCategoryColumn(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
      child: Center(
        child: AvatarPartsWidget(
          parts: _parts,
          size: 180,
          backgroundColor: AppColors.primaryLight.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(28),
        ),
      ),
    );
  }

  Widget _buildPartsGrid() {
    final ids = _currentIds;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemCount: ids.length,
        itemBuilder: (context, index) {
          final id = ids[index];
          final isSelected = id == _selectedId;
          return GestureDetector(
            onTap: () => setState(() => _parts = _withPart(id)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryLight
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: isSelected
                    ? Border.all(color: AppColors.primary, width: 2)
                    : null,
              ),
              child: Center(
                child: AvatarPartsWidget(
                  parts: _withPart(id),
                  size: 72,
                  backgroundColor: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryColumn() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _AvatarPartCategory.values.map((category) {
          final isSelected = category == _category;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: GestureDetector(
              onTap: () => setState(() => _category = category),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 64,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryLight
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                  border: isSelected
                      ? Border.all(color: AppColors.primary, width: 2)
                      : null,
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Image.asset(
                      _categoryAssetPath(category),
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const SizedBox(width: 36, height: 36);
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _categoryLabel(category),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
