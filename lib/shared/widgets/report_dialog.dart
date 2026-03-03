// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_messages.dart';
import '../../core/utils/snackbar_helper.dart';
import '../providers/moderation_provider.dart';
import '../services/moderation_service.dart';

/// 通報ダイアログ
class ReportDialog extends ConsumerStatefulWidget {
  final String contentId;
  final String contentType; // "post" | "comment"
  final String targetUserId;
  final String? contentPreview;

  const ReportDialog({
    super.key,
    required this.contentId,
    required this.contentType,
    required this.targetUserId,
    this.contentPreview,
  });

  /// 通報ダイアログを表示
  static Future<bool?> show({
    required BuildContext context,
    required String contentId,
    required String contentType,
    required String targetUserId,
    String? contentPreview,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => ReportDialog(
        contentId: contentId,
        contentType: contentType,
        targetUserId: targetUserId,
        contentPreview: contentPreview,
      ),
    );
  }

  @override
  ConsumerState<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends ConsumerState<ReportDialog> {
  ReportReason? _selectedReason;
  final _otherReasonController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) {
      setState(() => _error = '通報理由を選択してください');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = ref.read(moderationServiceProvider);

      String reason = _selectedReason!.label;
      if (_selectedReason == ReportReason.other &&
          _otherReasonController.text.isNotEmpty) {
        reason = _otherReasonController.text.trim();
      }

      await service.reportContent(
        contentId: widget.contentId,
        contentType: widget.contentType,
        reason: reason,
        targetUserId: widget.targetUserId,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        SnackBarHelper.showSuccess(context, AppMessages.success.reportSent);
      }
    } on ModerationException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = AppMessages.error.reportFailed);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('🚨', style: TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 12),
          Text(widget.contentType == 'post' ? '投稿を通報' : 'コメントを通報'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '通報理由を選択してください',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),

            // プレビュー（あれば）
            if (widget.contentPreview != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.contentPreview!,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 通報理由選択
            ...ReportReason.values.map((reason) {
              return RadioListTile<ReportReason>(
                value: reason,
                groupValue: _selectedReason,
                onChanged: (value) => setState(() => _selectedReason = value),
                title: Text(reason.label),
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                activeColor: AppColors.primary,
              );
            }),

            // その他の場合のテキストフィールド
            if (_selectedReason == ReportReason.other) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _otherReasonController,
                maxLines: 2,
                maxLength: 100,
                decoration: const InputDecoration(hintText: '具体的な理由を入力してください'),
              ),
            ],

            // エラー表示
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            Text(
              '※ 虚偽の通報を繰り返すと、あなたの徳ポイントが下がることがあります',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textHint),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('通報する'),
        ),
      ],
    );
  }
}

/// 通報ボタン（アイコンボタン）
class ReportButton extends StatelessWidget {
  final String contentId;
  final String contentType;
  final String targetUserId;
  final String? contentPreview;
  final double size;

  const ReportButton({
    super.key,
    required this.contentId,
    required this.contentType,
    required this.targetUserId,
    this.contentPreview,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.flag_outlined, size: size, color: AppColors.textHint),
      onPressed: () => ReportDialog.show(
        context: context,
        contentId: contentId,
        contentType: contentType,
        targetUserId: targetUserId,
        contentPreview: contentPreview,
      ),
      tooltip: '通報',
      visualDensity: VisualDensity.compact,
    );
  }
}

/// ネガティブコンテンツ検出時のエラーダイアログ
class NegativeContentDialog extends StatelessWidget {
  final String message;

  const NegativeContentDialog({super.key, required this.message});

  static Future<void> show({
    required BuildContext context,
    required String message,
  }) {
    return showDialog(
      context: context,
      builder: (context) =>
          NegativeContentDialog(message: message),
    );
  }

  @override
  Widget build(BuildContext context) {
    // メッセージを解析して、理由と提案を分離
    final parts = message.split('\n\n');
    final reason = parts.isNotEmpty ? parts[0] : message;
    final suggestion = parts.length > 1 ? parts[1] : null;
    final virtueInfo = parts.length > 2 ? parts[2] : null;

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('😢', style: TextStyle(fontSize: 28)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('ちょっと待って', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reason, style: Theme.of(context).textTheme.bodyMedium),
            if (suggestion != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💡', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        suggestion
                            .replaceFirst('💡 提案: ', '')
                            .replaceFirst('💡 ', ''),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: AppColors.info),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (virtueInfo != null) ...[
              const SizedBox(height: 12),
              Text(
                virtueInfo,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.textHint),
              ),
            ],
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
