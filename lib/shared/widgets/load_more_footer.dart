import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// もっと読み込むフッターWidget
///
/// スクロール不可の場合に表示し、押下で追加読み込みを実行する。
///
/// 使用方法:
/// ```dart
/// // SliverListの末尾に配置
/// SliverToBoxAdapter(
///   child: LoadMoreFooter(
///     hasMore: _hasMore,
///     isLoadingMore: _isLoadingMore,
///     isInitialLoadComplete: !_isLoading,
///     canLoadMore: _lastDocument != null,
///     isScrollable: _scrollController.hasClients && _scrollController.position.maxScrollExtent > 0,
///     onLoadMore: _loadMore,
///   ),
/// )
/// ```
class LoadMoreFooter extends StatelessWidget {
  /// まだデータがあるかどうか
  final bool hasMore;

  /// 追加読み込み中かどうか
  final bool isLoadingMore;

  /// 初回ロード完了かどうか
  final bool isInitialLoadComplete;

  /// 追加読み込み可能かどうか（初回ロード成功時のみtrue）
  final bool canLoadMore;

  /// スクロール可能かどうか（trueならスクロールで発火するため非表示）
  final bool isScrollable;

  /// 追加読み込みコールバック
  final VoidCallback onLoadMore;

  const LoadMoreFooter({
    super.key,
    required this.hasMore,
    required this.isLoadingMore,
    required this.isInitialLoadComplete,
    required this.canLoadMore,
    required this.isScrollable,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    // 表示条件: hasMore && !isLoadingMore && 初回ロード完了 && canLoadMore && スクロール不可
    final shouldShow =
        hasMore &&
        !isLoadingMore &&
        isInitialLoadComplete &&
        canLoadMore &&
        !isScrollable;

    if (!shouldShow) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: TextButton.icon(
          onPressed: onLoadMore,
          icon: const Icon(Icons.expand_more),
          label: const Text('もっと読み込む'),
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
        ),
      ),
    );
  }
}
