import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/services/recent_reactions_service.dart';
import 'reaction_button.dart';

/// カテゴリごとにタブで整理されたリアクション選択シート
class ReactionSelectionSheet extends StatefulWidget {
  final String postId;
  final Map<String, int> reactions;
  final void Function(String reactionType)? onReactionAdded; // リアクション追加時のコールバック

  const ReactionSelectionSheet({
    super.key,
    required this.postId,
    required this.reactions,
    this.onReactionAdded,
  });

  @override
  State<ReactionSelectionSheet> createState() => _ReactionSelectionSheetState();
}

class _ReactionSelectionSheetState extends State<ReactionSelectionSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<String> _recentReactions = [];
  bool _isLoading = true;
  int _reactionCount = 0; // リアクション回数カウント
  static const int _maxReactions = 5; // 最大リアクション回数

  @override
  void initState() {
    super.initState();
    _loadRecentReactions();
  }

  Future<void> _loadRecentReactions() async {
    final recent = await RecentReactionsService.getRecentReactions();
    if (mounted) {
      setState(() {
        _recentReactions = recent;
        _isLoading = false;
        // タブ数: よく使う（履歴がある場合のみ） + カテゴリ数
        final tabCount =
            (_recentReactions.isNotEmpty ? 1 : 0) +
            ReactionCategory.values.length;
        _tabController = TabController(length: tabCount, vsync: this);
      });
    }
  }

  /// リアクション追加時のコールバック（シート内で呼び出される）
  void _handleReactionAdded(String reactionType) {
    // 親コールバックを呼び出してローカル状態を更新
    widget.onReactionAdded?.call(reactionType);

    // リアクション回数をカウント
    _reactionCount++;

    // 5回でシートを閉じてトースト表示
    if (_reactionCount >= _maxReactions) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('リアクションは5回までです'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    if (!_isLoading) {
      _tabController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SafeArea(
        child: SizedBox(
          height: 320,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final hasRecent = _recentReactions.isNotEmpty;

    return SafeArea(
      child: Container(
        height: 320,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ドラッグハンドル
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // ヘッダー
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'リアクションを選択',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // カテゴリタブ
            TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.primary,
              indicatorSize: TabBarIndicatorSize.label,
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              tabs: [
                // よく使うタブ（履歴がある場合のみ）
                if (hasRecent)
                  const Tab(
                    height: 36,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time, size: 16),
                        SizedBox(width: 4),
                        Text('よく使う', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                // カテゴリタブ
                ...ReactionCategory.values.map((category) {
                  final firstEmoji =
                      ReactionType.values
                          .where((t) => t.category == category)
                          .firstOrNull
                          ?.emoji ??
                      '📁';
                  return Tab(
                    height: 36,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(firstEmoji, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 4),
                        Text(
                          category.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
            const Divider(height: 1),
            // リアクショングリッド
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // よく使うタブ（履歴がある場合のみ）
                  if (hasRecent)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        alignment: WrapAlignment.start,
                        spacing: 16,
                        runSpacing: 16,
                        children: _recentReactions.map((typeValue) {
                          final type = ReactionType.values.firstWhere(
                            (t) => t.value == typeValue,
                            orElse: () => ReactionType.love,
                          );
                          return ReactionButton(
                            type: type,
                            count: widget.reactions[type.value] ?? 0,
                            postId: widget.postId,
                            onReactionAdded: _handleReactionAdded,
                          );
                        }).toList(),
                      ),
                    ),
                  // カテゴリごとのタブ
                  ...ReactionCategory.values.map((category) {
                    final types = ReactionType.values
                        .where((t) => t.category == category)
                        .toList();

                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        alignment: WrapAlignment.start,
                        spacing: 16,
                        runSpacing: 16,
                        children: types.map((type) {
                          return ReactionButton(
                            type: type,
                            count: widget.reactions[type.value] ?? 0,
                            postId: widget.postId,
                            onReactionAdded: _handleReactionAdded,
                          );
                        }).toList(),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
