import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/providers/auth_provider.dart';

class BanAppealScreen extends ConsumerStatefulWidget {
  final String? appealId; // 特定の申し立てIDがある場合（管理者用）
  final String? targetUserId; // 管理者が特定のユーザーのチャットを見る場合

  const BanAppealScreen({super.key, this.appealId, this.targetUserId});

  @override
  ConsumerState<BanAppealScreen> createState() => _BanAppealScreenState();
}

class _BanAppealScreenState extends ConsumerState<BanAppealScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  String? _currentAppealId;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _currentAppealId = widget.appealId;
    // 特定のIDが指定されていない場合は既存の申し立てを探す
    if (_currentAppealId == null) {
      _findExistingAppeal();
    } else {
      // チャットを開いた場合、未読メッセージを既読にする
      _markMessagesAsRead();
    }
  }

  // 管理者モードかどうか
  bool get _isAdminMode => widget.targetUserId != null;

  // 未読メッセージを既読にする（メッセージごとのフラグ方式）
  Future<void> _markMessagesAsRead() async {
    if (_currentAppealId == null) return;
    try {
      final docRef = FirebaseFirestore.instance
          .collection('banAppeals')
          .doc(_currentAppealId);

      final doc = await docRef.get();
      if (!doc.exists) return;

      final data = doc.data() as Map<String, dynamic>;
      final messages = List<Map<String, dynamic>>.from(
        (data['messages'] as List<dynamic>? ?? []).map(
          (m) => Map<String, dynamic>.from(m as Map),
        ),
      );

      bool hasChanges = false;
      for (var i = 0; i < messages.length; i++) {
        final msg = messages[i];
        if (_isAdminMode) {
          // 管理者がチャットを開いた場合、ユーザーからのメッセージを既読に
          if (msg['isAdmin'] != true && msg['readByAdmin'] != true) {
            messages[i]['readByAdmin'] = true;
            hasChanges = true;
          }
        } else {
          // ユーザーがチャットを開いた場合、管理者からのメッセージを既読に
          if (msg['isAdmin'] == true && msg['readByUser'] != true) {
            messages[i]['readByUser'] = true;
            hasChanges = true;
          }
        }
      }

      if (hasChanges) {
        await docRef.update({'messages': messages});
      }
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  Future<void> _findExistingAppeal() async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    // 管理者がターゲットを指定している場合はそれを使う、そうでなければ自分のID
    final userIdToCheck = widget.targetUserId ?? currentUser?.uid;

    if (userIdToCheck == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('banAppeals')
          .where('bannedUserId', isEqualTo: userIdToCheck)
          .where('status', isEqualTo: 'open') // 未解決のもの
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _currentAppealId = snapshot.docs.first.id;
        });
        // 未読メッセージを既読にする
        _markMessagesAsRead();
      }
    } catch (e) {
      debugPrint('Error finding appeal: $e');
    }
  }

  // 対応完了確認ダイアログ
  void _showDeleteConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('対応完了'),
        content: const Text('このチャット履歴を削除しますか？\n削除後は復元できません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAppeal();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }

  // チャット履歴を削除
  Future<void> _deleteAppeal() async {
    if (_currentAppealId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('banAppeals')
          .doc(_currentAppealId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('チャット履歴を削除しました')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('削除エラー: $e')));
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isSending = true);

    try {
      final messageData = {
        'senderId': user.uid,
        'content': text,
        'createdAt':
            Timestamp.now(), // 配列内ではserverTimestamp()が使えないためクライアント時刻を使用
        'isAdmin': _isAdminMode, // 管理者モードの場合はtrue
      };

      if (_currentAppealId != null) {
        // 既存のチャットに追加
        await FirebaseFirestore.instance
            .collection('banAppeals')
            .doc(_currentAppealId)
            .update({
              'messages': FieldValue.arrayUnion([messageData]),
              'updatedAt': FieldValue.serverTimestamp(),
            });
      } else {
        // 新規作成
        final docRef = await FirebaseFirestore.instance
            .collection('banAppeals')
            .add({
              'bannedUserId': user.uid,
              'status': 'open',
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
              'messages': [messageData],
            });
        setState(() {
          _currentAppealId = docRef.id;
        });
      }

      _messageController.clear();
      // スクロールを一番下へ
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0, // reverse: true なので 0 が一番下
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('送信エラー: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ユーザー情報取得（状態が変わっている可能性があるためwatch）
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('サポートへの問い合わせ'),
        automaticallyImplyLeading: widget.appealId != null, // 管理者モードなら戻れる
        actions: _isAdminMode && widget.targetUserId != null
            ? [
                IconButton(
                  icon: const Icon(Icons.person),
                  tooltip: 'ユーザープロフィールを見る',
                  onPressed: () {
                    context.push('/profile/${widget.targetUserId}');
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.check_circle_outline),
                  tooltip: '対応完了（チャット削除）',
                  onPressed: () => _showDeleteConfirmDialog(context),
                ),
              ]
            : null,
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) return const Center(child: Text('ログインしていません'));

          // まだチャットが始まっていない場合
          if (_currentAppealId == null) {
            return _buildEmptyState();
          }

          // チャット画面
          return Column(
            children: [
              // BAN理由などの表示エリア（オプション）
              if (!_isAdminMode)
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.grey.shade100,
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          user.banStatus == 'permanent'
                              ? 'アカウントは永久停止されています。\n解除の申し立てはここから管理者へ連絡できます。'
                              : 'アカウントは一時的に制限されています。\n解除の申し立てや詳細はここから管理者へ連絡できます。',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('banAppeals')
                      .doc(_currentAppealId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    if (data == null) return _buildEmptyState();

                    final messages =
                        (data['messages'] as List<dynamic>? ?? [])
                            .map((m) => m as Map<String, dynamic>)
                            .toList()
                          ..sort((a, b) {
                            // 降順ソート（新しいものが上）
                            final ta =
                                (a['createdAt'] as Timestamp?)?.toDate() ??
                                DateTime.now();
                            final tb =
                                (b['createdAt'] as Timestamp?)?.toDate() ??
                                DateTime.now();
                            return tb.compareTo(ta);
                          });

                    // 未読メッセージがあれば既読に更新（非同期で実行）
                    _markMessagesAsRead();

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true, // 新しいメッセージを下に表示するため、リストは逆順にして下から積み上げ
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg['senderId'] == user.uid;
                        final timestamp = (msg['createdAt'] as Timestamp?)
                            ?.toDate();

                        return _buildMessageBubble(
                          content: msg['content'] as String,
                          isMe: isMe,
                          timestamp: timestamp,
                          isAdmin: msg['isAdmin'] as bool? ?? false,
                        );
                      },
                    );
                  },
                ),
              ),
              _buildInputArea(),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラーが発生しました: $e')),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.support_agent,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '異議申し立て・お問い合わせ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '管理者にメッセージを送信して、\nBANの解除や詳細について問い合わせることができます。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
        _buildInputArea(isNew: true),
      ],
    );
  }

  Widget _buildInputArea({bool isNew = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'メッセージを入力...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isSending ? null : _sendMessage,
            icon: _isSending
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({
    required String content,
    required bool isMe,
    required DateTime? timestamp,
    required bool isAdmin,
  }) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (isAdmin && !isMe)
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 4),
                child: Text(
                  '管理者',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? AppColors.primary : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isMe ? const Radius.circular(0) : null,
                  bottomLeft: !isMe ? const Radius.circular(0) : null,
                ),
              ),
              child: Text(
                content,
                style: TextStyle(color: isMe ? Colors.white : Colors.black87),
              ),
            ),
            if (timestamp != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                child: Text(
                  timeago.format(timestamp, locale: 'ja'),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
