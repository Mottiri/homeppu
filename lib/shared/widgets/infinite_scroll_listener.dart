import 'package:flutter/material.dart';

/// 無限スクロール用のリスナーWidget
///
/// 使用方法:
/// ```dart
/// InfiniteScrollListener(
///   isLoadingMore: _isLoadingMore,
///   hasMore: _hasMore,
///   onLoadMore: _loadMore,
///   child: CustomScrollView(...),
/// )
/// ```
class InfiniteScrollListener extends StatelessWidget {
  /// 子Widget（CustomScrollView/ListView等のスクロール所有者）
  final Widget child;

  /// 追加読み込み中かどうか
  final bool isLoadingMore;

  /// まだデータがあるかどうか
  final bool hasMore;

  /// 追加読み込みを実行するコールバック
  final VoidCallback onLoadMore;

  /// 発火閾値（デフォルト 300px）
  final double threshold;

  const InfiniteScrollListener({
    super.key,
    required this.child,
    required this.isLoadingMore,
    required this.hasMore,
    required this.onLoadMore,
    this.threshold = 300,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          if (notification.metrics.extentAfter < threshold) {
            // ガード: ロード中でなく、かつ追加データがある場合のみ発火
            if (!isLoadingMore && hasMore) {
              onLoadMore();
            }
          }
        }
        return false;
      },
      child: child,
    );
  }
}
