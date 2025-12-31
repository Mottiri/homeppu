import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_colors.dart';

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

    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('reports')
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
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

class _ReportCard extends StatefulWidget {
  final String reportId;
  final Map<String, dynamic> data;

  const _ReportCard({required this.reportId, required this.data});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  final _firestore = FirebaseFirestore.instance;
  bool _isExpanded = false;
  Map<String, dynamic>? _reportedUser;
  Map<String, dynamic>? _reporterUser;
  int _reporterReportCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    // 被通報者情報を取得
    final reportedUserDoc = await _firestore
        .collection('users')
        .doc(widget.data['targetUserId'])
        .get();
    // 通報者情報を取得
    final reporterUserDoc = await _firestore
        .collection('users')
        .doc(widget.data['reporterId'])
        .get();
    // 通報者の通報回数
    final reporterReports = await _firestore
        .collection('reports')
        .where('reporterId', isEqualTo: widget.data['reporterId'])
        .get();

    if (mounted) {
      setState(() {
        _reportedUser = reportedUserDoc.data();
        _reporterUser = reporterUserDoc.data();
        _reporterReportCount = reporterReports.size;
      });
    }
  }

  String _getReasonLabel(String reason) {
    switch (reason) {
      case 'spam':
        return 'スパム・宣伝';
      case 'harassment':
        return '誹謗中傷・嫌がらせ';
      case 'inappropriate':
        return '不適切なコンテンツ';
      case 'misinformation':
        return '誤情報・デマ';
      case 'other':
        return 'その他';
      default:
        return reason;
    }
  }

  @override
  Widget build(BuildContext context) {
    final createdAt = widget.data['createdAt'] as Timestamp?;
    final timeAgo = createdAt != null
        ? timeago.format(createdAt.toDate(), locale: 'ja')
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          setState(() => _isExpanded = !_isExpanded);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ヘッダー
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: widget.data['contentType'] == 'post'
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.data['contentType'] == 'post' ? '投稿' : 'コメント',
                      style: TextStyle(
                        color: widget.data['contentType'] == 'post'
                            ? AppColors.primary
                            : AppColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getReasonLabel(widget.data['reason'] ?? ''),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    timeAgo,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),

              // 被通報者情報
              if (_reportedUser != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('被通報者: ', style: TextStyle(fontSize: 12)),
                    Text(
                      _reportedUser!['displayName'] ?? '名前なし',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(累計通報: ${_reportedUser!['reportCount'] ?? 0}件)',
                      style: TextStyle(color: AppColors.error, fontSize: 12),
                    ),
                  ],
                ),
              ],

              // 展開時の詳細
              if (_isExpanded) ...[
                const Divider(height: 24),

                // 通報者情報
                if (_reporterUser != null) ...[
                  _buildInfoRow(
                    '通報者',
                    '${_reporterUser!['displayName'] ?? '名前なし'} (通報回数: $_reporterReportCount件)',
                  ),
                  const SizedBox(height: 8),
                ],

                // UID表示
                _buildInfoRow(
                  '被通報者UID',
                  widget.data['targetUserId'] ?? '',
                  canCopy: true,
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  '通報者UID',
                  widget.data['reporterId'] ?? '',
                  canCopy: true,
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  'コンテンツID',
                  widget.data['contentId'] ?? '',
                  canCopy: true,
                ),

                // 対処ボタン（未対応の場合のみ）
                if (widget.data['status'] == 'pending') ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _handleAction('dismissed'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                          ),
                          child: const Text('虚偽判定'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _handleAction('resolved'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.success,
                          ),
                          child: const Text('問題なし'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _handleAction('delete_post'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.error,
                          ),
                          child: const Text('投稿削除'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],

              // 展開アイコン
              Center(
                child: Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool canCopy = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        if (canCopy)
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('コピーしました'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ],
    );
  }

  Future<void> _handleAction(String action) async {
    try {
      final now = FieldValue.serverTimestamp();

      if (action == 'dismissed') {
        // 虚偽判定 - 通報者の徳ポイント減少（TODO: Cloud Function呼び出し）
        await _firestore.collection('reports').doc(widget.reportId).update({
          'status': 'dismissed',
          'reviewedAt': now,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('虚偽判定しました'),
              backgroundColor: AppColors.warning,
            ),
          );
        }
      } else if (action == 'resolved') {
        // 問題なし - 投稿を再表示、通報カウントリセット
        if (widget.data['contentType'] == 'post') {
          await _firestore
              .collection('posts')
              .doc(widget.data['contentId'])
              .update({
                'isHidden': false,
                'hiddenAt': FieldValue.delete(),
                'hiddenReason': FieldValue.delete(),
              });
        }
        await _firestore.collection('reports').doc(widget.reportId).update({
          'status': 'resolved',
          'reviewedAt': now,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('問題なしとして処理しました'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else if (action == 'delete_post') {
        // 投稿削除
        if (widget.data['contentType'] == 'post') {
          await _firestore
              .collection('posts')
              .doc(widget.data['contentId'])
              .delete();
          // 投稿者に通知
          await _firestore
              .collection('users')
              .doc(widget.data['targetUserId'])
              .collection('notifications')
              .add({
                'type': 'post_deleted',
                'title': '投稿が削除されました',
                'body': '規約違反のため、投稿が削除されました。',
                'isRead': false,
                'createdAt': now,
              });
        }
        await _firestore.collection('reports').doc(widget.reportId).update({
          'status': 'resolved',
          'reviewedAt': now,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('投稿を削除しました'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }
}
