# リアクション送信シリアルキュー設計書

## 概要
リアクションスタンプの連続タップ時に、サーバーへの送信が並列実行されFirestoreトランザクションが競合する問題を解決する。
クライアント側にシリアルキューを導入し、サーバー呼び出しを直列化する。

## 現状の問題

```
タップ1 → unawaited(_sendReactionToServer()) → サーバー呼び出しA
タップ2 → unawaited(_sendReactionToServer()) → サーバー呼び出しB（Aと並列）
タップ3 → unawaited(_sendReactionToServer()) → サーバー呼び出しC（A,Bと並列）
→ Firestoreトランザクション競合、一部失敗、remaining のズレ
```

## 修正後のフロー

```
タップ1 → UIは即時反映 → キューにエンキュー → サーバー呼び出しA開始
タップ2 → UIは即時反映 → キューにエンキュー → Aの完了を待機
タップ3 → UIは即時反映 → キューにエンキュー → Bの完了を待機
  → A完了 → サーバー呼び出しB開始
  → B完了 → サーバー呼び出しC開始
  → C完了 → キュー空
```

## 設計

### 変更対象ファイル
- `lib/shared/services/reaction_sync_service.dart`
- `lib/features/home/presentation/widgets/post_card.dart`

### 変更内容

#### 1. `_ReactionQueue` クラスの追加（`reaction_sync_service.dart` 内 private クラス）

```dart
class _ReactionQueue {
  final Queue<Future<void> Function()> _queue = Queue();
  bool _isProcessing = false;

  void enqueue(Future<void> Function() task) {
    _queue.add(task);
    _processNext();
  }

  Future<void> _processNext() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;
    while (_queue.isNotEmpty) {
      final task = _queue.removeFirst();
      await task();
    }
    _isProcessing = false;
  }
}
```

#### 2. ユーザー単位のキュー共有（`ReactionSyncService`）

```dart
class ReactionSyncService {
  static final Map<String, _ReactionQueue> _queues = {};

  static void enqueue(String? userId, Future<void> Function() task) {
    final key = (userId == null || userId.isEmpty) ? 'anonymous' : userId;
    final queue = _queues.putIfAbsent(key, () => _ReactionQueue());
    queue.enqueue(task);
  }
}
```

#### 3. `_showReactionOverlay` 内の `onReactionTap` コールバック修正

変更前（post_card.dart:299-300）:
```dart
_addReaction(reactionType);
unawaited(_sendReactionToServer(reactionType));
```

変更後:
```dart
_addReaction(reactionType);
ReactionSyncService.enqueue(
  currentUserId,
  () => _sendReactionToServer(reactionType),
);
```

### 変更しない箇所
- `_addReaction()` のUI即時反映ロジック: そのまま
- `_sendReactionToServer()` の内容: そのまま
- `RecentReactionsService.addReaction()`: そのまま（UIフィードバック用なので即時でOK）
- `ReactionLimitService.incrementReactionCount()`: そのまま（ローカルカウントなので即時）
- `_ReactionOverlayDialog` のUI/残数表示: そのまま
- Cloud Functions側: 変更不要

### エラーハンドリング
- キュー内の個別アイテムが失敗しても、次のアイテムの処理は続行する
- 失敗時のUIロールバックは現状も行っていないため変更なし（次回バー表示時にサーバー同期で補正）
- キュー内にタスクが残っている状態でダイアログが閉じられても、キューは処理を続行する（バックグラウンドで完了）

### スコープ
- キューは **ユーザー単位でグローバル共有**（`ReactionSyncService`）
- 投稿A/B間の同時連打でも **直列化が保証**される
- ダイアログが閉じてもキュー処理は継続（ユーザーセッション内）

## 影響範囲
- `post_card.dart` のみ
- Cloud Functions 変更なし
- Firestoreルール 変更なし
- 他画面への影響なし

## テスト観点
1. スタンプを素早く5回連打した場合、UIは即座に5回反映される
2. サーバーへの送信が直列化され、5回すべてが正しく記録される
3. Epicスタンプの remaining が正確にデクリメントされる
4. スタンプバーを閉じた後もバックグラウンドで残りの送信が完了する
5. 通常速度（1秒に1回程度）のタップでは体感に変化がない
