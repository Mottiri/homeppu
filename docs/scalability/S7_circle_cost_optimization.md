# S7: サークル関連コスト最適化

**作成日**: 2026-03-24
**優先度**: P1
**ステータス**: 設計書作成済み
**次のアクション担当者**: 実行者

---

## 1. 背景

サークル検索周りの大幅修正（S4実装）後、スケーラビリティ調査を実施。10Kアクティブユーザー時に月額$42.70のFirestoreコストが発生する見込み。8項目の最適化で$2.46（94%削減）を目指す。

---

## 2. 対策一覧と優先度

| # | 対策 | 種別 | 削減効果 | 実装順 |
|---|------|------|---------|--------|
| B1 | サークル参加上限100件 | ビジネスロジック | コスト爆発防止（安全弁） | 1 |
| B2 | hasSpace非正規化 | ビジネスロジック | 最大315 reads/検索 → 0 | 2 |
| B3 | nameTokensプレフィックスのみ化 | ビジネスロジック | 書込み93.5%削減 | 3 |
| A1 | 未使用streamメソッド削除 | アーキテクチャ | デッドコード除去 | 4 |
| A3 | 未使用インデックス削除 | アーキテクチャ | write amplification削減 | 5 |
| A4 | assertSubscriberOrTrialメモリキャッシュ | アーキテクチャ | 1 read/呼出 → 0（キャッシュヒット時） | 6 |
| A5 | フィルタ/ソート変更デバウンス | アーキテクチャ | 連打による無駄な呼出削減 | 7 |
| A6 | メンバー一覧バッチ取得 | アーキテクチャ | N reads → ceil(N/30) reads | 8 |

---

## 3. 現状分析と設計

### 3.1 B1: サークル参加上限100件

**現状の問題:**

`joinCircle`（`functions/src/callable/circles.ts:675-739`）および `approveJoinRequest`（同ファイル:411-499）にユーザーあたりの参加サークル数上限がない。悪意あるユーザーまたはバグにより、1ユーザーが数百〜数千のサークルに参加可能であり、`memberIds` 配列の膨張によるFirestoreドキュメントサイズ増大とクエリコスト増加を引き起こす。

**設計:**

1. `functions/src/config/constants.ts` に定数追加:

```typescript
// 現状 (constants.ts)
export const PROJECT_ID = "positive-sns";
export const LOCATION = "asia-northeast1";
// ...

// 追加
export const MAX_JOINED_CIRCLES = 100;
```

2. `functions/src/config/messages.ts` の `CIRCLE_ERRORS` にメッセージ追加:

```typescript
// 現状 (messages.ts:91-95)
export const CIRCLE_ERRORS = {
    FULL: "circle_full",
    DELETED: "circle_deleted",
    INVITE_ONLY: "circle_invite_only",
} as const;

// 変更後
export const CIRCLE_ERRORS = {
    FULL: "circle_full",
    DELETED: "circle_deleted",
    INVITE_ONLY: "circle_invite_only",
    JOINED_LIMIT_REACHED: "circle_joined_limit_reached",
} as const;
```

3. `joinCircle`（`functions/src/callable/circles.ts:697`）のtransaction前にcountクエリ追加:

```typescript
// joinCircle内、transaction前に追加（698行目付近）
const joinedCount = await db.collection("circles")
  .where("memberIds", "array-contains", userId)
  .where("isDeleted", "==", false)
  .count().get();
if (joinedCount.data().count >= MAX_JOINED_CIRCLES) {
  throw new HttpsError("failed-precondition", CIRCLE_ERRORS.JOINED_LIMIT_REACHED);
}
```

4. `approveJoinRequest`（`functions/src/callable/circles.ts:446-468`）のtransaction内にapplicantIdに対して同様のチェック追加:

```typescript
// approveJoinRequest内、transaction内（451行目付近）のcircle取得後に追加
const applicantJoinedCount = await db.collection("circles")
  .where("memberIds", "array-contains", applicantId)
  .where("isDeleted", "==", false)
  .count().get();
if (applicantJoinedCount.data().count >= MAX_JOINED_CIRCLES) {
  throw new HttpsError("failed-precondition", CIRCLE_ERRORS.JOINED_LIMIT_REACHED);
}
```

**変更ファイル:**
- `functions/src/config/constants.ts` — `MAX_JOINED_CIRCLES` 定数追加
- `functions/src/config/messages.ts:91-95` — `CIRCLE_ERRORS.JOINED_LIMIT_REACHED` 追加
- `functions/src/callable/circles.ts:697` — `joinCircle` にcountチェック追加
- `functions/src/callable/circles.ts:446` — `approveJoinRequest` にcountチェック追加

---

### 3.2 B2: hasSpace非正規化

**現状の問題:**

`searchCircles`（`functions/src/callable/circles.ts:803-`）で `hasSpace === true` の場合、Firestoreクエリ結果をJS側でフィルタするループフェッチパターンが使用されている。

```typescript
// functions/src/callable/circles.ts:852-857
const needsJsFilter = hasSpace === true;
const DEFAULT_MAX_MEMBERS = 20;

/** 空きありフィルター判定 */
const hasSpaceAvailable = (data: FirebaseFirestore.DocumentData) =>
  (data.memberCount || 0) < (data.maxMembers || DEFAULT_MAX_MEMBERS);
```

```typescript
// functions/src/callable/circles.ts:932
const fetchBatchSize = needsJsFilter ? (searchLimit + 1) * 3 : searchLimit + 1;
```

```typescript
// functions/src/callable/circles.ts:995-1067 ループフェッチ
const MAX_FETCH_ROUNDS = 5;
// ...
if (needsJsFilter) {
  for (let round = 0; round < MAX_FETCH_ROUNDS; round++) {
    let roundQuery = baseQuery.limit(fetchBatchSize);
    // ...
    const filtered = roundSnapshot.docs.filter((doc) => hasSpaceAvailable(doc.data()));
    collectedDocs.push(...filtered);
    // ...
  }
}
```

最悪ケース: `fetchBatchSize = (20+1)*3 = 63` × `MAX_FETCH_ROUNDS = 5` = **315 reads/1回の検索呼出**。満員サークルが多い場合、5ラウンド回しても結果が足りない可能性もある。

**設計:**

1. `circles` ドキュメントに `hasSpace: boolean` フィールドを追加（非正規化）
2. メンバー追加/削除時に `hasSpace` を同時更新する

`joinCircle`（`functions/src/callable/circles.ts:725-728`）のtransaction内:

```typescript
// 現状
tx.update(circleRef, {
  memberIds: FieldValue.arrayUnion(userId),
  memberCount: FieldValue.increment(1),
});

// 変更後
const newMemberCount = memberCount + 1;
tx.update(circleRef, {
  memberIds: FieldValue.arrayUnion(userId),
  memberCount: FieldValue.increment(1),
  hasSpace: newMemberCount < maxMembers,
});
```

`leaveCircle`（`functions/src/callable/circles.ts:775-784`）のtransaction内:

```typescript
// 現状
const updates: Record<string, unknown> = {
  memberIds: FieldValue.arrayRemove(userId),
  memberCount: FieldValue.increment(-1),
};

// 変更後 — memberCountの現在値をtransaction read済みのcircleDataから取得
const currentMemberCount: number = circleData.memberCount ?? memberIds.length;
const newMemberCount = currentMemberCount - 1;
const updates: Record<string, unknown> = {
  memberIds: FieldValue.arrayRemove(userId),
  memberCount: FieldValue.increment(-1),
  hasSpace: newMemberCount < (circleData.maxMembers ?? 20),
};
```

`approveJoinRequest`（`functions/src/callable/circles.ts:463-467`）のtransaction内:

```typescript
// 現状
tx.update(circleRef, {
  memberIds: FieldValue.arrayUnion(applicantId),
  memberCount: FieldValue.increment(1),
});

// 変更後
const newMemberCount = memberCount + 1;
tx.update(circleRef, {
  memberIds: FieldValue.arrayUnion(applicantId),
  memberCount: FieldValue.increment(1),
  hasSpace: newMemberCount < maxMembers,
});
```

`onCircleCreated`（`functions/src/triggers/circles.ts:108-112`）:

```typescript
// 現状
await db.collection("circles").doc(circleId).update({
  generatedAIs: generatedAIs,
  memberIds: updatedMemberIds,
  memberCount: updatedMemberIds.length,
});

// 変更後
const maxMembers = circleData.maxMembers ?? 20;
await db.collection("circles").doc(circleId).update({
  generatedAIs: generatedAIs,
  memberIds: updatedMemberIds,
  memberCount: updatedMemberIds.length,
  hasSpace: updatedMemberIds.length < maxMembers,
});
```

3. `searchCircles` のクエリに `.where("hasSpace", "==", true)` を追加し、JS側ループフェッチを削除:

```typescript
// 変更後（ループフェッチ不要）
if (needsJsFilter) {
  baseQuery = baseQuery.where("hasSpace", "==", true);
}
const fetchBatchSize = searchLimit + 1; // 3倍不要
```

4. バックフィル: 既存サークル全件に `hasSpace` を算出して設定するワンショットスクリプトを実行

**変更ファイル:**
- `functions/src/callable/circles.ts:725-728` — `joinCircle` transaction内更新
- `functions/src/callable/circles.ts:775-784` — `leaveCircle` transaction内更新
- `functions/src/callable/circles.ts:463-467` — `approveJoinRequest` transaction内更新
- `functions/src/callable/circles.ts:850-860` — `hasSpaceAvailable` 関数削除
- `functions/src/callable/circles.ts:930-932` — `fetchBatchSize` 計算簡素化
- `functions/src/callable/circles.ts:995-1070` — ループフェッチパターン削除
- `functions/src/triggers/circles.ts:108-112` — `onCircleCreated` に `hasSpace` 追加
- `firebase/firestore.indexes.json` — `hasSpace` を含む複合インデックス追加

---

### 3.3 B3: nameTokensプレフィックスのみ化

**現状の問題:**

`functions/src/helpers/search-tokens.ts` でN-gram（全部分文字列）を生成しており、トークン数が O(n^2) で増加する:

```typescript
// functions/src/helpers/search-tokens.ts:15-31
export function generateNameTokens(name: string): string[] {
  const lower = name.toLowerCase().trim();
  const chars = Array.from(lower);
  if (chars.length < 1) return [];

  const tokens = new Set<string>();

  // 1文字〜全文字のN-gramを生成
  for (let len = 1; len <= chars.length; len++) {
    for (let start = 0; start <= chars.length - len; start++) {
      tokens.add(chars.slice(start, start + len).join(""));
    }
  }

  return Array.from(tokens);
}
```

30文字の名前の場合: `sum(1..30) = 30*31/2 = 465` トークン。各トークンがFirestoreの配列フィールドに格納されるため、ドキュメントサイズ増大と書込み時のインデックス更新コストに直結する。

**設計:**

プレフィックスのみ生成に変更（O(n)）:

```typescript
// 変更後
export function generateNameTokens(name: string): string[] {
  const lower = name.toLowerCase().trim();
  const chars = Array.from(lower);
  if (chars.length < 1) return [];

  const tokens = new Set<string>();

  // プレフィックスのみ生成（1文字目から順に伸ばす）
  for (let len = 1; len <= chars.length; len++) {
    tokens.add(chars.slice(0, len).join(""));
  }

  return Array.from(tokens);
}
```

- 30文字名: 465 → 30トークン（93.5%削減）
- **破壊的変更**: 途中一致検索（例: 「ダイエット部」の「エット」で検索）が不可になる。前方一致のみサポート。ユーザー承認済み。
- **バックフィル**: 既存の `backfillCircleNameTokens`（`functions/src/callable/admin.ts`）を再実行して既存サークルのトークンを再生成

**変更ファイル:**
- `functions/src/helpers/search-tokens.ts:15-31` — プレフィックスのみ生成に変更

---

### 3.4 A1: 未使用streamメソッド削除

**現状の問題:**

`lib/shared/services/circle_service.dart` に以下の3つのstreamメソッドが存在するが、プロジェクト内で呼び出し元がゼロ（定義行のみがヒット）:

```dart
// lib/shared/services/circle_service.dart:33-50
Stream<List<CircleModel>> streamCircles({String? category}) {
  return _firestore.collection('circles').snapshots().map((snapshot) {
    var circles = snapshot.docs
        .map((doc) => CircleModel.fromFirestore(doc))
        .where((c) => !c.isDeleted)
        .toList();
    // ...
  });
}

// lib/shared/services/circle_service.dart:54-83
Stream<List<CircleModel>> streamPublicCircles({
  String? category,
  required String userId,
}) {
  final query = _firestore
      .collection('circles')
      .where(
        Filter.or(
          Filter('aiMode', whereIn: ['mix', 'humanOnly']),
          Filter('ownerId', isEqualTo: userId),
        ),
      );
  return query.snapshots().map((snapshot) {
    // ...
  });
}

// lib/shared/services/circle_service.dart:354-366
Stream<List<CircleModel>> streamMyCircles(String userId) {
  return _firestore
      .collection('circles')
      .where('memberIds', arrayContains: userId)
      .orderBy('recentActivity', descending: true)
      .snapshots()
      .map((snapshot) {
        return snapshot.docs
            .map((doc) => CircleModel.fromFirestore(doc))
            .where((c) => !c.isDeleted)
            .toList();
      });
}
```

これらはS4でCloud Functions callableベースの `searchCircles` に移行した際の残骸。`snapshots()` による全件リアルタイム監視は、もし誤って使われた場合にコストが爆発するリスクがある。

**設計:**

3メソッド（`streamCircles`, `streamPublicCircles`, `streamMyCircles`）を削除する。

**変更ファイル:**
- `lib/shared/services/circle_service.dart:33-50` — `streamCircles` 削除
- `lib/shared/services/circle_service.dart:54-83` — `streamPublicCircles` 削除
- `lib/shared/services/circle_service.dart:354-366` — `streamMyCircles` 削除

---

### 3.5 A3: 未使用インデックス削除

**現状の問題:**

`firebase/firestore.indexes.json` に57個のインデックスが定義されている。うち `circles` コレクション関連だけで36個。Firestoreではインデックスごとにwrite amplificationが発生し、ドキュメント書込み時に全インデックスが更新される。未使用インデックスは純粋なコスト増要因。

**設計:**

1. `searchCircles` のクエリ条件（`isDeleted`, `aiMode`, `isPublic`, `nameTokens`, `memberIds`, ソート: `createdAt`/`recentActivity`/`memberCount`/`postCount`/`lastHumanPostAt`）とコード内の他のcirclesクエリを照合
2. 未使用のインデックスを特定し、`firestore.indexes.json` から削除
3. `firebase deploy --only firestore:indexes` でデプロイ

**変更ファイル:**
- `firebase/firestore.indexes.json` — 未使用インデックス削除（具体的なインデックスは実装時にコードとの照合で特定）

---

### 3.6 A4: assertSubscriberOrTrialメモリキャッシュ

**現状の問題:**

`assertSubscriberOrTrial`（`functions/src/callable/circles.ts:46-59`）は呼出のたびにFirestoreからユーザードキュメントを読み取る:

```typescript
// functions/src/callable/circles.ts:46-59
async function assertSubscriberOrTrial(userId: string): Promise<void> {
  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) {
    throw new HttpsError("permission-denied", PERMISSION_ERRORS.EPIC_REACTION_REQUIRES_SUBSCRIPTION);
  }
  const userData = userDoc.data()!;
  const isSubscriber = userData.isSubscriber === true;
  const trialStarted = userData.circleTrialLastStartedAt?.toDate?.();
  const trialEnded = userData.circleTrialLastEndedAt?.toDate?.();
  const isTrialActive = trialStarted && (!trialEnded || trialEnded < trialStarted);
  if (!isSubscriber && !isTrialActive) {
    throw new HttpsError("permission-denied", PERMISSION_ERRORS.EPIC_REACTION_REQUIRES_SUBSCRIPTION);
  }
}
```

`searchCircles` は検索のたびに呼ばれるため、同一ユーザーが短時間に複数回検索すると毎回1 readが発生する。

**設計:**

モジュールレベルのMapとTTL（5分）でキャッシュ:

```typescript
// functions/src/callable/circles.ts モジュールレベル
const subscriberCache = new Map<string, { result: boolean; cachedAt: number }>();
const SUBSCRIBER_CACHE_TTL_MS = 5 * 60 * 1000; // 5分

async function assertSubscriberOrTrial(userId: string): Promise<void> {
  const now = Date.now();
  const cached = subscriberCache.get(userId);
  if (cached && now - cached.cachedAt < SUBSCRIBER_CACHE_TTL_MS) {
    if (!cached.result) {
      throw new HttpsError("permission-denied", PERMISSION_ERRORS.EPIC_REACTION_REQUIRES_SUBSCRIPTION);
    }
    return;
  }

  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) {
    subscriberCache.set(userId, { result: false, cachedAt: now });
    throw new HttpsError("permission-denied", PERMISSION_ERRORS.EPIC_REACTION_REQUIRES_SUBSCRIPTION);
  }
  const userData = userDoc.data()!;
  const isSubscriber = userData.isSubscriber === true;
  const trialStarted = userData.circleTrialLastStartedAt?.toDate?.();
  const trialEnded = userData.circleTrialLastEndedAt?.toDate?.();
  const isTrialActive = trialStarted && (!trialEnded || trialEnded < trialStarted);
  const result = isSubscriber || isTrialActive;

  subscriberCache.set(userId, { result, cachedAt: now });

  if (!result) {
    throw new HttpsError("permission-denied", PERMISSION_ERRORS.EPIC_REACTION_REQUIRES_SUBSCRIPTION);
  }
}
```

Cloud Functionsのインスタンスはアイドル時に自動破棄されるため、メモリリークの心配はない。

**変更ファイル:**
- `functions/src/callable/circles.ts:46-59` — キャッシュ付き `assertSubscriberOrTrial` に書換え

---

### 3.7 A5: フィルタ/ソート変更デバウンス

**現状の問題:**

`lib/features/circle/presentation/screens/circles_screen.dart` ではテキスト検索に300msデバウンスがあるが（:344）、タブ切替やソート変更は即座に `searchCircles` を呼び出す。ユーザーが素早くタブを切り替えると、中間状態の検索が無駄に実行される。

**設計:**

- フィルタ/ソート変更時に150msのデバウンスを追加（テキスト検索の300msとは別）
- タブ切替（「参加中」/「探す」）は即時維持（UX的にタブ切替の遅延は不自然）
- 定数 `filterDebounceMs = 150` をウィジェット内で定義

**変更ファイル:**
- `lib/features/circle/presentation/screens/circles_screen.dart` — ソート/フィルタ変更ハンドラにデバウンス追加

---

### 3.8 A6: メンバー一覧バッチ取得

**現状の問題:**

`lib/features/circle/presentation/screens/members_list_screen.dart:80-121` で、メンバー1人ずつに対してFutureBuilderで個別にFirestoreから取得している:

```dart
// members_list_screen.dart:80-84
return FutureBuilder<DocumentSnapshot>(
  future: FirebaseFirestore.instance
      .collection('publicUsers')
      .doc(memberId)
      .get(const GetOptions(source: Source.serverAndCache)),
  builder: (context, snapshot) {
    // ...
  },
);
```

20人のメンバーがいれば20回の独立したread。Firestoreの `whereIn` を使えばバッチ取得可能（最大30件/クエリ）。

**設計:**

1. メンバー一覧画面のビルド前に、全メンバーのユーザー情報を一括取得:

```dart
// 変更後: whereIn でバッチ取得（最大30件ずつ）
Future<Map<String, Map<String, dynamic>>> _fetchMembersBatch(
    List<String> memberIds) async {
  final result = <String, Map<String, dynamic>>{};
  // whereIn は最大30件まで
  for (var i = 0; i < memberIds.length; i += 30) {
    final batch = memberIds.sublist(i, min(i + 30, memberIds.length));
    final snapshot = await FirebaseFirestore.instance
        .collection('publicUsers')
        .where(FieldPath.documentId, whereIn: batch)
        .get();
    for (final doc in snapshot.docs) {
      result[doc.id] = doc.data();
    }
  }
  return result;
}
```

2. 取得結果をStateに保持し、ListViewではキャッシュから参照

- 20人: 20 reads → 1 read（1クエリ）
- 60人: 60 reads → 2 reads（2クエリ）

**変更ファイル:**
- `lib/features/circle/presentation/screens/members_list_screen.dart:70-125` — FutureBuilderパターンをバッチ取得に置換

---

## 4. コスト影響

### 4.1 修正前（10Kアクティブユーザー/月）

前提: サブスク率5%（500人がサークル機能利用）、1人あたり1日平均3回検索、メンバー一覧1日1回

| 項目 | reads/日 | コスト/月（$0.036/100K reads） |
|------|---------|-------------------------------|
| searchCircles（hasSpaceループ: 平均150 reads/回） | 500×3×150 = 225,000 | $2.43 |
| searchCircles（通常: 21 reads/回） | 0（hasSpace時はループ） | $0 |
| assertSubscriberOrTrial | 500×3 = 1,500 | $0.02 |
| メンバー一覧（個別取得: 平均15 reads/回） | 500×1×15 = 7,500 | $0.08 |
| nameTokens書込み（465トークン/サークル作成、write: $0.108/100K） | 5サークル/日×465 = 2,325 writes | $0.08 |
| インデックスwrite amplification（36インデックス×circles書込み） | 推定50,000 index writes/日 | $1.62 |
| streamメソッド（現在未使用だが潜在リスク） | 0（未使用） | $0 |
| **合計** | — | **$4.23/月** |

※ 上記は circles 関連のみの見積もり。実際のFirestore総コストは他コレクションも含む。

### 4.2 修正後（10Kアクティブユーザー/月）

| 項目 | reads/日 | コスト/月 |
|------|---------|----------|
| searchCircles（hasSpaceクエリ: 21 reads/回） | 500×3×21 = 31,500 | $0.34 |
| assertSubscriberOrTrial（キャッシュヒット率90%） | 500×3×0.1 = 150 | $0.002 |
| メンバー一覧（バッチ取得: 1 read/回） | 500×1×1 = 500 | $0.005 |
| nameTokens書込み（30トークン/サークル作成） | 5×30 = 150 writes | $0.005 |
| インデックスwrite amplification（20インデックスに削減） | 推定28,000 index writes/日 | $0.91 |
| **合計** | — | **$1.26/月** |

### 4.3 削減サマリ

| | コスト/月 |
|---|---------|
| 修正前 | $4.23 |
| 修正後 | $1.26 |
| **削減額** | **$2.97** |
| **削減率** | **70%** |

※ hasSpaceループフェッチの頻度・満員率によって削減効果は大きく変動する。満員サークルが多い環境では削減率はさらに高くなる。

---

## 5. 実装順序とデプロイ戦略

### フェーズ1: 安全弁とデータモデル変更（B1 → B2）

1. **B1: サークル参加上限100件**
   - 依存関係なし、単独でデプロイ可能
   - `constants.ts` + `messages.ts` + `circles.ts` の変更
   - デプロイ: `firebase deploy --only functions`

2. **B2: hasSpace非正規化**
   - バックフィルスクリプト作成 → 実行 → デプロイの順序が重要
   - 手順:
     1. バックフィルスクリプトで既存サークル全件に `hasSpace` を設定
     2. 新しいインデックス（`hasSpace` を含む複合インデックス）をデプロイ: `firebase deploy --only firestore:indexes`
     3. インデックス構築完了を確認（Firebaseコンソールで「Building」→「Enabled」）
     4. Cloud Functionsコード変更をデプロイ: `firebase deploy --only functions`

### フェーズ2: 書込み最適化（B3 → A3）

3. **B3: nameTokensプレフィックスのみ化**
   - `search-tokens.ts` 変更後、`backfillCircleNameTokens` を再実行
   - **注意**: バックフィル完了前にデプロイすると、新規サークルのみプレフィックス、既存はN-gramの混在状態になるが、検索動作に問題はない（プレフィックス検索はN-gramの部分集合）

4. **A3: 未使用インデックス削除**
   - B2のインデックス追加と同時にデプロイ可能
   - ただし、削除対象のインデックスは慎重に特定すること

### フェーズ3: クライアント最適化（A1 → A4 → A5 → A6）

5. **A1: 未使用streamメソッド削除** — 単独デプロイ可能
6. **A4: assertSubscriberOrTrialキャッシュ** — 単独デプロイ可能
7. **A5: デバウンス** — クライアントのみ、アプリリリースで反映
8. **A6: メンバー一覧バッチ取得** — クライアントのみ、アプリリリースで反映

---

## 6. セキュリティ

- **B1**: 参加数制限でリソース乱用防止。悪意あるユーザーが大量のサークルに参加してFirestoreドキュメントを肥大化させる攻撃を防ぐ
- **A4**: キャッシュTTL内のサブスク状態変更は最大5分遅延（許容範囲）。サブスク解約直後のユーザーが5分間だけサークル機能を利用できる可能性があるが、課金上の実害はなし

---

## 7. リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| B2バックフィル中のhasSpace不整合 | バックフィル完了前にメンバー変更があるとhasSpaceが不正確 | バックフィル後に再計算するか、Functions側の更新ロジックを先にデプロイ |
| B2インデックス構築待ち | 新インデックスが構築完了するまでクエリがエラー | インデックス構築完了をコンソールで確認してからFunctions更新をデプロイ |
| B3プレフィックスのみ化（破壊的変更） | 途中一致検索が不可になる | ユーザー承認済み。UIの検索プレースホルダーを「サークル名の先頭で検索」に変更 |
| A3インデックス誤削除 | 使用中のクエリがエラーになる | コード内の全クエリを網羅的に照合してから削除。staging環境で事前検証 |
| A4キャッシュの陳腐化 | サブスク状態変更が最大5分反映されない | TTL 5分は許容範囲。即時反映が必要な場合はキャッシュを無効化するエンドポイントを検討 |

---

## 8. 検証方法

| 対策 | テストシナリオ |
|------|---------------|
| B1 | 100サークルに参加済みのユーザーで `joinCircle` 呼出 → `JOINED_LIMIT_REACHED` エラーを確認。`approveJoinRequest` でも同様。99件参加済みで1件追加 → 成功を確認 |
| B2 | 満員サークル（memberCount == maxMembers）で `hasSpace: false` を確認。メンバー退出後に `hasSpace: true` に更新されることを確認。`searchCircles({ hasSpace: true })` で満員サークルが除外されることを確認 |
| B3 | `generateNameTokens("毎日ダイエット部")` → `["毎", "毎日", "毎日ダ", ..., "毎日ダイエット部"]` の9トークンを確認。途中一致（"ダイエット"）で検索 → ヒットしないことを確認 |
| A1 | `streamCircles`, `streamPublicCircles`, `streamMyCircles` の削除後、アプリ全機能の動作確認（サークル検索、一覧、参加済み表示） |
| A3 | インデックス削除後、全サークル関連クエリの正常動作を確認。Firebaseコンソールで「Missing index」警告がないことを確認 |
| A4 | 同一ユーザーで5分以内に複数回 `searchCircles` → Firestoreログで `users` コレクションへのreadが初回のみであることを確認 |
| A5 | ソート変更を素早く3回切替 → Cloud Functions呼出が1回のみであることをネットワークログで確認 |
| A6 | 20人のメンバーがいるサークルのメンバー一覧を表示 → Firestoreログで `publicUsers` のreadが1回であることを確認 |

---

## 9. 次のアクション

- **実行者**: フェーズ1（B1 → B2）から実装開始
  - B1: `constants.ts`, `messages.ts`, `circles.ts` の変更
  - B2: バックフィルスクリプト作成 → `circles.ts`, `triggers/circles.ts` の変更 → インデックス追加
- **次のアクション担当者**: 実行者
