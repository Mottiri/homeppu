import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_messages.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../shared/services/inquiry_service.dart';
import '../../../../shared/services/media_service.dart';
import '../../../../shared/widgets/full_screen_image_viewer.dart';

/// 問い合わせ詳細画面
class InquiryDetailScreen extends ConsumerStatefulWidget {
  final String inquiryId;

  const InquiryDetailScreen({super.key, required this.inquiryId});

  @override
  ConsumerState<InquiryDetailScreen> createState() =>
      _InquiryDetailScreenState();
}

class _InquiryDetailScreenState extends ConsumerState<InquiryDetailScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _inquiryService = InquiryService();

  File? _selectedImage;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // 未読をクリア & 閲覧中フラグを設定
    _inquiryService.markAsRead(widget.inquiryId);
    _inquiryService.setUserViewing(widget.inquiryId, true);
  }

  @override
  void dispose() {
    // 閲覧中フラグを解除
    _inquiryService.setUserViewing(widget.inquiryId, false);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
    });
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty && _selectedImage == null) return;

    setState(() => _isSending = true);

    try {
      String? imageUrl;

      if (_selectedImage != null) {
        final mediaService = MediaService();
        final userId = FirebaseAuth.instance.currentUser?.uid;
        if (userId == null) {
          throw Exception(AppMessages.error.unauthorized);
        }
        imageUrl = await mediaService.uploadInquiryImage(
          _selectedImage!,
          userId: userId,
        );
      }

      await _inquiryService.sendMessage(
        inquiryId: widget.inquiryId,
        content:
            content.isEmpty ? AppMessages.inquiry.imageOnlyMessage : content,
        imageUrl: imageUrl,
      );

      _messageController.clear();
      _selectedImage = null;

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
    } catch (e) {
      debugPrint('InquiryDetailScreen send failed: $e');
      if (mounted) {
        SnackBarHelper.showError(context, AppMessages.error.general);
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppMessages.inquiry.detailTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: Column(
          children: [
            // ヘッダー（問い合わせ情報）
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight.withValues(
                                alpha: 0.3,
                              ),
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
                          const Spacer(),
                          _StatusBadge(status: inquiry.status),
                        ],
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

            // 入力エリア
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 選択した画像のプレビュー
            if (_selectedImage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _selectedImage!,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: _removeImage,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Row(
              children: [
                // 画像添付ボタン
                IconButton(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  color: AppColors.textSecondary,
                ),
                // テキスト入力
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: AppMessages.inquiry.messageHint,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                // 送信ボタン
                IconButton(
                  onPressed: _isSending ? null : _sendMessage,
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : const Icon(Icons.send),
                  color: AppColors.primary,
                ),
              ],
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
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAdmin) ...[
            // 運営チームアバター
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
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isAdmin
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                // 送信者名
                Text(
                  message.senderName,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                // メッセージバブル
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isAdmin ? Colors.white : AppColors.primary,
                    borderRadius: BorderRadius.circular(16).copyWith(
                      bottomLeft: isAdmin ? const Radius.circular(4) : null,
                      bottomRight: isAdmin ? null : const Radius.circular(4),
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
                      // 画像
                      if (message.imageUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GestureDetector(
                            onTap: () => FullScreenImageViewer.show(
                              context,
                              message.imageUrl!,
                              heroTag: 'inquiry_image_${message.id}',
                            ),
                            child: Hero(
                              tag: 'inquiry_image_${message.id}',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  message.imageUrl!,
                                  width: 200,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // テキスト
                      Text(
                        message.content,
                        style: TextStyle(
                          color: isAdmin ? AppColors.textPrimary : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // 時刻
                Text(
                  timeago.format(message.createdAt, locale: 'ja'),
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColors.textHint),
                ),
              ],
            ),
          ),
          if (!isAdmin) const SizedBox(width: 48),
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
