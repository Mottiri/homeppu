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
  static const Map<String, double> _eyesScaleOverrides = {'eyes_03': 0.47};
  static const double _mouthScale = 0.6;
  static const Map<String, double> _mouthScaleOverrides = {
    'mouth_03': 0.23,
    'mouth_06': 0.3,
    'mouth_07': 0.3,
  };
  static const Map<String, Offset> _mouthOffsetOverrides = {
    'mouth_03': Offset(0, 1),
    'mouth_06': Offset(0, 3),
  };
  static const double _hairScale = 1.45;
  static const double _eyebrowsScale = 0.52;
  static const Map<String, double> _eyebrowsScaleOverrides = {
    'eyebrows_04': 0.46,
    'eyebrows_07': 0.46,
    'eyebrows_08': 0.46,
    'eyebrows_11': 0.46,
    'eyebrows_12': 0.46,
    'eyebrows_13': 0.46,
    'eyebrows_16': 0.46,
    'eyebrows_17': 0.46,
    'eyebrows_19': 0.46,
    'eyebrows_20': 0.46,
  };
  static const Offset _eyebrowsOffset = Offset(0, -9);
  static const Map<String, Offset> _eyebrowsOffsetOverrides = {
    'eyebrows_04': Offset(0, -1),
    'eyebrows_02': Offset(0, -2),
    'eyebrows_03': Offset(0, -2),
    'eyebrows_09': Offset(0, -2),
    'eyebrows_17': Offset(0, -2),
    'eyebrows_20': Offset(0, -3),
  };
  static const Offset _eyesOffset = Offset(0, -2);
  static const Map<String, Offset> _eyesOffsetOverrides = {
    'eyes_03': Offset(0, 0.5),
  };
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
    final mouthOffset =
        _mouthOffset + (_mouthOffsetOverrides[parts.mouthId] ?? Offset.zero);
    final eyebrowsOffset =
        _eyebrowsOffset +
        (_eyebrowsOffsetOverrides[parts.eyebrowsId] ?? Offset.zero);
    final eyesOffset =
        _eyesOffset + (_eyesOffsetOverrides[parts.eyesId] ?? Offset.zero);
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
              scale:
                  _eyebrowsScaleOverrides[parts.eyebrowsId] ?? _eyebrowsScale,
              offset: Offset(
                eyebrowsOffset.dx * unit,
                eyebrowsOffset.dy * unit,
              ),
            ),
            _buildLayer(
              AvatarAssets.eyesPath(parts.eyesId),
              size: size,
              scale: _eyesScaleOverrides[parts.eyesId] ?? _eyesScale,
              offset: Offset(eyesOffset.dx * unit, eyesOffset.dy * unit),
            ),
            _buildLayer(
              AvatarAssets.mouthPath(parts.mouthId),
              size: size,
              scale: _mouthScaleOverrides[parts.mouthId] ?? _mouthScale,
              offset: Offset(mouthOffset.dx * unit, mouthOffset.dy * unit),
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
