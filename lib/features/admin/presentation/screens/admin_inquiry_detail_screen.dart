import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/services/inquiry_service.dart';

/// 管理者用問い合わせ詳細画面
class AdminInquiryDetailScreen extends ConsumerStatefulWidget {
  final String inquiryId;

  const AdminInquiryDetailScreen({super.key, required this.inquiryId});

  @override
  ConsumerState<AdminInquiryDetailScreen> createState() =>
      _AdminInquiryDetailScreenState();
}

class _AdminInquiryDetailScreenState
    extends ConsumerState<AdminInquiryDetailScreen> {
  final _replyController = TextEditingController();
  final _scrollController = ScrollController();
  final _inquiryService = InquiryService();

  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // 管理者の未読をクリア
    _inquiryService.markAsReadByAdmin(widget.inquiryId);
  }

  @override
  void dispose() {
    _replyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final content = _replyController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSending = true);

    try {
      await _inquiryService.sendAdminReply(
        inquiryId: widget.inquiryId,
        content: content,
      );

      _replyController.clear();

      // スクロールを最下部へ
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('返信を送信しました'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('送信に失敗しました: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _changeStatus(InquiryStatus newStatus) async {
    try {
      await _inquiryService.updateStatus(widget.inquiryId, newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ステータスを「${newStatus.label}」に変更しました'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('変更に失敗しました: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('問い合わせ詳細'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          // ステータス変更メニュー
          PopupMenuButton<InquiryStatus>(
            icon: const Icon(Icons.edit_note),
            tooltip: 'ステータス変更',
            onSelected: _changeStatus,
            itemBuilder: (context) => InquiryStatus.values
                .map(
                  (status) => PopupMenuItem<InquiryStatus>(
                    value: status,
                    child: Row(
                      children: [
                        _StatusDot(status: status),
                        const SizedBox(width: 8),
                        Text(status.label),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: Column(
          children: [
            // ヘッダー（問い合わせ情報 + ユーザー情報）
            StreamBuilder<InquiryModel?>(
              stream: _inquiryService.getInquiry(widget.inquiryId),
              builder: (context, snapshot) {
                final inquiry = snapshot.data;
                if (inquiry == null) return const SizedBox.shrink();

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ユーザー情報
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppColors.primaryLight,
                            child: Text(
                              inquiry.userDisplayName.isNotEmpty
                                  ? inquiry.userDisplayName[0]
                                  : '?',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  inquiry.userDisplayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  timeago.format(
                                    inquiry.createdAt,
                                    locale: 'ja',
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.textHint),
                                ),
                              ],
                            ),
                          ),
                          _StatusBadge(status: inquiry.status),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // カテゴリと件名
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          inquiry.category.label,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        inquiry.subject,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              },
            ),

            // メッセージ一覧
            Expanded(
              child: StreamBuilder<List<InquiryMessageModel>>(
                stream: _inquiryService.getMessages(widget.inquiryId),
                builder: (context, snapshot) {
                  final messages = snapshot.data ?? [];

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return _MessageBubble(message: message);
                    },
                  );
                },
              ),
            ),

            // 返信入力エリア
            _buildReplyArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _replyController,
                decoration: InputDecoration(
                  hintText: '返信を入力...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendReply(),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              onPressed: _isSending ? null : _sendReply,
              mini: true,
              backgroundColor: AppColors.primary,
              child: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final InquiryMessageModel message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isAdmin = message.isAdmin;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isAdmin
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isAdmin) const SizedBox(width: 48),
          Flexible(
            child: Column(
              crossAxisAlignment: isAdmin
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  message.senderName,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isAdmin ? AppColors.primary : Colors.white,
                    borderRadius: BorderRadius.circular(16).copyWith(
                      bottomRight: isAdmin ? const Radius.circular(4) : null,
                      bottomLeft: isAdmin ? null : const Radius.circular(4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.imageUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              message.imageUrl!,
                              width: 200,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      Text(
                        message.content,
                        style: TextStyle(
                          color: isAdmin ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeago.format(message.createdAt, locale: 'ja'),
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColors.textHint),
                ),
              ],
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(width: 8),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.support_agent,
                color: Colors.white,
                size: 24,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final InquiryStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case InquiryStatus.open:
        color = AppColors.warning;
        break;
      case InquiryStatus.inProgress:
        color = AppColors.info;
        break;
      case InquiryStatus.resolved:
        color = AppColors.success;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final InquiryStatus status;

  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case InquiryStatus.open:
        color = AppColors.warning;
        break;
      case InquiryStatus.inProgress:
        color = AppColors.info;
        break;
      case InquiryStatus.resolved:
        color = AppColors.success;
        break;
    }

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
