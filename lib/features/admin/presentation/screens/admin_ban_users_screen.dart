import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/avatar_selector.dart';

/// 管理者用BANユーザー管理画面
class AdminBanUsersScreen extends ConsumerStatefulWidget {
  const AdminBanUsersScreen({super.key});

  @override
  ConsumerState<AdminBanUsersScreen> createState() =>
      _AdminBanUsersScreenState();
}

class _AdminBanUsersScreenState extends ConsumerState<AdminBanUsersScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BANユーザー管理'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.warmGradient),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('banAppeals')
              .where('status', isEqualTo: 'open')
              .orderBy('updatedAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            if (snapshot.hasError) {
              return Center(child: Text('エラーが発生しました: ${snapshot.error}'));
            }

            final appeals = snapshot.data?.docs ?? [];

            if (appeals.isEmpty) {
              return _buildEmptyState();
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: appeals.length,
              itemBuilder: (context, index) {
                final appeal = appeals[index];
                final data = appeal.data() as Map<String, dynamic>;
                return _BanUserCard(appealId: appeal.id, data: data);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: AppColors.success.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            '対応が必要なBANユーザーはいません',
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// BANユーザーカード
class _BanUserCard extends StatelessWidget {
  final String appealId;
  final Map<String, dynamic> data;

  const _BanUserCard({required this.appealId, required this.data});

  @override
  Widget build(BuildContext context) {
    final bannedUserId = data['bannedUserId'] as String? ?? '';
    final messages = data['messages'] as List<dynamic>? ?? [];
    final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate();

    // 未読メッセージ数を計算（メッセージごとの既読フラグ方式）
    // ユーザーからのメッセージで readByAdmin != true のものをカウント
    final unreadCount = messages.where((m) {
      final msg = m as Map<String, dynamic>;
      return msg['isAdmin'] != true && msg['readByAdmin'] != true;
    }).length;

    // 最後のメッセージ
    final lastMessage = messages.isNotEmpty
        ? (messages.last as Map<String, dynamic>)['content'] as String? ?? ''
        : 'メッセージなし';

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(bannedUserId)
          .get(),
      builder: (context, userSnapshot) {
        String displayName = 'ユーザー';
        int avatarIndex = 0;
        String banStatus = 'unknown';

        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          final userData = userSnapshot.data!.data() as Map<String, dynamic>;
          displayName = userData['displayName'] as String? ?? 'ユーザー';
          avatarIndex = userData['avatarIndex'] as int? ?? 0;
          banStatus = userData['banStatus'] as String? ?? 'unknown';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () {
              // チャット画面へ遷移
              context.push(
                '/ban-appeal',
                extra: {'appealId': appealId, 'targetUserId': bannedUserId},
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // アバター
                  Stack(
                    children: [
                      AvatarWidget(avatarIndex: avatarIndex, size: 48),
                      // BANステータスバッジ
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: banStatus == 'permanent'
                                ? AppColors.error
                                : Colors.orange,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(
                            banStatus == 'permanent'
                                ? Icons.gavel
                                : Icons.block,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // 情報
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (updatedAt != null)
                              Text(
                                timeago.format(updatedAt, locale: 'ja'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: banStatus == 'permanent'
                                    ? AppColors.error.withValues(alpha: 0.1)
                                    : Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                banStatus == 'permanent' ? '永久BAN' : '一時BAN',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: banStatus == 'permanent'
                                      ? AppColors.error
                                      : Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lastMessage,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 未読バッジ
                  if (unreadCount > 0)
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
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
