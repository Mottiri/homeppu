# S4: サークル検索のサーバー側クエリ化

**作成日**: 2026-03-13
**優先度**: P1
**ステータス**: 設計書作成済み・ユーザーレビュー待ち
**次のアクション担当者**: 全体管理者 → 設計レビュー

---

## 1. 現状分析

### 1.1 問題点: 全件取得 + クライアント側フィルタリング

`lib/shared/services/circle_service.dart:193-217` の `searchCircles()`:

```dart
Future<List<CircleModel>> searchCircles(
  String query, {
  required String userId,
}) async {
  final snapshot = await _firestore
      .collection('circles')
      .where(
        Filter.or(
          Filter('aiMode', whereIn: ['mix', 'humanOnly']),
          Filter('ownerId', isEqualTo: userId),
        ),
      )
      .get();  // ← 全件取得

  final lowerQuery = query.toLowerCase();
  return snapshot.docs
      .map((doc) => CircleModel.fromFirestore(doc))
      .where((c) => !c.isDeleted)
      .where((c) => c.name.toLowerCase().contains(lowerQuery))
      .take(20)
      .toList();
}
```

**問題点:**
- サークル数が増加するほど、1回の検索で全サークルドキュメントを読み取る
- Firestoreの読み取り課金がサークル総数に比例して増加
- 全データがクライアントに転送されるため、帯域・メモリも圧迫
- `onChanged` で文字入力のたびに発火し、debounceもないため連続的に全件取得が走る

### 1.2 コスト影響（現状）

| サークル総数 | 1回の検索読み取り数 | 1文字入力ごとの読み取り |
|-------------|-------------------|----------------------|
| 100件 | 100 reads | 100 reads |
| 1,000件 | 1,000 reads | 1,000 reads |
| 10,000件 | 10,000 reads | 10,000 reads |

検索テキスト「ダイエット」と入力すると5文字 = 5回のクエリ発火。サークル1,000件なら5,000 reads。

### 1.3 関連する同種の問題: streamCircles / streamPublicCircles

`circle_service.dart:32-82` の `streamCircles()` と `streamPublicCircles()` も同様に全件をリアルタイム監視している。ただし、これらはサークル一覧画面で使用されており、現在は `getPublicCirclesPaginated()` に移行済み（ページネーション対応）。本設計では **検索機能のみ** を対象とする。

### 1.4 現在のUI動作

`circles_screen.dart:364` で `TextField.onChanged` に `_performSearch` が直接バインドされている:

```dart
TextField(
  controller: _searchController,
  onChanged: (value) => _performSearch(value),
  ...
)
```

- 文字入力のたびに即座にFirestoreクエリが発火
- debounce（入力待ち）なし
- 結果は最大20件をリスト表示

---

## 2. 設計

### 2.1 基本方針

**「トークン分割 + `array-contains` による単語一致検索 + Cloud Functions callable + cursorページネーション + debounce」**

1. **`nameTokens` 配列フィールド追加**: サークル名をN-gramトークンに分割し、`array-contains` で単語一致検索を実現
2. **Cloud Functions callable関数**: サーバー側でクエリを実行し、公開ルール・isDeleted判定をサーバーで完結
3. **cursorページネーション**: Firestoreの `startAfter` を使い、人気順（memberCount DESC）でページネーションを実現（memberCount変動時の軽微な重複・欠落は許容）
4. **クライアント側debounce**: 文字入力ごとではなく、入力停止後300msで検索を発火
5. **カテゴリフィルタ対応**: カテゴリを指定した絞り込み検索も可能に

### 2.2 なぜCloud Functionsを経由するか

Firestoreのクライアント側クエリでは以下の制約がある:

- **ORクエリ + array-containsの組み合わせ不可**: 現在の公開ルール（`aiMode in ['mix','humanOnly'] OR ownerId == userId`）と`array-contains`をクライアント側の1クエリで表現できない
- **Security Rules**: サーバー側で処理することで、クライアントに不要なデータ（非公開サークル名等）が漏洩しない

### 2.3 `nameTokens` フィールド

#### フィールド仕様

| フィールド名 | 型 | 値 | 例 |
|-------------|-----|-----|-----|
| `nameTokens` | `string[]` | サークル名のN-gramトークン配列（小文字化済み） | 下記参照 |

#### トークン生成ロジック

サークル名を1文字以上の連続部分文字列（N-gram）に分割する。

```typescript
// helpers/search-tokens.ts（新規）
export function generateNameTokens(name: string): string[] {
  const lower = name.toLowerCase().trim();
  const tokens = new Set<string>();

  // 1文字〜全文字のN-gramを生成（Unicode対応）
  const chars = Array.from(lower);
  for (let len = 1; len <= chars.length; len++) {
    for (let start = 0; start <= chars.length - len; start++) {
      tokens.add(chars.slice(start, start + len).join(""));
    }
  }

  return Array.from(tokens);
}
```

**例: 「毎日ダイエット部」の場合:**
```
入力: "毎日ダイエット部"
トークン: ["毎", "日", "ダ", ..., "毎日", "日ダ", "ダイ", ...,
           "毎日ダ", "日ダイ", ..., "毎日ダイエット部"]
```

これにより:
- 「ダイエット」で検索 → `array-contains: "ダイエット"` → ヒット ✅
- 「毎日」で検索 → `array-contains: "毎日"` → ヒット ✅
- 「毎」で検索 → `array-contains: "毎"` → ヒット ✅（1文字検索対応）

**制約・リスク分析:**
- Firestoreの配列フィールド上限は最大40,000要素（サークル名の現実的な長さでは問題なし）
- サークル名が30文字の場合、トークン数は最大 `30+29+...+1 = 465` 個
- 1文字検索は多くのサークルにヒットしうるが、`limit(20)` で1リクエストあたりの読み取りを制限しているため、コスト面での影響は限定的
- `Array.from()` によりUnicodeサロゲートペア（絵文字等）にも対応

#### 書き込み時の自動設定

**onCircleCreated / onCircleUpdated トリガーで設定**（トリガーで一元管理し漏れを防止）

**重要: 既存の `onCircleCreated` では `aiMode === "humanOnly"` の場合に早期return（AI生成スキップ）がある。`nameTokens` 付与はこの早期returnより前に配置すること。** これにより humanOnly サークルも確実に検索対象になる。

```typescript
// triggers/circles.ts - onCircleCreated に追加
// ※ 必ず aiMode === "humanOnly" の早期return（AI生成スキップ）よりも前に配置すること
import { generateNameTokens } from "../helpers/search-tokens";

const circleData = snapshot.data();
await db.collection("circles").doc(circleId).update({
  nameTokens: generateNameTokens(circleData.name || ""),
});
```

```typescript
// triggers/circles.ts - onCircleUpdated に追加
if (beforeData.name !== afterData.name) {
  // 名前が変更された場合、nameTokensも更新
  // ※再帰ループ防止: nameTokensの変更ではnameは変わらないのでスキップされる
  await db.collection("circles").doc(circleId).update({
    nameTokens: generateNameTokens(afterData.name || ""),
  });
}
```

### 2.4 Cloud Functions: `searchCircles` callable

#### インターフェース

```typescript
// リクエスト
interface SearchCirclesRequest {
  query: string;           // 検索文字列（1文字以上、100文字以下）
  category?: string;       // カテゴリフィルタ（省略時は全カテゴリ）
  joinedOnly?: boolean;    // true: 参加中サークルのみ（「参加中」タブ用、サーバー側ポストフィルタ）
  limit?: number;          // 取得件数（デフォルト20、最大50）
  cursor?: {               // cursorページネーション用（2ページ目以降）
    memberCount: number;   // 前回最後の公開サークルのmemberCount
    id: string;            // 前回最後の公開サークルのID
  };
}

// レスポンス
interface CircleData {
  id: string;
  name: string;
  description: string;
  category: string;
  ownerId: string;
  aiMode: string;
  isPublic: boolean;
  memberCount: number;
  postCount: number;
  iconImageUrl: string | null;
  coverImageUrl: string | null;
  goal: string;
  recentActivity: string | null;     // ISO 8601（活動チップ表示用）
  lastHumanPostAt: string | null;    // ISO 8601（管理者用人間活動チップ表示用）
  createdAt: string | null;          // ISO 8601（欠損時はnull — データ補完しない）
}

interface SearchCirclesResponse {
  circles: CircleData[];             // 公開サークル検索結果（cursorページネーション対象）
  privateOwnerCircles: CircleData[]; // オーナーのaiOnlyサークル（初回のみ、2ページ目以降は空配列）
  hasMore: boolean;                  // 公開サークルの次ページが存在するか
  nextCursor?: {                     // cursorページネーション用（hasMore=trueの場合のみ）
    memberCount: number;             // 最後の公開サークルのmemberCount
    id: string;                      // 最後の公開サークルのID
  };
}
```

#### 実装

```typescript
// functions/src/callable/circles.ts に追加

export const searchCircles = onCall(
  {
    region: LOCATION,
    enforceAppCheck: true,
    timeoutSeconds: 10,
    memory: "256MiB",
  },
  async (request) => {
    const userId = requireAuth(request, AUTH_ERRORS.UNAUTHENTICATED_ALT);

    const { query, category, limit: requestLimit, cursor } = request.data;

    // バリデーション
    if (!query || typeof query !== "string" || query.trim().length < 2) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
    }
    if (query.length > 100) {
      throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
    }
    // cursorバリデーション（指定時は memberCount と id が必須）
    if (cursor) {
      if (typeof cursor.memberCount !== "number" || typeof cursor.id !== "string") {
        throw new HttpsError("invalid-argument", VALIDATION_ERRORS.INVALID_ARGUMENT);
      }
    }

    const searchLimit = Math.min(Math.max(requestLimit || 20, 1), 50);
    const searchToken = query.toLowerCase().trim();

    // ===== 戦略 =====
    //
    // 2系統のクエリを独立して実行し、結果をマージする:
    //
    // 1. オーナーサークル（初回のみ、ページネーション不要）
    //    - 自分が作成した非公開サークルは通常ごく少数（〜数十件）
    //    - 初回検索時に取得し、limit内に含めてマージ
    //    - 2ページ目以降は cursor が指定されるためスキップ
    //
    // 2. 公開サークル（cursorページネーション対応）
    //    - array-contains + memberCount DESC + documentId ASC + startAfter でページング
    //    - cursor はソートキー（memberCount, id）を含む境界値
    //    - ※ memberCount は参加・脱退で変動するため、ページ間で軽微な重複・欠落の可能性あり
    //      （人気順ソートを維持するためのトレードオフ。実用上は問題ないレベル）
    //
    // ===== レスポンス構造 =====
    // circles: 公開サークル（cursorページネーション対象）
    // privateOwnerCircles: オーナーのaiOnlyサークル（初回のみ、2ページ目以降は空配列）
    // → 2つを分離することで、cursor/hasMore は公開サークルのみに適用され、
    //   ownerCount による publicLimit 枯渇問題を根本的に回避する。

    // --- レスポンス整形ヘルパー ---
    const formatCircle = (data: FirebaseFirestore.DocumentData, id: string) => ({
      id,
      name: data.name || "",
      description: data.description || "",
      category: data.category || "その他",
      ownerId: data.ownerId || "",
      aiMode: data.aiMode || "mix",
      isPublic: data.isPublic ?? true,
      memberCount: data.memberCount || 0,
      postCount: data.postCount || 0,
      iconImageUrl: data.iconImageUrl || null,
      coverImageUrl: data.coverImageUrl || null,
      goal: data.goal || "",
      recentActivity: data.recentActivity?.toDate?.()?.toISOString() || null,
      lastHumanPostAt: data.lastHumanPostAt?.toDate?.()?.toISOString() || null,
      createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
    });

    // --- クエリ1: オーナーのaiOnlyサークル（初回のみ） ---
    // cursor がない = 初回検索。別配列で返すためlimit枠を消費しない。
    const privateOwnerCircles: ReturnType<typeof formatCircle>[] = [];

    if (!cursor) {
      let ownerQuery: FirebaseFirestore.Query = db.collection("circles")
        .where("isDeleted", "==", false)
        .where("ownerId", "==", userId)
        .where("nameTokens", "array-contains", searchToken);

      // カテゴリフィルタ（ownerQueryにも適用）
      if (category && category !== "全て") {
        ownerQuery = ownerQuery.where("category", "==", category);
      }

      ownerQuery = ownerQuery.limit(50);

      const ownerSnapshot = await ownerQuery.get();

      for (const doc of ownerSnapshot.docs) {
        const data = doc.data();
        // 公開サークル（mix/humanOnly）はクエリ2で取得するため、aiOnlyのみここで追加
        if (data.aiMode !== "mix" && data.aiMode !== "humanOnly") {
          privateOwnerCircles.push(formatCircle(data, doc.id));
        }
      }
    }

    // --- クエリ2: 公開サークル検索（cursorページネーション対応） ---
    // circles 配列は常に searchLimit 以下を保証
    let publicQuery: FirebaseFirestore.Query = db.collection("circles")
      .where("isDeleted", "==", false)
      .where("aiMode", "in", ["mix", "humanOnly"])
      .where("nameTokens", "array-contains", searchToken)
      .orderBy("memberCount", "desc")
      .orderBy(FieldPath.documentId())  // 安定ソートのため documentId を副ソートキーに追加
      .limit(searchLimit + 1);  // hasMore判定用に+1件取得

    // カテゴリフィルタ（Firestoreクエリレベルで適用）
    if (category && category !== "全て") {
      publicQuery = publicQuery.where("category", "==", category);
    }

    // cursorページネーション（2ページ目以降）
    // cursor にはソートキー（memberCount, id）が含まれるため、ドキュメント再取得不要。
    // ※ memberCount は変動しうるが、検索セッション中の変動確率は低く実用上問題ない。
    if (cursor) {
      publicQuery = publicQuery.startAfter(cursor.memberCount, cursor.id);
    }

    const publicSnapshot = await publicQuery.get();

    // hasMore判定（公開クエリの取得件数が searchLimit+1 を超えるか）
    const hasMore = publicSnapshot.docs.length > searchLimit;

    // 公開サークルを整形（+1件目を除外）
    const publicDocs = publicSnapshot.docs.slice(0, searchLimit);
    const circles = publicDocs.map((doc) => formatCircle(doc.data(), doc.id));

    // nextCursor: 公開サークルの最後のソートキーを返す
    let nextCursor: { memberCount: number; id: string } | undefined;
    if (hasMore && publicDocs.length > 0) {
      const lastDoc = publicDocs[publicDocs.length - 1];
      nextCursor = {
        memberCount: lastDoc.data().memberCount || 0,
        id: lastDoc.id,
      };
    }

    return { circles, privateOwnerCircles, hasMore, nextCursor };
  }
);
```

### 2.5 Firestoreインデックス

以下のコンポジットインデックスを `firebase/firestore.indexes.json` に追加:

```json
{
  "collectionGroup": "circles",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "isDeleted", "order": "ASCENDING" },
    { "fieldPath": "aiMode", "order": "ASCENDING" },
    { "fieldPath": "nameTokens", "arrayConfig": "CONTAINS" },
    { "fieldPath": "memberCount", "order": "DESCENDING" },
    { "fieldPath": "__name__", "order": "ASCENDING" }
  ]
},
{
  "collectionGroup": "circles",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "isDeleted", "order": "ASCENDING" },
    { "fieldPath": "ownerId", "order": "ASCENDING" },
    { "fieldPath": "nameTokens", "arrayConfig": "CONTAINS" }
  ]
},
{
  "collectionGroup": "circles",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "isDeleted", "order": "ASCENDING" },
    { "fieldPath": "ownerId", "order": "ASCENDING" },
    { "fieldPath": "category", "order": "ASCENDING" },
    { "fieldPath": "nameTokens", "arrayConfig": "CONTAINS" }
  ]
}
```

**カテゴリフィルタ方針:** カテゴリフィルタはFirestoreクエリレベルで適用する（サーバー側JSフィルタではない）。カテゴリ付きクエリ用の追加インデックスが必要になるが、ページネーションの正確性とコスト効率を優先する。カテゴリ付きインデックスは以下を追加:

```json
{
  "collectionGroup": "circles",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "isDeleted", "order": "ASCENDING" },
    { "fieldPath": "aiMode", "order": "ASCENDING" },
    { "fieldPath": "category", "order": "ASCENDING" },
    { "fieldPath": "nameTokens", "arrayConfig": "CONTAINS" },
    { "fieldPath": "memberCount", "order": "DESCENDING" },
    { "fieldPath": "__name__", "order": "ASCENDING" }
  ]
}
```

**注意**: `array-contains` と `in` は同一クエリで使用可能（Firestoreの制約上OK）。

### 2.6 クライアント側変更

#### 2.6.1 debounce追加

```dart
// circles_screen.dart
Timer? _debounceTimer;

@override
void dispose() {
  _debounceTimer?.cancel();
  _searchController.dispose();
  _scrollController.dispose();
  super.dispose();
}

// TextField.onChanged のハンドラ
void _onSearchChanged(String value) {
  _debounceTimer?.cancel();
  if (value.isEmpty) {
    setState(() {
      _isSearching = false;
      _searchResults = [];
    });
    return;
  }
  _debounceTimer = Timer(const Duration(milliseconds: 300), () {
    _performSearch(value);
  });
}
```

`TextField.onChanged` を `_onSearchChanged` に変更:

```dart
TextField(
  controller: _searchController,
  onChanged: _onSearchChanged,  // debounce付き
  ...
)
```

#### 2.6.2 searchCircles をCloud Functions callable呼び出しに変更

```dart
// circle_service.dart

/// 検索カーソル（ページネーション用）
typedef SearchCursor = ({int memberCount, String id});

/// 検索結果とページネーション情報を返すレコード型
typedef SearchResult = ({
  List<CircleModel> circles,            // 公開サークル（cursorページネーション対象）
  List<CircleModel> privateOwnerCircles, // オーナーのaiOnlyサークル（初回のみ）
  bool hasMore,
  SearchCursor? nextCursor,
});

Future<SearchResult> searchCircles(
  String query, {
  required String userId,
  String? category,
  SearchCursor? cursor,
}) async {
  final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');
  final callable = functions.httpsCallable('searchCircles');

  final result = await callable.call({
    'query': query,
    if (category != null && category != '全て') 'category': category,
    'limit': 20,
    if (cursor != null) 'cursor': {
      'memberCount': cursor.memberCount,
      'id': cursor.id,
    },
  });

  final data = Map<String, dynamic>.from(result.data as Map);
  final hasMore = data['hasMore'] as bool? ?? false;
  final cursorData = data['nextCursor'] as Map<String, dynamic>?;
  final nextCursor = cursorData != null
      ? (memberCount: cursorData['memberCount'] as int, id: cursorData['id'] as String)
      : null;

  // JSON → CircleModel 変換ヘルパー
  CircleModel parseCircle(Map<String, dynamic> json) => CircleModel(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String,
    category: json['category'] as String,
    ownerId: json['ownerId'] as String,
    aiMode: CircleAIMode.values.firstWhere(
      (e) => e.name == (json['aiMode'] ?? 'mix'),
      orElse: () => CircleAIMode.mix,
    ),
    isPublic: json['isPublic'] as bool? ?? true,
    memberCount: json['memberCount'] as int? ?? 0,
    postCount: json['postCount'] as int? ?? 0,
    iconImageUrl: json['iconImageUrl'] as String?,
    coverImageUrl: json['coverImageUrl'] as String?,
    goal: json['goal'] as String? ?? '',
    recentActivity: DateTime.tryParse(json['recentActivity'] as String? ?? ''),
    lastHumanPostAt: DateTime.tryParse(json['lastHumanPostAt'] as String? ?? ''),
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    memberIds: [],  // 検索結果ではメンバーIDリストは不要
  );

  final circlesList = List<Map<String, dynamic>>.from(data['circles'] as List);
  final circles = circlesList.map(parseCircle).toList();

  final privateList = List<Map<String, dynamic>>.from(data['privateOwnerCircles'] as List);
  final privateOwnerCircles = privateList.map(parseCircle).toList();

  return (
    circles: circles,
    privateOwnerCircles: privateOwnerCircles,
    hasMore: hasMore,
    nextCursor: nextCursor,
  );
}
```

#### 2.6.3 _performSearch と無限スクロール

```dart
// circles_screen.dart - 状態変数
bool _searchHasMore = false;
bool _isLoadingMoreSearch = false;
SearchCursor? _searchCursor;
List<CircleModel> _privateOwnerResults = [];  // aiOnlyサークル（初回のみ取得）

// 初回検索（検索文字列変更時）
// _searchGeneration: レースコンディション防止用。非同期レスポンスが
// 現在のクエリに対応しているかを世代番号で判定し、古い結果を破棄する。
int _searchGeneration = 0;

Future<void> _performSearch(String query) async {
  _searchGeneration++;
  final generation = _searchGeneration;

  if (query.isEmpty) {
    setState(() {
      _isSearching = false;
      _searchResults = [];
      _privateOwnerResults = [];
      _searchHasMore = false;
      _searchCursor = null;
    });
    return;
  }

  setState(() => _isSearching = true);
  try {
    final circleService = ref.read(circleServiceProvider);
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    final result = await circleService.searchCircles(
      query,
      userId: currentUser?.uid ?? '',
      category: _selectedCategory,
      // 初回検索: cursor なし
    );
    // 古いリクエストの結果を破棄（レースコンディション防止）
    if (!mounted || generation != _searchGeneration) return;
    setState(() {
      _searchResults = result.circles;
      _privateOwnerResults = result.privateOwnerCircles;
      _searchHasMore = result.hasMore;
      _searchCursor = result.nextCursor;
      _isSearching = false;
    });
  } catch (e) {
    debugPrint('_performSearch エラー: $e');
    if (!mounted) return;
    setState(() {
      _searchResults = [];
      _privateOwnerResults = [];
      _searchHasMore = false;
      _searchCursor = null;
      _isSearching = false;
    });
    SnackBarHelper.showError(context, AppMessages.circle.searchError);
  }
}

// 追加読み込み（無限スクロール）
Future<void> _loadMoreSearchResults() async {
  if (_isLoadingMoreSearch || !_searchHasMore || _searchCursor == null) return;

  setState(() => _isLoadingMoreSearch = true);
  try {
    final circleService = ref.read(circleServiceProvider);
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    final result = await circleService.searchCircles(
      _searchController.text,
      userId: currentUser?.uid ?? '',
      category: _selectedCategory,
      cursor: _searchCursor,  // ソートキー含むcursorで安定ページネーション
    );
    if (!mounted) return;
    setState(() {
      _searchResults.addAll(result.circles);
      _searchHasMore = result.hasMore;
      _searchCursor = result.nextCursor;
      _isLoadingMoreSearch = false;
    });
  } catch (e) {
    if (!mounted) return;
    setState(() => _isLoadingMoreSearch = false);
  }
}
```

検索結果の表示では、2つのリストを結合して表示:

```dart
// 検索結果リストのビルド
List<CircleModel> get _allSearchResults => [
  ..._privateOwnerResults,  // aiOnlyサークル（先頭に表示）
  ..._searchResults,         // 公開サークル
];
```

スクロールリスナーで検索結果の末尾到達を検知:

```dart
void _onScroll() {
  // 既存のサークル一覧ページネーション処理...

  // 検索モード中の無限スクロール
  if (_searchController.text.isNotEmpty &&
      _scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
    _loadMoreSearchResults();
  }
}
```

### 2.7 アーキテクチャ概要

```
[変更前]
ユーザー入力 → onChanged → searchCircles() → Firestore全件get() → クライアント側filter → 表示

[変更後]
ユーザー入力 → onChanged → 300ms debounce → searchCircles() → Cloud Functions callable
  → クエリ1: aiOnlyオーナーサークル（初回のみ、別配列 privateOwnerCircles で返却）
  → クエリ2: 公開サークル（array-contains + memberCount DESC + documentId ASC + cursor）
  → レスポンス（circles ≤ limit件 + privateOwnerCircles + hasMore + nextCursor{memberCount,id}）→ 表示
  → スクロール末尾到達 → nextCursor で追加リクエスト → 公開サークルのみ追加表示
```

---

## 3. セキュリティ考慮

| # | 項目 | 対策 |
|---|------|------|
| S1 | 認証必須 | `requireAuth()` で未認証ユーザーを拒否 |
| S2 | App Check | `enforceAppCheck: true` で不正クライアントを拒否 |
| S3 | 入力バリデーション | query長さ制限（100文字）、limit制限（最大50） |
| S4 | aiOnlyサークルの漏洩防止 | `aiMode` が `mix`/`humanOnly` でない（=aiOnly）、かつ `ownerId` が自分でないサークルはレスポンスに含まない。招待制（`isPublic=false`）サークルは検索で表示され、参加時に申請フローを経由するため漏洩には該当しない |
| S5 | isDeletedサークルの漏洩 | Firestoreクエリレベルで `isDeleted == false` をフィルタ |
| S6 | memberIdsの漏洩防止 | レスポンスに `memberIds` を含めない（メンバー一覧は別APIで取得） |
| S7 | DoS防止 | Phase 2のcap（200件）でサーバー側読み取り量を制限。debounceでクライアント側発火頻度を制限 |

---

## 4. コスト影響分析

### 4.1 Firestore読み取りコスト

| シナリオ | 変更前（1検索あたり） | 変更後（1検索あたり） | 削減率 |
|---------|--------------------|--------------------|--------|
| サークル100件 | 100 reads | 通常21 reads | 79% |
| サークル1,000件 | 1,000 reads | 通常21 reads | 97.9% |
| サークル10,000件 | 10,000 reads | 通常21 reads | 99.8% |

**通常ケース（aiOnlyサークル未所有）**: 公開クエリ21件 = 21 reads。サークル数に関わらず上限固定。
**最大ケース（aiOnlyサークル50件所有）**: 公開クエリ21件 + ownerクエリ50件 = 71 reads。ただし公開サークルのレスポンス（`circles`）は常にlimit以下（デフォルト20件）。`privateOwnerCircles` は別枠で最大50件。

### 4.2 debounceによるクエリ発火回数削減

| 操作 | 変更前（debounceなし） | 変更後（300ms debounce） |
|------|---------------------|------------------------|
| 「ダイエット」入力 | 5回発火 | 1回発火 |
| 「Running Club」入力 | 12回発火 | 1〜2回発火 |

### 4.3 Cloud Functions実行コスト

| 項目 | コスト |
|------|--------|
| callable関数呼び出し | Cloud Functions無料枠（月200万回）内で収まる見込み |
| メモリ256MiB / タイムアウト10秒 | 最小構成 |
| ネットワーク | レスポンスは最大20件のサマリデータ（数KB） |

### 4.4 総合評価

**コスト増**: Cloud Functions実行コストがわずかに発生するが、Firestore読み取りコストの大幅削減で相殺される。サークル数が増えるほど効果が大きい。

---

## 5. マイグレーション計画

### 5.1 既存サークルへの `nameTokens` バックフィル

既存サークルには `nameTokens` フィールドが存在しないため、一括バックフィルが必要。

#### 方法: 管理者callable関数によるワンタイムマイグレーション

```typescript
// functions/src/callable/admin.ts に追加
import { generateNameTokens } from "../helpers/search-tokens";

export const backfillCircleNameTokens = onCall(
  {
    region: LOCATION,
    timeoutSeconds: 540,
    memory: "256MiB",  // 分割走査のためメモリ節約可能
  },
  async (request) => {
    await requireAdmin(request);

    const BATCH_SIZE = 400;
    const PAGE_SIZE = 500;  // 1回のFirestore読み取り件数上限
    let updated = 0;
    let total = 0;
    let lastDoc: FirebaseFirestore.DocumentSnapshot | undefined;

    // 分割走査: limit + startAfter で全件を分割処理
    // メモリに全件を載せず、PAGE_SIZE件ずつ処理する
    while (true) {
      let query: FirebaseFirestore.Query = db.collection("circles")
        .orderBy(FieldPath.documentId())
        .limit(PAGE_SIZE);

      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snapshot = await query.get();
      if (snapshot.empty) break;

      // バッチ書き込み
      for (let i = 0; i < snapshot.docs.length; i += BATCH_SIZE) {
        const batch = db.batch();
        const chunk = snapshot.docs.slice(i, i + BATCH_SIZE);

        for (const doc of chunk) {
          const data = doc.data();
          const name = data.name || "";
          const tokens = generateNameTokens(name);
          batch.update(doc.ref, { nameTokens: tokens });
          updated++;
        }

        await batch.commit();
      }

      total += snapshot.docs.length;
      lastDoc = snapshot.docs[snapshot.docs.length - 1];

      // 取得件数がPAGE_SIZE未満なら最終ページ
      if (snapshot.docs.length < PAGE_SIZE) break;
    }

    return { updated, total };
  }
);
```

#### 実行手順

1. `firebase deploy --only functions:backfillCircleNameTokens` でデプロイ
2. Firebase Consoleまたはcurlで関数を呼び出し
3. 完了確認後、関数を削除（ワンタイム）

### 5.2 デプロイ順序

```
Step 1: firebase deploy --only firestore:indexes
  → インデックス作成開始（数分〜数十分）
  → Firebase Consoleでインデックスの状態を確認（READY になるまで待機）

Step 2: firebase deploy --only functions
  → searchCircles callable関数デプロイ
  → onCircleCreated / onCircleUpdated のnameTokens設定ロジックデプロイ
  → backfillCircleNameTokens デプロイ

Step 3: backfillCircleNameTokens を実行
  → 既存サークルの nameTokens を一括設定

Step 4: アプリ更新（Flutter側）
  → debounce付き検索UI + callable呼び出しに切り替え

Step 5: backfillCircleNameTokens を index.ts から削除・再デプロイ（クリーンアップ）
```

### 5.3 後方互換性

- **旧バージョンのアプリ**: 旧 `searchCircles()` はクライアント側Firestoreクエリなので、Cloud Functions変更の影響なし。`nameTokens` フィールド追加はFirestoreの既存データに影響なし
- **ロールバック**: アプリ側のみの変更。旧バージョンのアプリがそのまま動作する

---

## 6. 既存フローへの影響

| フロー | 影響 | 理由 |
|--------|------|------|
| サークル検索 | **変更** | クライアント全件取得 → Cloud Functions callable経由に変更 |
| サークル一覧表示 | **なし** | `getPublicCirclesPaginated` は変更なし |
| サークル作成 | **軽微** | `onCircleCreated` トリガーに `nameTokens` 設定を追加 |
| サークル名変更 | **軽微** | `onCircleUpdated` トリガーに `nameTokens` 更新を追加 |
| 検索UI | **変更** | debounce追加、無限スクロール、カテゴリフィルタ対応 |
| 参加中サークル | **なし** | `streamMyCircles` は変更なし |

---

## 7. 変更ファイル一覧

| # | ファイル | 変更内容 | 影響度 |
|---|---------|---------|--------|
| 1 | `functions/src/callable/circles.ts` | `searchCircles` callable関数を追加 | **大** |
| 2 | `functions/src/index.ts` | `searchCircles` のexportを追加 | **小** |
| 3 | `functions/src/triggers/circles.ts` | `onCircleCreated`/`onCircleUpdated` に `nameTokens` 設定を追加 | **中** |
| 3.5 | `functions/src/helpers/search-tokens.ts` | `generateNameTokens()` ヘルパー関数を新規作成 | **小** |
| 4 | `functions/src/callable/admin.ts` | `backfillCircleNameTokens` ワンタイム関数を追加（後で削除） | **小** |
| 5 | `lib/shared/services/circle_service.dart` | `searchCircles()` をCloud Functions callable呼び出しに変更 | **中** |
| 6 | `lib/features/circle/presentation/screens/circles_screen.dart` | debounce追加、検索結果の無限スクロール、カテゴリフィルタ対応 | **中** |
| 7 | `firebase/firestore.indexes.json` | circles用コンポジットインデックス追加 | **小** |

---

## 8. リスクと注意点

| # | リスク | 影響度 | 対策 |
|---|--------|--------|------|
| R1 | インデックス未作成でcallable関数がエラー | **高** | Step 1でインデックスを先行デプロイし、READY確認後にStep 2以降を実行 |
| R2 | `nameTokens` 未設定のサークルが検索から漏れる | **高** | バックフィル（Step 3）を関数デプロイ直後に実行 |
| R3 | onCircleUpdatedのnameTokens更新で再帰ループ | **中** | name未変更時はnameTokens更新をスキップする条件分岐で防止 |
| R4 | 1文字検索の広範ヒット | **低** | 1文字検索は多くのサークルにヒットしうるが、`limit(20)`で読み取り量を制限。ユーザー要望により1文字から検索可能とした |
| R5a | サークル名が長い場合にトークン数が多くなる | **低** | 30文字で最大435トークン。Firestoreの配列上限40,000には余裕あり。ストレージコストも微小 |
| R5 | Cloud Functions cold startで初回検索が遅い | **低** | 300ms debounce + ローディングインジケーターで体感遅延を軽減。min_instances設定は コスト増のため採用しない |
| R6 | 検索結果にmemberIds含めないことでクライアント側の表示に影響 | **低** | サークルカードでmemberIds不要を確認済み。詳細画面遷移時にFirestoreから直接取得 |

### ロールバック

- **クライアント**: 旧バージョンの `searchCircles()` は独立したFirestoreクエリなので、アプリをロールバックすれば即座に旧動作に戻る
- **バックエンド**: `searchCircles` callable関数を削除しても旧アプリに影響なし。`nameTokens` フィールドは追加のみで既存フィールドに影響なし
- **インデックス**: 追加インデックスは既存クエリに影響なし（不要になれば削除可能）

---

## 9. テスト観点

### クライアント側

| # | テスト項目 |
|---|-----------|
| T1 | 検索バーに文字入力後、300ms後に検索が発火する |
| T2 | 高速入力時に最後の入力のみ検索が発火する（debounce動作） |
| T3 | 検索結果が正しく表示される（先頭一致） |
| T4 | 検索結果が正しく表示される（部分一致） |
| T5 | カテゴリフィルタ + 検索の組み合わせが動作する |
| T6 | 検索クリア（xボタン）でサークル一覧に戻る |
| T7 | 検索結果0件時に「見つかりませんでした」が表示される |
| T8 | ネットワークエラー時にエラーメッセージが表示される |
| T9 | aiOnlyサークルが検索結果に表示されない（オーナー以外）。招待制サークル（isPublic=false）は表示される |
| T10 | 自分がオーナーのaiOnlyサークルが検索結果に表示される |
| T11 | isDeletedサークルが検索結果に表示されない |
| T12 | 検索結果20件超の場合、スクロールで追加20件が読み込まれる |
| T13 | 追加読み込み中にローディング表示がされる |
| T14 | 全結果を読み込んだ後、追加読み込みが発火しない（hasMore=false） |

### バックエンド側

| # | テスト項目 |
|---|-----------|
| T15 | 未認証リクエストが拒否される |
| T16 | query1文字/100文字超がバリデーションエラーになる |
| T17 | 先頭一致サークルが検索結果に表示される（例: 「ダイエット」→「ダイエット部」） |
| T18 | 部分一致サークルが検索結果に表示される（例: 「ダイエット」→「毎日ダイエット」） |
| T19 | 公開ルール（aiMode mix/humanOnly）が正しく適用される |
| T20 | オーナーの非公開サークルが検索結果に含まれる |
| T21 | レスポンスにmemberIdsが含まれない |
| T22 | startAfterId指定で正しい次ページの結果が返される |
| T23 | hasMoreが正しく判定される（結果がlimitを超える場合true、以下の場合false） |
| T24 | サークル作成時にnameTokensが自動設定される（humanOnlyモード含む） |
| T25 | サークル名変更時にnameTokensが自動更新される |
| T26 | バックフィル関数で既存サークルのnameTokensが正しく設定される |
| T27 | generateNameTokensが正しいN-gramトークンを生成する |
