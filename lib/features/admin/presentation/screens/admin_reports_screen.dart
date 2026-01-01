import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/avatar_selector.dart';

/// 管理者用通報一覧画面（コンテンツ単位でグループ化）
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
            _GroupedReportsList(status: 'pending'),
            _GroupedReportsList(status: 'reviewed'),
          ],
        ),
      ),
    );
  }
}

/// コンテンツ単位でグループ化された通報リスト
class _GroupedReportsList extends StatelessWidget {
  final String status;

  const _GroupedReportsList({required this.status});

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
      stream: query.limit(100).snapshots(),
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

        // contentIdでグループ化
        final Map<String, List<QueryDocumentSnapshot>> groupedReports = {};
        for (final report in reports) {
          final data = report.data() as Map<String, dynamic>;
          final contentId = data['contentId'] as String? ?? '';
          if (contentId.isNotEmpty) {
            groupedReports.putIfAbsent(contentId, () => []).add(report);
          }
        }

        // グループ化されたリストを最新の通報順でソート
        final sortedContentIds = groupedReports.keys.toList()
          ..sort((a, b) {
            final aTime =
                (groupedReports[a]!.first.data()
                        as Map<String, dynamic>)['createdAt']
                    as Timestamp?;
            final bTime =
                (groupedReports[b]!.first.data()
                        as Map<String, dynamic>)['createdAt']
                    as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime);
          });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sortedContentIds.length,
          itemBuilder: (context, index) {
            final contentId = sortedContentIds[index];
            final contentReports = groupedReports[contentId]!;
            final firstData =
                contentReports.first.data() as Map<String, dynamic>;
            return _GroupedReportCard(
              contentId: contentId,
              contentType: firstData['contentType'] as String? ?? 'post',
              targetUserId: firstData['targetUserId'] as String? ?? '',
              reports: contentReports,
            );
          },
        );
      },
    );
  }
}

/// コンテンツ単位のカード
class _GroupedReportCard extends StatelessWidget {
  final String contentId;
  final String contentType;
  final String targetUserId;
  final List<QueryDocumentSnapshot> reports;

  const _GroupedReportCard({
    required this.contentId,
    required this.contentType,
    required this.targetUserId,
    required this.reports,
  });

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    final latestReport = reports.first.data() as Map<String, dynamic>;
    final createdAt = latestReport['createdAt'] as Timestamp?;
    final timeAgo = createdAt != null
        ? timeago.format(createdAt.toDate(), locale: 'ja')
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => context.push('/admin/reports/content/$contentId'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ヘッダー: タイプ + 通報件数 + 時間
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: contentType == 'post'
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      contentType == 'post' ? '投稿' : 'コメント',
                      style: TextStyle(
                        color: contentType == 'post'
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
                      '${reports.length}件の通報',
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
                future: firestore.collection('users').doc(targetUserId).get(),
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

              // 投稿プレビュー
              const SizedBox(height: 12),
              FutureBuilder<DocumentSnapshot>(
                future: firestore
                    .collection(contentType == 'post' ? 'posts' : 'comments')
                    .doc(contentId)
                    .get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '(削除済みまたは取得できません)',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }

                  final contentData =
                      snapshot.data!.data() as Map<String, dynamic>;
                  final content = contentData['content'] as String? ?? '';
                  final isHidden = contentData['isVisible'] == false;

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isHidden
                          ? AppColors.warning.withValues(alpha: 0.1)
                          : AppColors.textSecondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isHidden)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.visibility_off,
                                  size: 16,
                                  color: AppColors.warning,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '現在非表示中',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Text(
                          content.length > 100
                              ? '${content.substring(0, 100)}...'
                              : content,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
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
