import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// 統一されたタブバースタイル
/// ほめっぷのデザインシステムに準拠
class StyledTabBar extends StatelessWidget {
  final TabController controller;
  final List<String> tabs;
  final List<IconData>? icons;
  final EdgeInsetsGeometry? margin;
  final bool isScrollable;
  final TabBarStyle style;

  const StyledTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.icons,
    this.margin,
    this.isScrollable = false,
    this.style = TabBarStyle.pill,
  });

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case TabBarStyle.pill:
        return _buildPillStyle(context);
      case TabBarStyle.underline:
        return _buildUnderlineStyle(context);
      case TabBarStyle.segment:
        return _buildSegmentStyle(context);
    }
  }

  /// ピル型のタブバー（デフォルト）
  Widget _buildPillStyle(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: isScrollable,
        indicator: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        dividerColor: Colors.transparent,
        indicatorPadding: const EdgeInsets.all(4),
        tabs: _buildTabs(),
      ),
    );
  }

  /// アンダーライン型のタブバー
  Widget _buildUnderlineStyle(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.backgroundSecondary,
            width: 2,
          ),
        ),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: isScrollable,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textHint,
        indicatorColor: AppColors.primary,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
        dividerColor: Colors.transparent,
        tabs: _buildTabs(),
      ),
    );
  }

  /// セグメント型のタブバー（アイコン用）
  Widget _buildSegmentStyle(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: isScrollable,
        indicator: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        dividerColor: Colors.transparent,
        tabs: _buildIconTabs(),
      ),
    );
  }

  List<Widget> _buildTabs() {
    return tabs.map((tab) {
      final index = tabs.indexOf(tab);
      if (icons != null && index < icons!.length) {
        return Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icons![index], size: 18),
              const SizedBox(width: 6),
              Text(tab),
            ],
          ),
        );
      }
      return Tab(text: tab);
    }).toList();
  }

  List<Widget> _buildIconTabs() {
    if (icons != null) {
      return icons!.map((icon) => Tab(icon: Icon(icon, size: 20))).toList();
    }
    return tabs.map((tab) => Tab(text: tab)).toList();
  }
}

enum TabBarStyle {
  /// ピル型（背景がグラデーション）
  pill,

  /// アンダーライン型
  underline,

  /// セグメント型（主にアイコン用）
  segment,
}

/// 統一されたSliverPersistentHeaderDelegate
class StyledTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color? backgroundColor;
  final double? topPadding;

  StyledTabBarDelegate({
    required this.tabBar,
    this.backgroundColor,
    this.topPadding,
  });

  @override
  double get minExtent => tabBar.preferredSize.height + (topPadding ?? 0);

  @override
  double get maxExtent => tabBar.preferredSize.height + (topPadding ?? 0);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: backgroundColor ?? AppColors.background,
      padding: EdgeInsets.only(top: topPadding ?? 0),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(StyledTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}
