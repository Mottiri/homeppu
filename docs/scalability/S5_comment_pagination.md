# S5: コメントページネーション + AI遅延時間修正

**作成日**: 2026-03-12
**優先度**: P1
**ステータス**: 設計書改訂v4・R6指摘反映済み・再レビュー待ち
**次のアクション担当者**: レビュワー → Codexレビュー

---

## 1. 現状分析

### 1.1 問題A: コメント全件リアルタイム監視

`lib/features/post/presentation/screens/post_detail_screen.dart:76-80`:

```dart
_commentsStream = FirebaseFirestore.instance
    .collection('comments')
    .where('postId', isEqualTo: widget.postId)
    .orderBy('createdAt', descending: false)
    .snapshots();
```

**問題点:**
- `limit()` なしの `snapshots()` で、投稿に紐づく全コメントをリアルタイム監視
- コメントが増えるほど、スナップショットリスナーが受信するドキュメント数が線形に増加
- Firestoreの課金上も、スナップショット更新のたびに全ドキュメント分の読み取りが発生

### 1.2 問題B: AI遅延時間が短すぎる

`functions/src/triggers/posts.ts:171-172`:

```typescript
const delays = Array.from(
  { length: selectedPersonas.length },
  (_, i) => (i + 1) * 2 + Math.floor(Math.random() * 2)
).sort((a, b) => a - b);
```

**現状の遅延**: ペルソナインデックスに基づく2〜11分
- ペルソナ0: 2〜3分
- ペルソナ1: 4〜5分
- ペルソナ2: 6〜7分
- ペルソナ3: 8〜9分
- ペルソナ4: 10〜11分

**問題点**: 投稿直後に2〜11分で一気にコメントが並ぶのは不自然。BOTと疑われるリスクがある。

**理想**: 1分〜12時間のランダム遅延で、人間がたまたまその投稿を見てコメントしたかのような演出。

### 1.3 問題C: 未使用の遅延表示コード（残骸）

以下のコードは `scheduledAt` をクライアント側で制御する仕組みだが、AIコメント作成時に `scheduledAt` を設定するコードがどこにもなく、**完全に未使用**:

| 箇所 | ファイル | 行 | 内容 | 状態 |
|------|---------|-----|------|------|
| scheduledAt フィールド | `comment_model.dart` | 13 | `final DateTime? scheduledAt` | **未使用**（常にnull） |
| isVisibleNow | `comment_model.dart` | 68-72 | `scheduledAt == null → true` | **常にtrue** |
| 30秒タイマー | `post_detail_screen.dart` | 82-85 | `Timer.periodic(30秒) → setState` | **無意味**（isVisibleNowが常にtrue） |
| isVisibleNowフィルタ | `post_detail_screen.dart` | 418 | `.where((c) => c.isVisibleNow)` | **フィルタされるコメントがない** |
| scheduledAtチェック | `notifications.ts` | 188-195 | 未来コメントの通知スキップ | **到達しないコード** |

### 1.4 コスト影響

| 状況 | 変更前 | 変更後 | 削減率 |
|------|--------|--------|--------|
| 初回読み取り（100コメントの投稿） | 100 reads | 20 reads | 80% |
| リアルタイム更新（1コメント追加時） | 1 read（差分のみ課金） | 0 reads（リアルタイム監視廃止） | 100% |
| プルリフレッシュ | - | 20 reads | 追加コスト |
| 過去コメント無限スクロール1回 | - | 20 reads | 追加コスト |
| AI遅延変更（1分〜12時間） | 変化なし | 変化なし | - |

リアルタイム監視の廃止で継続的な読み取りコストがゼロに。なお、Firestoreのリスナー課金は差分ドキュメント単位（追加・更新・除外されたドキュメントのみ）であり、初回以降は変更分のみ課金される。`snapshots()` 廃止の主な理由はコストではなく、UX（スクロールジャンプ、窓の脱落）と設計の複雑性削減。AI遅延時間の変更はCloud Tasksの遅延パラメータのみでFirestore読み書き回数に影響なし。

### 1.5 関連するコードの依存関係

| 箇所 | ファイル | 行 | 内容 |
|------|---------|-----|------|
| コメント投稿 | `post_detail_screen.dart` | 95-151 | `_sendComment()` - Cloud Functions経由でコメント作成 |
| コメント表示 | `post_detail_screen.dart` | 400-663 | `StreamBuilder<QuerySnapshot>` でリスト描画 |
| チュートリアル | `post_detail_screen.dart` | 462-589 | コメントリスト内のチュートリアルターゲット検出・自動スクロール |
| お礼機能 | `post_detail_screen.dart` | 886-941+ | `_CommentTile` - 投稿主のお礼（thanks）付与UI |
| AI遅延計算 | `triggers/posts.ts` | 171-172 | コメント用Cloud Tasksの遅延時間 |
| AI遅延計算 | `triggers/posts.ts` | 257-259 | リアクション用Cloud Tasksの遅延時間 |

---

## 2. 対策A: get()ベースページネーション + 楽観UI

### 2.1 基本方針

**「全コメントを `get()` で取得 + 自分のコメントは楽観UIで即表示 + プルリフレッシュで最新化」**

リアルタイム監視（`snapshots()`）を完全に廃止し、TL（ホームフィード）と同じ `get()` ベースのページネーションに統一する。

**方針転換の経緯**:
- 初期設計: リアルタイム監視 + ページネーションのハイブリッド方式
- レビューで以下の問題が判明:
  - リアルタイム窓の移動でコメントが脱落する
  - 新着コメントの先頭挿入で閲覧位置がジャンプする
- ほめっぷのAIコメントは1分〜12時間かけてバラバラに到着する設計であり、リアルタイム性の要件が低い
- 大手SNS（YouTube, TikTok）もコメントはリアルタイム更新せずプルリフレッシュ方式
- `get()` 方式に統一することで上記問題を根本解決

### 2.2 表示順の変更: 降順（新しいコメントが上）

**変更前**: 古い順（上が古い、下が新しい）
**変更後**: 新しい順（上が新しい、下が古い）

**理由**:
- SNSのコメント欄として自然な表示順（Instagram/X と同様）
- ほめっぷのコメントは「会話」よりも「個別の応援メッセージ」に近いため、最新が先に見える方が適切
- 無限スクロールが下方向（過去を読む）になり、TLと同じ操作感になる

### 2.3 パラメータ設計

| パラメータ | 値 | 根拠 |
|-----------|-----|------|
| 初回取得件数 | 20件 | 画面に一度に表示される件数 + バッファ。`AppConstants.commentsPerPage` を20に更新して使用 |
| 過去コメント取得単位 | 20件 | 同上。`AppConstants.commentsPerPage` を使用 |
| 初回表示 | 最新20件のみ | `get()` で取得 |

### 2.4 アーキテクチャ

```
[投稿詳細画面] ※表示順: 新しい↑ 古い↓

  ├── 初回ロード: get() limit(20) orderBy(createdAt, desc)
  │     → 最新20件を取得して表示
  │
  ├── 自分のコメント投稿: 楽観UI
  │     → Cloud Functions呼び出し後、即座にローカルリストの先頭に挿入
  │     → サーバー応答を待たずに画面に表示
  │
  ├── 他ユーザーのコメント / AIコメント: プルリフレッシュ
  │     → RefreshIndicator で引っ張り更新
  │     → リストをリセットして最新20件を再取得
  │     → AIコメントは1分〜12時間後に到着するため、プルリフレッシュで自然に拾える
  │
  └── 過去コメント: 無限スクロール
        → 下方向スクロール時に自動で get() 取得
        → startAfterDocument でカーソルページネーション
```

### 2.5 初回ロード

`StreamBuilder` を廃止し、`initState` で `get()` による初回取得を行う。

```dart
List<CommentModel> _comments = [];
bool _isLoading = true;
bool _isLoadingOlder = false;
bool _hasMoreComments = true;
DocumentSnapshot? _lastDocument;

@override
void initState() {
  super.initState();
  _loadComments();
}

Future<void> _loadComments() async {
  final snapshot = await FirebaseFirestore.instance
      .collection('comments')
      .where('postId', isEqualTo: widget.postId)
      .orderBy('createdAt', descending: true)
      .limit(AppConstants.commentsPerPage)
      .get();

  final comments = snapshot.docs
      .map((doc) => CommentModel.fromFirestore(doc))
      .toList();

  setState(() {
    _comments = comments;
    _hasMoreComments = snapshot.docs.length == AppConstants.commentsPerPage;
    if (snapshot.docs.isNotEmpty) {
      _lastDocument = snapshot.docs.last;
    }
    _isLoading = false;
  });
}
```

### 2.6 自分のコメント投稿: 楽観UI

コメント投稿後、サーバー応答を待たずにローカルリストの先頭に挿入する。

```dart
Future<void> _sendComment() async {
  if (_isSending || _commentController.text.trim().isEmpty) return;
  setState(() => _isSending = true);

  final text = _commentController.text.trim();
  // 注意: 入力欄はまだクリアしない（失敗時に復元するため）

  // クライアント側で一意IDを生成（楽観コメントの照合に使用）
  final clientRequestId = const Uuid().v4();

  // 楽観的にリストの先頭に追加（新しい順なので先頭 = 最新）
  final optimisticComment = CommentModel(
    id: 'optimistic_$clientRequestId',
    postId: widget.postId,
    userId: currentUser.uid,
    userDisplayName: currentUser.displayName,
    userAvatarIndex: currentUser.avatarIndex,
    isAI: false,
    content: text,
    createdAt: DateTime.now(),
    thanksLikedByPostOwner: false,
  );

  setState(() {
    _comments.insert(0, optimisticComment);
  });

  try {
    // サーバーからcommentIdを受け取り、楽観コメントを正式データに置換
    // clientRequestIdをcallableに渡し、Firestoreに保存させる
    final commentId = await _sendCommentToServer(text, clientRequestId: clientRequestId);
    setState(() {
      final idx = _comments.indexWhere((c) => c.id == optimisticComment.id);
      if (idx >= 0) {
        _comments[idx] = optimisticComment.copyWith(id: commentId);
      }
      _commentController.clear(); // 成功時のみ入力欄をクリア
    });
  } catch (e) {
    // 失敗時は楽観コメントを除去し、入力内容を復元
    setState(() {
      _comments.removeWhere((c) => c.id == optimisticComment.id);
      _commentController.text = text; // 入力内容を復元
    });
    // エラー表示
  } finally {
    setState(() => _isSending = false);
  }
}
```

### 2.6.1 楽観UIとプルリフレッシュの競合対策

コメント送信中（`_isSending == true`）にプルリフレッシュが実行されると、`_comments` が全置換されて楽観コメントが消失する。これを防ぐため、refresh時に送信中の楽観コメントをmergeする。

```dart
Future<void> _refreshComments() async {
  final snapshot = await FirebaseFirestore.instance
      .collection('comments')
      .where('postId', isEqualTo: widget.postId)
      .orderBy('createdAt', descending: true)
      .limit(AppConstants.commentsPerPage)
      .get();

  final serverComments = snapshot.docs
      .map((doc) => CommentModel.fromFirestore(doc))
      .toList();

  setState(() {
    // 送信中の楽観コメントを保持してmerge（重複排除付き）
    final pendingOptimistic = _isSending
        ? _comments.where((c) => c.id.startsWith('optimistic_')).toList()
        : <CommentModel>[];

    // callableはFirestore書き込み完了後にcommentIdを返すため、
    // 応答待ち中にrefreshするとサーバー側に実コメントが既に存在する場合がある。
    // clientRequestIdでサーバーコメントと照合し、重複を除去。
    // ※楽観コメントのidは 'optimistic_<clientRequestId>' 形式
    // ※サーバーコメントはFirestore上の clientRequestId フィールドで照合
    final dedupedOptimistic = pendingOptimistic.where((opt) {
      final reqId = opt.id.replaceFirst('optimistic_', '');
      return !serverComments.any((s) => s.clientRequestId == reqId);
    }).toList();

    _comments = [...dedupedOptimistic, ...serverComments];
    _hasMoreComments = snapshot.docs.length == AppConstants.commentsPerPage;
    _lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
  });
}
```

### 2.7 プルリフレッシュ

`RefreshIndicator` で引っ張り更新を実装。TLと同じパターン。

**注意**: コメントが少ない投稿ではコンテンツ高が不足してプルリフレッシュが発火しない場合がある。`CustomScrollView` に `physics: const AlwaysScrollableScrollPhysics()` を指定して、コンテンツが少なくてもスクロール可能にする。

**チュートリアルとの共存**: 現行コード（`post_detail_screen.dart:377`）ではチュートリアルの `commentLongPress` ステップ中に `NeverScrollableScrollPhysics` を使ってスクロールを禁止し、ターゲットコメントを固定表示している。この条件分岐を維持し、チュートリアル中は `NeverScrollableScrollPhysics`、それ以外は `AlwaysScrollableScrollPhysics` を適用する。

```dart
RefreshIndicator(
  onRefresh: _refreshComments, // §2.6.1 の楽観UIマージ版を使用
  child: CustomScrollView(
    controller: _scrollController,
    // チュートリアル中はスクロール禁止（ターゲット固定）、通常時はプルリフレッシュ対応
    physics: isTutorialCommentLongPress
        ? const NeverScrollableScrollPhysics()
        : const AlwaysScrollableScrollPhysics(),
    slivers: [
      // ... 投稿本体 + コメントリスト
    ],
  ),
)
```

`_refreshComments` の実装は §2.6.1 を参照（楽観コメントのmergeロジック込み）。

### 2.8 過去コメントの取得（無限スクロール）

表示順が降順（新しい↑ 古い↓）のため、下方向スクロール = 過去コメントの読み込み。TLと同じ操作方向。

**カーソルの安定性**: `startAfterDocument(_lastDocument!)` は Firestore が内部的にドキュメントIDをtie-breakerとして使用するため、同一 `createdAt` タイムスタンプのコメントが複数存在してもページ境界での重複・欠落は発生しない。`startAfter(value)` ではなく `startAfterDocument(documentSnapshot)` を使うことが重要。

```dart
void _onScroll() {
  if (_scrollController.position.pixels >=
      _scrollController.position.maxScrollExtent - 300) {
    _loadOlderComments();
  }
}

Future<void> _loadOlderComments() async {
  if (_isLoadingOlder || !_hasMoreComments || _lastDocument == null) return;
  setState(() => _isLoadingOlder = true);

  final snapshot = await FirebaseFirestore.instance
      .collection('comments')
      .where('postId', isEqualTo: widget.postId)
      .orderBy('createdAt', descending: true)
      .startAfterDocument(_lastDocument!)
      .limit(AppConstants.commentsPerPage)
      .get();

  final newComments = snapshot.docs
      .map((doc) => CommentModel.fromFirestore(doc))
      .toList();

  setState(() {
    _comments.addAll(newComments);
    _hasMoreComments = snapshot.docs.length == AppConstants.commentsPerPage;
    if (snapshot.docs.isNotEmpty) {
      _lastDocument = snapshot.docs.last;
    }
    _isLoadingOlder = false;
  });
}
```

リスト下端にローディングインジケーターを表示：

```dart
if (_isLoadingOlder)
  SliverToBoxAdapter(
    child: Center(
      child: Padding(
        padding: EdgeInsets.all(8),
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  ),
```

### 2.9 追加インデックス

`firebase/firestore.indexes.json` に追加:

```json
{
  "collectionGroup": "comments",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "postId", "order": "ASCENDING" },
    { "fieldPath": "createdAt", "order": "DESCENDING" }
  ]
}
```

---

## 3. 対策B: AI遅延時間の修正（1分〜12時間）

### 3.1 変更対象

AIコメントのCloud Tasks遅延時間を変更する。

**変更箇所**: `functions/src/triggers/posts.ts:171-172`

### 3.2 変更内容

**変更前**（2〜11分、ペルソナインデックスに基づく連番）:
```typescript
const delays = Array.from(
  { length: selectedPersonas.length },
  (_, i) => (i + 1) * 2 + Math.floor(Math.random() * 2)
).sort((a, b) => a - b);
// → [2, 4, 6, 8, 10] 分（+0or1分のランダム）
```

**変更後**（1分〜12時間、deterministic random、1件目は最大30分保証）:
```typescript
const MIN_DELAY_MINUTES = 1;
const MAX_DELAY_MINUTES = 720; // 12時間
const FIRST_COMMENT_MAX_MINUTES = 30; // 1件目の上限（即時フィードバック保証）

const delays = selectedPersonas.map((persona, i) => {
  const hash = createHash("sha256")
    .update(`${postId}-comment-delay-${persona.id}`)
    .digest();
  return MIN_DELAY_MINUTES +
    (hash.readUInt16BE(0) % (MAX_DELAY_MINUTES - MIN_DELAY_MINUTES + 1));
}).sort((a, b) => a - b);

// 1件目だけは最大30分に制限（投稿直後に長時間無反応になるのを防ぐ）
delays[0] = Math.min(delays[0], FIRST_COMMENT_MAX_MINUTES);
// → 例: [12, 47, 182, 391, 653] 分（1件目: 1〜30分、2件目以降: 1〜720分）
```

**ポイント**:
- `postId + personaId` ベースのハッシュで**deterministic**（S1冪等性対策と整合）
- `Math.random()` は使用しない（リトライ時に異なる遅延になるため）
- 1件目は最大30分以内に到着を保証（`FIRST_COMMENT_MAX_MINUTES`）。投稿直後に長時間無反応になるのを防ぐ
- 2件目以降は1分〜12時間かけてバラバラに到着
- sort済みなので時系列順に到着する

### 3.3 AIリアクションの遅延（変更なし）

リアクションの遅延は現状のまま維持する:

```typescript
// functions/src/triggers/posts.ts:257-259（既存・変更なし）
const delayHash = createHash("sha256")
  .update(`${postId}-reaction-delay-${persona.id}`).digest();
const delaySeconds = (delayHash.readUInt16BE(0) % 3600) + 10;
// → 10秒〜約60分（既にdeterministic）
```

**理由**: リアクション（いいね等）は即座に付くのが自然。コメントと違いBOT感が出にくい。

### 3.4 Cloud Tasksの制約確認

| 制約 | 値 | S5で問題になるか |
|------|-----|----------------|
| 最大スケジュール遅延 | 30日 | **問題なし**（最大12時間） |
| タスク実行回数課金 | 1タスク1実行 | **変化なし** |
| タスク保持期間 | 30日 | **問題なし** |

---

## 4. 対策C: 残骸コードの削除

### 4.1 削除対象

| # | ファイル | 削除内容 |
|---|---------|---------|
| C1 | `lib/shared/models/comment_model.dart` | `scheduledAt` フィールド、コンストラクタ引数、fromFirestore/toMap、copyWith から削除 |
| C2 | `lib/shared/models/comment_model.dart` | `isVisibleNow` getter を削除 |
| C3 | `lib/features/post/presentation/screens/post_detail_screen.dart` | `_refreshTimer`（30秒タイマー）を削除 |
| C4 | `lib/features/post/presentation/screens/post_detail_screen.dart` | `.where((c) => c.isVisibleNow)` フィルタを削除 |
| C5 | `functions/src/triggers/notifications.ts` | `scheduledAt` チェック（188-195行）を削除 |
| C6 | `functions/src/callable/comments.ts` | コメント作成時の `isVisibleNow: true`（411行）を削除。このフィールドはクライアント側で使用されておらず、scheduledAt系の残骸 |

### 4.2 削除の安全性

- `scheduledAt` は AIコメント作成時（`ai-generation.ts`）で設定されていないため、常に `null`
- `isVisibleNow` は `scheduledAt == null → true` なので、フィルタとして機能していない
- 30秒タイマーは `setState` を呼ぶだけだが、`isVisibleNow` が常にtrueなので画面に変化を与えない
- `notifications.ts` の `scheduledAt` チェックは到達しないコード

---

## 5. 既存フローへの影響

| フロー | 影響 | 理由 |
|--------|------|------|
| コメント投稿 → 即表示 | **なし** | 楽観UIにより即座に画面先頭に表示 |
| AIコメント到着 | **変更あり** | 2-11分後 → 1分〜12時間後に変更。ユーザーはプルリフレッシュまたは画面再訪問で確認 |
| AIリアクション | **なし** | 遅延時間変更なし |
| チュートリアル | **軽微** | チュートリアル対象は `comments.firstWhere((c) => c.userId != post.userId)` で選定される。降順表示により、リスト先頭=最新コメントとなるため、ターゲットは**最新の non-owner コメント（一番上に表示されるコメント）**に変わる。新規ユーザーの初回投稿ではコメント数が少なく20件以内に収まるため、ターゲットが取得範囲外になるリスクはない。選定ロジック自体の変更は不要 |
| お礼（Thanks）機能 | **なし** | 楽観UI (`_optimisticThanked`) で即時反映。サーバー側の状態はプルリフレッシュで同期 |
| 表示順 | **変更** | 古い順 → 新しい順に変更 |
| 他ユーザーのコメント | **変更** | リアルタイム自動表示 → プルリフレッシュに変更 |

### 5.1 仕様として許容する一貫性低下

以下の挙動は `get()` 方式の仕様として許容する（TLと同じ設計判断）:

- **他端末でのお礼付与**: プルリフレッシュまで画面に反映されない
- **コメントの非表示化（通報対応等）**: プルリフレッシュまで画面に反映されない
- **他ユーザー/AIの新規コメント**: プルリフレッシュまで画面に反映されない

いずれも「画面を開き直す」または「プルリフレッシュ」で最新状態に同期される。

---

## 6. 変更ファイル一覧

| # | ファイル | 変更内容 | 影響度 |
|---|---------|---------|--------|
| 1 | `lib/features/post/presentation/screens/post_detail_screen.dart` | StreamBuilder廃止 → get()ベース、降順表示、楽観UI、プルリフレッシュ（AlwaysScrollableScrollPhysics）、無限スクロール、30秒タイマー削除、isVisibleNowフィルタ削除 | **大** |
| 2 | `lib/shared/models/comment_model.dart` | `scheduledAt` フィールド・`isVisibleNow` getter 削除、`clientRequestId` フィールド追加 | **中** |
| 3 | `lib/core/constants/app_constants.dart` | `commentsPerPage` を 10 → 20 に変更 | **小** |
| 4 | `firebase/firestore.indexes.json` | `postId ASC, createdAt DESC` インデックス追加 | **小** |
| 5 | `functions/src/triggers/posts.ts` | AIコメント遅延を2-11分 → 1分〜12時間に変更（deterministic hash） | **中** |
| 6 | `functions/src/triggers/notifications.ts` | `scheduledAt` チェック（188-195行）削除 | **小** |
| 7 | `functions/src/callable/comments.ts` | `isVisibleNow: true` 削除、`clientRequestId` フィールドをFirestoreに保存・レスポンスに含める | **小** |

---

## 7. リスクと注意点

| # | リスク | 影響度 | 対策 |
|---|--------|--------|------|
| R1 | インデックス未作成でデプロイ | **高** | `firebase deploy --only firestore:indexes` を先行実行。作成完了確認後にアプリリリース |
| R2 | 楽観UIとプルリフレッシュの競合 | **中** | 送信中の楽観コメントをrefresh時にmerge（§2.6.1）。送信成功時にサーバーIDで置換 |
| R3 | プルリフレッシュが短いリストで発火しない | **中** | `AlwaysScrollableScrollPhysics` を明示指定 |
| R4 | 同一タイムスタンプでページ境界不安定 | **低** | `startAfterDocument` がドキュメントIDをtie-breakerに使用するため問題なし（§2.8に明記） |
| R5 | 降順表示でチュートリアル対象が変わる | **低** | `firstWhere` が最新 non-owner を選ぶようになる（一番上のコメント）。選定ロジック変更不要。スクロール方向を調整 |
| R6 | AIコメント遅延変更で既存テストの期待値不一致 | **低** | 遅延値のテストは定数ベースで検証 |

### ロールバック

- クライアント: アプリ側のみの変更。Firestoreの構造変更なし。旧バージョンのアプリがそのまま動作する
- バックエンド: Cloud Functionsの遅延変更は即座にロールバック可能。インデックス追加は既存クエリに影響しない
- 残骸削除: `scheduledAt` はFirestore上のフィールドとして残るが、書き込み側（ai-generation.ts）がそもそも設定していないため影響なし

---

## 8. テスト観点

### クライアント側

| # | テスト項目 |
|---|-----------|
| T1 | コメント0件の投稿で空状態が正しく表示される |
| T2 | コメント20件以下の投稿で下スクロールしても追加読み込みが発生しない |
| T3 | コメント21件以上の投稿で下スクロール時に過去コメントが自動で読み込まれる |
| T4 | 過去コメント読み込み中にローディングインジケーターがリスト下端に表示される |
| T5 | 自分のコメント投稿後、即座に画面先頭に表示される（楽観UI） |
| T6 | コメント投稿失敗時、楽観コメントが除去される |
| T7 | プルリフレッシュで新規コメント（AI/他ユーザー）が表示される |
| T8 | プルリフレッシュでお礼状態が最新化される |
| T9 | コメント0件でもプルリフレッシュが発火する（AlwaysScrollableScrollPhysics） |
| T10 | チュートリアルが正常に動作する |
| T11 | 過去コメントへの「お礼」が正常に動作する（楽観UI） |
| T12 | コメント表示順が新しい順（降順）になっている |
| T13 | 初回表示時に過去コメントの自動読み込みが発生しない |
| T14 | コメント送信中にプルリフレッシュしても楽観コメントが消えない |
| T15 | コメント送信成功後、楽観IDがサーバーIDに置換される |

### バックエンド側

| # | テスト項目 |
|---|-----------|
| T16 | AIコメントの遅延が1分〜720分の範囲内である |
| T17 | 同一postId+personaIdで遅延値が同じ（deterministic） |
| T18 | AIリアクションの遅延は変更なし（10秒〜60分） |
| T19 | scheduledAtチェック削除後も通知が正常に送信される |

---

## 9. レビュー履歴

| 日付 | レビュワー | 結果 | 対応 |
|------|-----------|------|------|
| 2026-03-12 | Codex R1 | needs_revision (major 3件) | 脱落コメント移管、スクロールトリガー下端化、チュートリアル影響修正 |
| 2026-03-13 | Codex R2 | needs_revision (major 3件) | チュートリアルFB不要、一貫性低下を仕様明記、リアルタイム監視廃止 |
| 2026-03-13 | ユーザー | 方針承認 | get()方式 + 楽観UI + プルリフレッシュに全面改訂（v3） |
| 2026-03-13 | Codex R3 | needs_revision (high 2 + medium 1) | AI遅延前提修正、isVisibleNow問題解消（残骸削除）、AlwaysScrollableScrollPhysics追加 |
| 2026-03-13 | ユーザー | スコープ拡大承認 | AI遅延時間修正（1分〜12時間）+ 残骸コード削除を追加（v4） |
| 2026-03-13 | Codex R4 | needs_revision (high 2 + medium 2) | カーソルtie-breaker明記、楽観UI+refreshの競合対策追加、遅延off-by-one修正、コスト表是正 |
| 2026-03-13 | Codex R5 | needs_revision (high 2 + medium 1) | 送信失敗時の入力復元追加、refresh時の重複排除追加、残骸削除スコープにcomments.ts追加 |
| 2026-03-13 | Codex R6 | needs_revision (high 1 + medium 1) | 重複排除をclientRequestIdベースに変更、チュートリアル影響の根拠を修正 |
| 2026-03-13 | Codex R7 | needs_revision (blocking 2) | 1件目AI遅延の上限30分保証追加、ScrollPhysicsのチュートリアル条件分岐明記 |
