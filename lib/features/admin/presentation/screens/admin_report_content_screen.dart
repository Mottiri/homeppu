import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/dialog_helper.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/widgets/avatar_selector.dart';

/// コンテンツ単位の通報詳細画面
class AdminReportContentScreen extends ConsumerStatefulWidget {
  final String contentId;

  const AdminReportContentScreen({super.key, required this.contentId});

  @override
  ConsumerState<AdminReportContentScreen> createState() =>
      _AdminReportContentScreenState();
}

class _AdminReportContentScreenState
    extends ConsumerState<AdminReportContentScreen> {
  final _firestore = FirebaseFirestore.instance;
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
        child: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('reports')
              .where('contentId', isEqualTo: widget.contentId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final reports = snapshot.data!.docs;
            if (reports.isEmpty) {
              return const Center(child: Text('通報が見つかりません'));
            }

            final firstData = reports.first.data() as Map<String, dynamic>;
            final contentType = firstData['contentType'] as String? ?? 'post';
            final targetUserId = firstData['targetUserId'] as String? ?? '';

            return Column(
              children: [
                // 投稿内容セクション
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 投稿プレビュー
                        _buildContentPreview(contentType, targetUserId),
                        const SizedBox(height: 24),

                        // 通報者一覧ヘッダー
                        Row(
                          children: [
                            const Text(
                              '通報者一覧',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${reports.length}件',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 通報者リスト
                        ...reports.map((report) {
                          final data = report.data() as Map<String, dynamic>;
                          return _buildReporterCard(data);
                        }),
                      ],
                    ),
                  ),
                ),

                // アクションボタン
                _buildActionButtons(contentType, targetUserId, reports),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContentPreview(String contentType, String targetUserId) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore
          .collection(contentType == 'post' ? 'posts' : 'comments')
          .doc(widget.contentId)
          .get(),
      builder: (context, contentSnapshot) {
        return FutureBuilder<DocumentSnapshot>(
          future: _firestore.collection('users').doc(targetUserId).get(),
          builder: (context, userSnapshot) {
            final contentData =
                contentSnapshot.data?.data() as Map<String, dynamic>?;
            final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
            final content = contentData?['content'] as String? ?? '';
            final isHidden = contentData?['isVisible'] == false;
            final reportCount = userData?['reportCount'] ?? 0;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ユーザー情報
                    InkWell(
                      onTap: () => context.push('/profile/$targetUserId'),
                      child: Row(
                        children: [
                          AvatarWidget(
                            avatarIndex: userData?['avatarIndex'] ?? 0,
                            size: 48,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  userData?['displayName'] ?? '読み込み中...',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  '投稿者の累計被通報: $reportCount件',
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
                        ],
                      ),
                    ),
                    const Divider(height: 24),

                    // 非表示ステータス
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

                    // コンテンツ
                    if (contentData != null)
                      InkWell(
                        onTap: contentType == 'post'
                            ? () => context.push('/post/${widget.contentId}')
                            : null,
                        child: Text(
                          content.isNotEmpty ? content : '(内容なし)',
                          style: const TextStyle(fontSize: 15),
                        ),
                      )
                    else
                      const Text(
                        '(削除済みまたは取得できません)',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),

                    // 技術情報
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: widget.contentId),
                        );
                        SnackBarHelper.showSuccess(
                          context,
                          AppMessages.admin.idCopied,
                          duration: const Duration(seconds: 1),
                        );
                      },
                      child: Text(
                        'ID: ${widget.contentId}',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildReporterCard(Map<String, dynamic> data) {
    final reporterId = data['reporterId'] as String? ?? '';
    final reason = data['reason'] as String? ?? '';
    final createdAt = data['createdAt'] as Timestamp?;
    final timeAgo = createdAt != null
        ? timeago.format(createdAt.toDate(), locale: 'ja')
        : '';

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _firestore.collection('users').doc(reporterId).get(),
        _firestore
            .collection('reports')
            .where('reporterId', isEqualTo: reporterId)
            .count()
            .get(),
      ]),
      builder: (context, snapshot) {
        final userData = snapshot.data?[0] is DocumentSnapshot
            ? (snapshot.data![0] as DocumentSnapshot).data()
                  as Map<String, dynamic>?
            : null;
        final totalReports = snapshot.data?[1] is AggregateQuerySnapshot
            ? (snapshot.data![1] as AggregateQuerySnapshot).count ?? 0
            : 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => context.push('/profile/$reporterId'),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  AvatarWidget(
                    avatarIndex: userData?['avatarIndex'] ?? 0,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userData?['displayName'] ?? '読み込み中...',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _getReasonLabel(reason),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.error,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              timeAgo,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 累計通報回数
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '累計通報',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        '$totalReports件',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: totalReports > 3
                              ? AppColors.error
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(
    String contentType,
    String targetUserId,
    List<QueryDocumentSnapshot> reports,
  ) {
    // 未対応の通報があるかチェック
    final hasPending = reports.any((r) {
      final data = r.data() as Map<String, dynamic>;
      return data['status'] == 'pending';
    });

    if (!hasPending) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Text(
          'すべての通報が対応済みです',
          style: TextStyle(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 問題なし（再表示）ボタン
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : () => _handleResolve(reports),
                icon: const Icon(Icons.visibility),
                label: const Text('問題なし'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 投稿削除ボタン
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _handleDelete(contentType, targetUserId, reports),
                icon: const Icon(Icons.delete),
                label: const Text('投稿削除'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleResolve(List<QueryDocumentSnapshot> reports) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('問題なしとして処理'),
        content: const Text('この投稿を問題なしとして処理し、再表示しますか？\nすべての通報が対応済みになります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('実行'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    try {
      final now = FieldValue.serverTimestamp();
      final batch = _firestore.batch();

      // 投稿を再表示
      final firstData = reports.first.data() as Map<String, dynamic>;
      if (firstData['contentType'] == 'post') {
        final postRef = _firestore.collection('posts').doc(widget.contentId);
        batch.update(postRef, {
          'isVisible': true,
          'hiddenAt': FieldValue.delete(),
          'hiddenReason': FieldValue.delete(),
        });
      }

      // すべての通報を resolved に
      for (final report in reports) {
        final data = report.data() as Map<String, dynamic>;
        if (data['status'] == 'pending') {
          batch.update(report.reference, {
            'status': 'resolved',
            'reviewedAt': now,
          });
        }
      }

      await batch.commit();

      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          AppMessages.admin.reportBatchResolved(reports.length),
        );
        context.pop();
      }
    } catch (e) {
      debugPrint('AdminReportContentScreen: resolve failed: $e');
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.admin.reportProcessFailed);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleDelete(
    String contentType,
    String targetUserId,
    List<QueryDocumentSnapshot> reports,
  ) async {
    final confirmed = await DialogHelper.showConfirmDialog(
      context: context,
      title: AppMessages.admin.deletePostTitle,
      message: AppMessages.admin.deletePostWithNotifyMessage,
      confirmText: AppMessages.label.delete,
      cancelText: AppMessages.label.cancel,
      isDangerous: true,
      barrierDismissible: false,
    );

    if (!confirmed) return;

    setState(() => _isProcessing = true);
    try {
      final now = FieldValue.serverTimestamp();
      final batch = _firestore.batch();

      // 投稿を削除
      if (contentType == 'post') {
        final postRef = _firestore.collection('posts').doc(widget.contentId);
        batch.delete(postRef);

        // 投稿者に通知
        final notifRef = _firestore
            .collection('users')
            .doc(targetUserId)
            .collection('notifications')
            .doc();
        batch.set(notifRef, {
          'type': 'post_deleted',
          'title': '投稿が削除されました',
          'body': '規約違反のため、投稿が削除されました。',
          'isRead': false,
          'createdAt': now,
        });
      }

      // すべての通報を resolved に
      for (final report in reports) {
        batch.update(report.reference, {
          'status': 'resolved',
          'reviewedAt': now,
        });
      }

      await batch.commit();

      if (mounted) {
        SnackBarHelper.showSuccess(context, AppMessages.admin.postDeleted);
        context.pop();
      }
    } catch (e) {
      debugPrint('AdminReportContentScreen: delete failed: $e');
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.admin.reportProcessFailed);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  String _getReasonLabel(String reason) {
    switch (reason) {
      case 'spam':
        return 'スパム';
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
}
