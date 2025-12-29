import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/services/inquiry_service.dart';

/// 管理者用問い合わせ一覧画面
class AdminInquiryListScreen extends ConsumerStatefulWidget {
  const AdminInquiryListScreen({super.key});

  @override
  ConsumerState<AdminInquiryListScreen> createState() =>
      _AdminInquiryListScreenState();
}

class _AdminInquiryListScreenState
    extends ConsumerState<AdminInquiryListScreen> {
  final _inquiryService = InquiryService();
  InquiryStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('問い合わせ管理'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          // フィルターボタン
          PopupMenuButton<InquiryStatus?>(
            icon: Badge(
              isLabelVisible: _statusFilter != null,
              child: const Icon(Icons.filter_list),
            ),
            onSelected: (status) {
              setState(() => _statusFilter = status);
            },
            itemBuilder: (context) => [
              const PopupMenuItem<InquiryStatus?>(
                value: null,
                child: Text('すべて'),
              ),
              PopupMenuItem<InquiryStatus>(
                value: InquiryStatus.open,
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('未対応'),
                  ],
                ),
              ),
              PopupMenuItem<InquiryStatus>(
                value: InquiryStatus.inProgress,
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.info,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('対応中'),
                  ],
                ),
              ),
              PopupMenuItem<InquiryStatus>(
                value: InquiryStatus.resolved,
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('解決済み'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: StreamBuilder<List<InquiryModel>>(
          stream: _inquiryService.getAllInquiries(statusFilter: _statusFilter),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            final inquiries = snapshot.data ?? [];

            if (inquiries.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('📭', style: TextStyle(fontSize: 64)),
                    const SizedBox(height: 16),
                    Text(
                      _statusFilter != null
                          ? '${_statusFilter!.label}の問い合わせはありません'
                          : '問い合わせがありません',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: inquiries.length,
              itemBuilder: (context, index) {
                final inquiry = inquiries[index];
                return _AdminInquiryCard(inquiry: inquiry);
              },
            );
          },
        ),
      ),
    );
  }
}

class _AdminInquiryCard extends StatelessWidget {
  final InquiryModel inquiry;

  const _AdminInquiryCard({required this.inquiry});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/admin/inquiry/${inquiry.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ヘッダー行
              Row(
                children: [
                  // ユーザー情報
                  CircleAvatar(
                    radius: 18,
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
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          timeago.format(inquiry.createdAt, locale: 'ja'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textHint),
                        ),
                      ],
                    ),
                  ),
                  // 未読バッジ
                  if (inquiry.hasUnreadMessage)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // カテゴリとステータス
              Row(
                children: [
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
                  const SizedBox(width: 8),
                  _StatusBadge(status: inquiry.status),
                ],
              ),

              const SizedBox(height: 8),

              // 件名
              Text(
                inquiry.subject,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: inquiry.hasUnreadMessage
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
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
