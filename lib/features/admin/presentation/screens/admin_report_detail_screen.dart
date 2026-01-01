import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/avatar_selector.dart';

/// 通報詳細画面
class AdminReportDetailScreen extends ConsumerStatefulWidget {
  final String reportId;

  const AdminReportDetailScreen({super.key, required this.reportId});

  @override
  ConsumerState<AdminReportDetailScreen> createState() =>
      _AdminReportDetailScreenState();
}

class _AdminReportDetailScreenState
    extends ConsumerState<AdminReportDetailScreen> {
  final _firestore = FirebaseFirestore.instance;
  bool _showTechDetails = false;
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通報詳細'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: StreamBuilder<DocumentSnapshot>(
          stream: _firestore
              .collection('reports')
              .doc(widget.reportId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final report = snapshot.data!;
            if (!report.exists) {
              return const Center(child: Text('通報が見つかりません'));
            }

            final data = report.data() as Map<String, dynamic>;
            return _buildContent(data);
          },
        ),
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> data) {
    final createdAt = data['createdAt'] as Timestamp?;
    final timeAgo = createdAt != null
        ? timeago.format(createdAt.toDate(), locale: 'ja')
        : '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ステータスと時間
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _getStatusColor(data['status']).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _getStatusLabel(data['status']),
                  style: TextStyle(
                    color: _getStatusColor(data['status']),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(timeAgo, style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 16),

          // 通報理由
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.report, color: AppColors.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '通報理由',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          _getReasonLabel(data['reason'] ?? ''),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 通報された投稿
          _buildReportedContentSection(data),
          const SizedBox(height: 16),

          // 被通報者
          _buildUserSection(
            title: '被通報者',
            userId: data['targetUserId'],
            icon: Icons.person_off,
            color: AppColors.error,
          ),
          const SizedBox(height: 16),

          // 通報者
          _buildUserSection(
            title: '通報者',
            userId: data['reporterId'],
            icon: Icons.flag,
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),

          // 技術情報（折りたたみ）
          _buildTechDetailsSection(data),
          const SizedBox(height: 24),

          // アクションボタン
          if (data['status'] == 'pending') _buildActionButtons(data),
        ],
      ),
    );
  }

  Widget _buildReportedContentSection(Map<String, dynamic> data) {
    final contentId = data['contentId'];
    final contentType = data['contentType'];
    // コンテンツタイプに応じてコレクションを切り替え
    final collection = contentType == 'post' ? 'posts' : 'comments';

    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection(collection).doc(contentId).get(),
      builder: (context, snapshot) {
        final doc = snapshot.data;
        final docData = doc?.data() as Map<String, dynamic>?;
        final isHidden = docData?['isHidden'] == true;

        // 遷移先の投稿IDを特定
        String? targetPostId;
        if (contentType == 'post') {
          targetPostId = contentId;
        } else if (docData != null) {
          // コメントの場合は親投稿IDを取得
          targetPostId = docData['postId'];
        }

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: targetPostId != null
                ? () => context.push('/post/$targetPostId')
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ヘッダー
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        contentType == 'post' ? Icons.article : Icons.comment,
                        color: AppColors.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '通報された${contentType == 'post' ? '投稿' : 'コメント'}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.error,
                        ),
                      ),
                      const Spacer(),
                      // 累計通報数バッジ
                      FutureBuilder<QuerySnapshot>(
                        future: _firestore
                            .collection('reports')
                            .where('contentId', isEqualTo: contentId)
                            .get(),
                        builder: (context, snap) {
                          final count = snap.data?.size ?? 0;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '累計 $count 件',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // コンテンツ
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isHidden)
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.visibility_off,
                                color: AppColors.warning,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '現在非表示中',
                                style: TextStyle(color: AppColors.warning),
                              ),
                            ],
                          ),
                        ),
                      if (docData != null) ...[
                        Text(
                          docData['content'] ?? '(内容なし)',
                          style: const TextStyle(fontSize: 14),
                          maxLines: 10,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // 遷移ヒント
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'タップして詳細を表示',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 12,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ] else ...[
                        Text(
                          'コンテンツが削除されています',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserSection({
    required String title,
    required String userId,
    required IconData icon,
    required Color color,
  }) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        final user = snapshot.data?.data() as Map<String, dynamic>?;

        return Card(
          child: InkWell(
            onTap: () => context.push('/admin/user/$userId'),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // アイコンバッジ
                  Stack(
                    children: [
                      AvatarWidget(
                        avatarIndex: user?['avatarIndex'] ?? 0,
                        size: 50,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: Colors.white, size: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          user?['displayName'] ?? '不明',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (user != null)
                          Text(
                            '累計通報: ${user['reportCount'] ?? 0}件',
                            style: TextStyle(
                              fontSize: 12,
                              color: (user['reportCount'] ?? 0) > 0
                                  ? AppColors.error
                                  : AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTechDetailsSection(Map<String, dynamic> data) {
    return Card(
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _showTechDetails = !_showTechDetails),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.code, color: AppColors.textSecondary),
                  const SizedBox(width: 12),
                  const Text('技術情報'),
                  const Spacer(),
                  Icon(
                    _showTechDetails ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_showTechDetails)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  _buildCopyableRow('通報ID', widget.reportId),
                  _buildCopyableRow('コンテンツID', data['contentId'] ?? ''),
                  _buildCopyableRow('被通報者UID', data['targetUserId'] ?? ''),
                  _buildCopyableRow('通報者UID', data['reporterId'] ?? ''),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCopyableRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
      ),
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> data) {
    return Column(
      children: [
        // メインアクション
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                label: '問題なし',
                subtitle: '投稿を再表示',
                icon: Icons.check_circle_outline,
                color: AppColors.success,
                onTap: () => _handleAction('resolved', data),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                label: '投稿削除',
                subtitle: '規約違反として削除',
                icon: Icons.delete_outline,
                color: AppColors.error,
                onTap: () => _handleAction('delete_post', data),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // セカンダリアクション
        SizedBox(
          width: double.infinity,
          child: _buildActionButton(
            label: '虚偽通報',
            subtitle: '通報者にペナルティ',
            icon: Icons.block,
            color: AppColors.textSecondary,
            onTap: () => _handleAction('dismissed', data),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isProcessing ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 14,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: color.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(String action, Map<String, dynamic> data) async {
    setState(() => _isProcessing = true);
    try {
      final now = FieldValue.serverTimestamp();

      if (action == 'dismissed') {
        await _firestore.collection('reports').doc(widget.reportId).update({
          'status': 'dismissed',
          'reviewedAt': now,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('虚偽判定しました'),
              backgroundColor: AppColors.warning,
            ),
          );
          context.pop();
        }
      } else if (action == 'resolved') {
        if (data['contentType'] == 'post') {
          await _firestore.collection('posts').doc(data['contentId']).update({
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
            SnackBar(
              content: const Text('問題なしとして処理しました'),
              backgroundColor: AppColors.success,
            ),
          );
          context.pop();
        }
      } else if (action == 'delete_post') {
        if (data['contentType'] == 'post') {
          await _firestore.collection('posts').doc(data['contentId']).delete();
          await _firestore
              .collection('users')
              .doc(data['targetUserId'])
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
            SnackBar(
              content: const Text('投稿を削除しました'),
              backgroundColor: AppColors.error,
            ),
          );
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return AppColors.warning;
      case 'resolved':
        return AppColors.success;
      case 'dismissed':
        return AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'pending':
        return '未対応';
      case 'resolved':
        return '対応済み';
      case 'dismissed':
        return '虚偽判定';
      default:
        return status ?? '不明';
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
}
