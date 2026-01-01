import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/avatar_selector.dart';

/// 管理者用通報一覧画面
class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通報管理'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '未対応'),
            Tab(text: '対応済み'),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: TabBarView(
          controller: _tabController,
          children: [
            _ReportsList(status: 'pending'),
            _ReportsList(status: 'reviewed'),
          ],
        ),
      ),
    );
  }
}

class _ReportsList extends StatelessWidget {
  final String status;

  const _ReportsList({required this.status});

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    // statusに応じてクエリを変更
    Query query;
    if (status == 'pending') {
      query = firestore
          .collection('reports')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true);
    } else {
      // 対応済み = resolved または dismissed
      query = firestore
          .collection('reports')
          .where('status', whereIn: ['resolved', 'dismissed'])
          .orderBy('createdAt', descending: true);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.limit(50).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('エラー: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final reports = snapshot.data?.docs ?? [];

        if (reports.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  status == 'pending' ? Icons.check_circle : Icons.history,
                  size: 64,
                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  status == 'pending' ? '未対応の通報はありません' : '対応済みの通報はありません',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final report = reports[index];
            final data = report.data() as Map<String, dynamic>;
            return _ReportCard(reportId: report.id, data: data);
          },
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String reportId;
  final Map<String, dynamic> data;

  const _ReportCard({required this.reportId, required this.data});

  String _getReasonLabel(String reason) {
    switch (reason) {
      case 'spam':
        return 'スパム・宣伝';
      case 'harassment':
        return '誹謗中傷';
      case 'inappropriate':
        return '不適切';
      case 'misinformation':
        return '誤情報';
      case 'other':
        return 'その他';
      default:
        return reason;
    }
  }

  @override
  Widget build(BuildContext context) {
    final createdAt = data['createdAt'] as Timestamp?;
    final timeAgo = createdAt != null
        ? timeago.format(createdAt.toDate(), locale: 'ja')
        : '';
    final firestore = FirebaseFirestore.instance;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => context.push('/admin/reports/$reportId'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ヘッダー: タイプ + 理由 + 時間
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: data['contentType'] == 'post'
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      data['contentType'] == 'post' ? '投稿' : 'コメント',
                      style: TextStyle(
                        color: data['contentType'] == 'post'
                            ? AppColors.primary
                            : AppColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _getReasonLabel(data['reason'] ?? ''),
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeAgo,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 被通報者情報
              FutureBuilder<DocumentSnapshot>(
                future: firestore
                    .collection('users')
                    .doc(data['targetUserId'])
                    .get(),
                builder: (context, snapshot) {
                  final user = snapshot.data?.data() as Map<String, dynamic>?;
                  final reportCount = user?['reportCount'] ?? 0;

                  return Row(
                    children: [
                      AvatarWidget(
                        avatarIndex: user?['avatarIndex'] ?? 0,
                        size: 36,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?['displayName'] ?? '読み込み中...',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '累計通報: $reportCount件',
                              style: TextStyle(
                                fontSize: 12,
                                color: reportCount > 0
                                    ? AppColors.error
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: AppColors.textSecondary),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
