import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/avatar_assets.dart';
import '../models/avatar_parts_model.dart';

class AvatarPartsWidget extends StatelessWidget {
  final AvatarParts parts;
  final double size;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  static const double _eyesScale = 0.5;
  static const double _mouthScale = 0.6;
  //いったん髪と輪郭を同一で作成するためBaseは廃止
  //static const double _baseScale = 1.08;
  static const double _hairScale = 1.45;
  static const double _eyebrowsScale = 0.52;
  static const Offset _eyebrowsOffset = Offset(0, -9);
  static const Offset _eyesOffset = Offset(0, -2);
  static const Offset _mouthOffset = Offset(0, 17);

  const AvatarPartsWidget({
    super.key,
    required this.parts,
    this.size = 40,
    this.backgroundColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(size * 0.22);
    final unit = size / 100.0;
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: size,
        height: size,
        color: backgroundColor ?? AppColors.primaryLight.withValues(alpha: 0.4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildLayer(
              AvatarAssets.hairPath(parts.hairId),
              size: size,
              scale: _hairScale,
            ),
            _buildLayer(
              AvatarAssets.eyebrowsPath(parts.eyebrowsId),
              size: size,
              scale: _eyebrowsScale,
              offset: Offset(
                _eyebrowsOffset.dx * unit,
                _eyebrowsOffset.dy * unit,
              ),
            ),
            _buildLayer(
              AvatarAssets.eyesPath(parts.eyesId),
              size: size,
              scale: _eyesScale,
              offset: Offset(_eyesOffset.dx * unit, _eyesOffset.dy * unit),
            ),
            _buildLayer(
              AvatarAssets.mouthPath(parts.mouthId),
              size: size,
              scale: _mouthScale,
              offset: Offset(_mouthOffset.dx * unit, _mouthOffset.dy * unit),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayer(
    String path, {
    required double size,
    double scale = 1.0,
    Offset offset = Offset.zero,
  }) {
    return Center(
      child: Transform.translate(
        offset: offset,
        child: Transform.scale(
          scale: scale,
          child: Image.asset(
            path,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}
