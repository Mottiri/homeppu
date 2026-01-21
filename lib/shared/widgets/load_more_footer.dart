import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// もっと読み込むフッターWidget
///
/// リストが短い（スクロール不可の可能性がある）場合に表示し、押下で追加読み込みを実行する。
///
/// 使用方法:
/// ```dart
/// // SliverListの末尾に配置
/// SliverToBoxAdapter(
///   child: LoadMoreFooter(
///     hasMore: _hasMore,
///     isLoadingMore: _isLoadingMore,
///     isInitialLoadComplete: !_isLoading,
///     currentItemCount: _posts.length,
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

  /// 現在のアイテム数（スクロール不可判定の代替）
  final int currentItemCount;

  /// 追加読み込みコールバック
  final VoidCallback onLoadMore;

  /// スクロール不可と判定するアイテム数の閾値（デフォルト: 5）
  final int shortListThreshold;

  const LoadMoreFooter({
    super.key,
    required this.hasMore,
    required this.isLoadingMore,
    required this.isInitialLoadComplete,
    required this.currentItemCount,
    required this.onLoadMore,
    this.shortListThreshold = 5,
  });

  /// 表示条件: hasMore && !isLoadingMore && 初回ロード完了 && アイテム数が少ない
  bool get _shouldShow =>
      hasMore &&
      !isLoadingMore &&
      isInitialLoadComplete &&
      currentItemCount < shortListThreshold;

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) {
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
