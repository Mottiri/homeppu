import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_messages.dart';
import '../models/campaign_model.dart';
import '../services/campaign_service.dart';

Future<void> showCampaignDialog({
  required BuildContext context,
  required CampaignModel campaign,
  required CampaignService service,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _CampaignDialog(
      campaign: campaign,
      service: service,
    ),
  );
}

class _CampaignDialog extends StatelessWidget {
  final CampaignModel campaign;
  final CampaignService service;

  const _CampaignDialog({
    required this.campaign,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final theme = Theme.of(context).textTheme;
    final imagePath = campaign.imagePath?.trim();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 340,
          maxHeight: screenHeight * 0.75,
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // タイトル
                    Text(
                      campaign.title,
                      style: theme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 本文（Markdown対応）
                    MarkdownBody(
                      data: campaign.body,
                      styleSheet: MarkdownStyleSheet.fromTheme(
                        Theme.of(context),
                      ).copyWith(
                        p: theme.bodyMedium,
                        a: theme.bodyMedium?.copyWith(
                          color: AppColors.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      onTapLink: (_, href, title) {
                        if (href != null) {
                          launchUrl(Uri.parse(href));
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // キャンペーン画像
                    if (imagePath != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            imagePath,
                            width: double.infinity,
                            fit: BoxFit.contain,
                            errorBuilder: (_, e, s) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),

                    // フッターノート
                    if (campaign.footerNote != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          campaign.footerNote!,
                          style: theme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ),

                    // 期限表示
                    Text(
                      _formatEndDate(campaign.endDate),
                      style: theme.bodySmall?.copyWith(
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ボタンエリア
            Row(
              children: [
                TextButton(
                  onPressed: () async {
                    await service.dismiss(campaign.id);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Text(
                    AppMessages.label.dontShowAgain,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(AppMessages.label.close),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatEndDate(DateTime endDate) {
    final displayDate = endDate.subtract(const Duration(days: 1));
    return AppMessages.campaignEndDate(displayDate.month, displayDate.day);
  }
}
