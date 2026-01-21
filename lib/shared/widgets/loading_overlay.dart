import 'package:flutter/material.dart';

/// ローディングオーバーレイWidget
///
/// 使用方法:
/// ```dart
/// LoadingOverlay(
///   isLoading: _isLoading,
///   message: '保存中...',
///   child: YourContent(),
/// )
/// ```
class LoadingOverlay extends StatelessWidget {
  /// ローディング中かどうか
  final bool isLoading;

  /// 子Widget
  final Widget child;

  /// 表示メッセージ（オプション）
  final String? message;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 入力ブロック（AbsorbPointer）
        AbsorbPointer(absorbing: isLoading, child: child),
        // オーバーレイ
        if (isLoading)
          Container(
            color: Colors.black26,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  if (message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      message!,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
