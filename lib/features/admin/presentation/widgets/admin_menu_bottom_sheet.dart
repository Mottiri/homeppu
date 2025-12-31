import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/providers/ai_provider.dart';

/// 管理者用ボトムシート
class AdminMenuBottomSheet extends ConsumerStatefulWidget {
  const AdminMenuBottomSheet({super.key});

  /// ボトムシートを表示
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AdminMenuBottomSheet(),
    );
  }

  @override
  ConsumerState<AdminMenuBottomSheet> createState() =>
      _AdminMenuBottomSheetState();
}

class _AdminMenuBottomSheetState extends ConsumerState<AdminMenuBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ハンドル
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ヘッダー
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.admin_panel_settings, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  '管理者メニュー',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // タブバー
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: [
              _buildTabWithBadge('AI操作', null), // AI操作はバッジ不要
              _buildTabWithBadgeStream('サポート', _getPendingInquiriesCount()),
              _buildTabWithBadgeStream('通報', _getPendingReportsCount()),
            ],
          ),

          // タブコンテンツ
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildAITab(), _buildSupportTab(), _buildReportsTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabWithBadge(String label, int? count) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count != null && count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabWithBadgeStream(String label, Stream<int> countStream) {
    return StreamBuilder<int>(
      stream: countStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return _buildTabWithBadge(label, count);
      },
    );
  }

  Stream<int> _getPendingInquiriesCount() {
    return _firestore
        .collection('inquiries')
        .where('status', whereIn: ['open', 'in_progress'])
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  Stream<int> _getPendingReportsCount() {
    return _firestore
        .collection('reports')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  // AI操作タブ
  Widget _buildAITab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildMenuButton(
            icon: Icons.group_add,
            label: 'AIアカウントを初期化',
            subtitle: 'AIユーザーアカウントを作成',
            color: AppColors.primary,
            onTap: () async {
              Navigator.pop(context);
              try {
                final aiService = ref.read(aiServiceProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('AIアカウントを初期化中...'),
                    backgroundColor: AppColors.primary,
                  ),
                );
                await aiService.initializeAIAccounts();
                if (mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('AIアカウントを作成しました！🤖'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('エラー: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 12),
          _buildMenuButton(
            icon: Icons.auto_awesome,
            label: 'AI投稿を生成',
            subtitle: 'AIによる投稿を手動で生成',
            color: AppColors.secondary,
            onTap: () async {
              Navigator.pop(context);
              try {
                final aiService = ref.read(aiServiceProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('AI投稿を生成中...（少し時間がかかります）'),
                    backgroundColor: AppColors.primary,
                    duration: Duration(seconds: 10),
                  ),
                );
                final result = await aiService.generateAIPosts();
                if (mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result['message'] as String? ?? '完了'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('エラー: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  // サポートタブ
  Widget _buildSupportTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          StreamBuilder<int>(
            stream: _getPendingInquiriesCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return _buildMenuButton(
                icon: Icons.mail_outline,
                label: '問い合わせ管理',
                subtitle: count > 0 ? '$count件の未対応' : '未対応なし',
                color: AppColors.primary,
                badge: count,
                onTap: () {
                  Navigator.pop(context);
                  context.push('/admin/inquiries');
                },
              );
            },
          ),
          const SizedBox(height: 12),
          _buildMenuButton(
            icon: Icons.rate_review,
            label: '要審査投稿レビュー',
            subtitle: 'ネガティブ判定された投稿を確認',
            color: AppColors.warning,
            onTap: () {
              Navigator.pop(context);
              context.push('/admin/review');
            },
          ),
        ],
      ),
    );
  }

  // 通報タブ
  Widget _buildReportsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          StreamBuilder<int>(
            stream: _getPendingReportsCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return _buildMenuButton(
                icon: Icons.flag_outlined,
                label: '通報管理',
                subtitle: count > 0 ? '$count件の未対応' : '未対応なし',
                color: AppColors.warning,
                badge: count,
                onTap: () {
                  Navigator.pop(context);
                  context.push('/admin/reports');
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    int? badge,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: color,
                          ),
                        ),
                        if (badge != null && badge > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              badge > 99 ? '99+' : '$badge',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// 管理者メニューアイコン（バッジ付き）
class AdminMenuIcon extends StatelessWidget {
  const AdminMenuIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    return StreamBuilder<int>(
      stream: _getTotalPendingCount(firestore),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return IconButton(
          onPressed: () => AdminMenuBottomSheet.show(context),
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(fontSize: 10),
            ),
            child: const Icon(Icons.admin_panel_settings),
          ),
          tooltip: '管理者メニュー',
        );
      },
    );
  }

  Stream<int> _getTotalPendingCount(FirebaseFirestore firestore) {
    // 問い合わせと通報の両方の未対応数を合計
    return firestore
        .collection('inquiries')
        .where('status', whereIn: ['open', 'in_progress'])
        .snapshots()
        .asyncMap((inquiries) async {
          final reports = await firestore
              .collection('reports')
              .where('status', isEqualTo: 'pending')
              .get();
          return inquiries.size + reports.size;
        });
  }
}
