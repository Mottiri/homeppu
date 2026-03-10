# 詳細設計書: 性能改善 #6 Phase 1 — Follow Feed の Chunked Query 対応

**作成日**: 2026-03-10
**起源**: docs/specs/2026-03-10_performance_optimization.md #6 Phase 1
**ステータス**: 実装完了 / ユーザー実機確認待ち
**次のアクション担当者**: ユーザー（実機確認）

---

## 背景

Firestore の `whereIn` は最大10要素の制限がある。現在 `followingIds.take(10)` で先頭10件に制限しており、**11人以上フォローすると一部の投稿が表示されない（正しさの欠陥）**。

---

## 1. 設計方針

### 3案の比較

| 案 | 概要 | メリット | デメリット |
|---|------|---------|-----------|
| **A: _ChunkedPostsList 新規作成（選定）** | Following 分岐のみ専用ウィジェットに置換 | For You タブに影響ゼロ、デグレリスク最小 | UI 描画ロジックの重複 |
| B: _PostsList を拡張 | `List<Query>` を受け取れるように変更 | ウィジェット重複なし | For You タブにもデグレリスク |
| C: Repository レイヤー抽象化 | FollowFeedRepository で管理 | 関心の分離が明確 | 大規模リファクタリング、スコープ超過 |

**選定理由**: For You タブへの影響ゼロが最優先。`_PostsList` の既存ページネーション（`startAfterDocument`ベース）を壊さない。

---

## 2. 詳細設計

### 2.1 データフロー

```
StreamBuilder<DocumentSnapshot>（ユーザードキュメント監視）
  ↓ followingIds（全件）
_ChunkedPostsList
  ↓ followingIds を10件ずつチャンクに分割
  ↓ 各チャンクで Query を構築
  ↓ Future.wait() で並列クエリ実行
  ↓ 全チャンクの結果を createdAt 降順でマージソート + 重複排除
  ↓ 表示
  ↓ ページネーション時: 各チャンクの独立カーソルで追加ロード → マージ
```

### 2.2 新規ウィジェット: `_ChunkedPostsList`

```dart
class _ChunkedPostsList extends ConsumerStatefulWidget {
  final List<String> followingIds;
  final bool isAIViewer;
  final String? currentUserId;
  final int refreshKey;
  final ValueChanged<Rect?>? onFirstPostCardRectChanged;
  final GlobalKey? tutorialOverlayAncestorKey;
}
```

State フィールド:
```dart
List<PostModel> _posts = [];
late List<List<String>> _chunks;           // 10件ずつ分割
late List<DocumentSnapshot?> _lastDocuments; // チャンクごとのカーソル
late List<bool> _chunkHasMore;              // チャンクごとの追加データ有無
bool _hasMore = true;
bool _isLoading = true;
bool _isLoadingMore = false;
int _loadGeneration = 0;              // stale request guard
```

### 2.3 主要メソッド

| メソッド | 処理 |
|---------|------|
| `_buildChunks()` | followingIds を10件ずつ分割 |
| `_loadPosts()` | チャンク構築 → 並列クエリ → マージソート → 表示。開始時に `_isLoadingMore = false` にリセット（loadMore 競合防止）。`_loadGeneration` をインクリメントし、レスポンス受信時に generation 不一致なら結果を破棄（stale request guard） |
| `_loadMorePosts()` | `_chunkHasMore[i]==true` のチャンクのみ追加ロード → マージ追加。generation 不一致時は結果を破棄 |
| `_mergePosts()` | createdAt 降順ソート + ID ベース重複排除 |

### 2.3.1 クライアント側フィルタリング

Firestore の `whereIn` と他の `where` 句の複合制約により、以下のフィルタはクエリレベルではなくクライアント側で実施:
- **circleId フィルタ**: `post.circleId == null || post.circleId!.isEmpty` のみ表示（サークル投稿を除外）
- **AIモード投稿フィルタ**: `isAIViewer` でない場合、他ユーザーの `postMode == 'ai'` の投稿を非表示

### 2.4 _TimelineTab の変更

Following 分岐で `_PostsList(query: ...)` を `_ChunkedPostsList(followingIds: ...)` に置換。

---

## 3. ページネーション戦略

- **初回ロード**: 各チャンク `limit(postsPerPage)` → 全結果マージ
- **追加ロード**: `_chunkHasMore[i]==true` のチャンクのみ `startAfterDocument(_lastDocuments[i])` で追加取得 → 既存リストにマージ追加 → 全体再ソート
- **_hasMore 判定**: `_chunkHasMore.any((h) => h)`

---

## 4. エッジケース

| ケース | 対処 |
|--------|------|
| followingIds 0件 | `_EmptyFollowingState` 表示（既存分岐で処理済み） |
| followingIds 1-10件 | チャンク1つ。従来と同等 |
| followingIds 11+件 | チャンク複数。並列クエリ + マージ |
| Load More 中にフォロー変更 | `didUpdateWidget` で検知 → フルリロード |
| 一部チャンクのクエリ失敗 | `Future.wait` 全体失敗 → エラー状態表示 |

---

## 5. Firestore コスト影響

| フォロー数 | チャンク数 | 初回読み取り数 | 従来 |
|-----------|-----------|---------------|------|
| 1-10 | 1 | 最大 20 | 同一 |
| 11-20 | 2 | 最大 40 | 20（バグで制限） |
| 21-30 | 3 | 最大 60 | 20（バグで制限） |
| 50 | 5 | 最大 100 | 20（バグで制限） |

従来は「正しくない結果を安く取得」していた状態。コスト増はバグ修正に伴う必要コスト。

---

## 6. リスクと対策

| リスク | 対策 |
|--------|------|
| UI ロジック重複 | Phase 2 で共通化。Phase 1 はコメントで「_PostsList と同一ロジック」を明記 |
| フォロー100超でクエリ爆発 | Phase 2 Fan-out on Write で根本解決。Phase 1 ではログ出力で監視 |
| チュートリアルとの互換性 | `_firstPostCardKey` 等のロジックを完全コピー |

---

## 7. 実装手順

1. `_buildChunks()` ユーティリティ追加
2. `_ChunkedPostsList` ウィジェット作成（`_PostsList` をコピーベースで作成）
3. `_loadPosts` をチャンク並列 + マージに書き換え
4. `_loadMorePosts` をチャンクカーソル管理に書き換え
5. `didUpdateWidget` に `followingIds` 変更検知を追加
6. `_TimelineTab` の Following 分岐を `_ChunkedPostsList` に置換

---

## 8. 変更対象ファイル

| ファイル | 変更内容 |
|---------|---------|
| `lib/features/home/presentation/screens/home_screen.dart` | `_ChunkedPostsList` 新規追加、`_TimelineTab` の Following 分岐変更 |

**変更ファイルは1つのみ**。

---

## 9. 次のアクション担当者

**ユーザー（実機確認）**
