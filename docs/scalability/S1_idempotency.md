# S1: Cloud Functions idempotency key 導入

**作成日**: 2026-03-11
**優先度**: P0
**ステータス**: 実装完了・検収OK（設計9回 + 実装2回 Codexレビュー完了）
**次のアクション担当者**: 全体管理者 → 最終確認

---

## 背景

Cloud Functions のトリガー・Cloud Tasks ワーカーにリトライ耐性（冪等性）がなく、再試行時に以下の副作用が二重実行される。

---

## 問題の全体像

```
onPostCreated トリガー
  ├─ Cloud Tasks タスク投入（Task ID 自動生成 → 重複タスク防止なし）
  │   ├─ generateAICommentV1  → コメント二重記録
  │   │   └─ [連鎖影響] コメント作成 → onCommentCreated → AIリアクション生成タスク投入
  │   │                    → commentCount 二重加算
  │   │                    → コメント通知作成 → FCM重複送信
  │   │                    → AIリアクション → reactions.* 二重加算 → リアクション通知 → FCM重複送信
  │   │
  │   └─ generateAIReactionV1 → リアクション二重記録（チェックあるがレース条件）
  │       └─ [連鎖影響] reactions.* 二重加算 → リアクション通知 → FCM重複送信
  │
  ├─ onCommentCreatedNotify → sendPushNotification → onNotificationCreated → FCM重複送信
  └─ onReactionAddedNotify  → sendPushNotification → onNotificationCreated → FCM重複送信

AIリアクション選択（リトライと無関係な問題）:
  └─ persona選択がランダム（replacement）→ 同一personaが複数回選ばれる可能性
```

**重要**: AIコメント1件の重複は、下流のリアクション生成・カウンタ更新・通知送信の連鎖的な重複を引き起こす。対策はコメント生成の冪等性を最優先で確保する必要がある。

---

## 現状の問題点（コード調査結果）

| 処理 | ファイル | 重複防止 | リトライ時の副作用 |
|------|---------|---------|------------------|
| AIコメント生成 | ai-generation.ts:214-342 | Jaccard類似度チェックのみ | コメント+連鎖リアクション+カウンタ+通知すべて二重 |
| AIリアクション生成 | ai-generation.ts:428-439 | あり（不完全・レース条件） | レース条件で重複リアクション |
| AI投稿生成 | ai-generation.ts:549-553 | なし | `totalPosts`/`totalPraises` 統計が複数回加算 |
| AIリアクションpersona選択 | triggers/posts.ts:234 | なし | 同一personaが重複選択される（リトライ不要で発生） |
| 通知プッシュ送信 | notifications.ts | なし | FCM重複送信 |
| 通知ドキュメント作成 | notification.ts | ID自動生成 | 上流リトライで別IDの通知ドキュメントが作成→FCM重複 |
| FCMエラーハンドリング | notification.ts:68-82 | なし | sendPushOnlyがエラーを握りつぶし送信状態が不正確 |
| Cloud Tasks投入 | cloud-tasks.ts | Task ID未指定 | 同一タスクが複数投入可能 |

---

## 対策設計

### 対象スコープ

**S1の対象は AI系処理（投稿/コメント/リアクション）に限定する。**

| 経路 | 対象 | 理由 |
|------|------|------|
| `triggers/posts.ts` → AIコメント/リアクション生成 | **対象** | トリガーリトライで重複が発生しやすい |
| `callable/ai.ts` → AI投稿生成 | **対象** | 手動操作だがCloud Tasks経由 |
| `scheduled/ai-posts.ts` → AI投稿生成（定期） | **対象** | 直呼び経路を`scheduleHttpTask`に統一 |
| `triggers/notifications.ts` → コメント/リアクション通知 | **対象** | `sendPushNotification`経由の通知 |

**S1の対象外（後続タスクで対応）**:

| 経路 | 非対象理由 |
|------|-----------|
| `callable/circles.ts` → サークル削除クリーンアップ | ユーザー手動操作で発生頻度が低い。削除処理は既存のFirestore上書きで冪等性がある程度担保されている |
| `scheduled/circles.ts` → ゴーストサークルクリーンアップ | 日次スケジュール実行。クリーンアップ処理は削除が中心で冪等性のリスクが低い |
| `circle-ai/posts.ts` → サークルAI投稿 | サークルAI投稿の重複リスクはあるが、S1ではまず投稿トリガー系を優先 |
| 通知direct writer（15箇所以上、後述） | Callable関数からのユーザー操作起因でリトライリスクが低い |

### Canonical Idempotency Key

全レイヤーで同一のイベントを追跡するため、**canonical idempotency key**をpayloadに載せてエンドツーエンドで伝搬する。

**キーの形式**: `{処理種別}-{postId}-{personaId}`
- AIコメント: `ai-comment-{postId}-{personaId}`
- AIリアクション: `ai-reaction-{postId}-{personaId}`
- AI投稿: `ai-post-{personaId}-{yyyyMMdd}`

**伝搬経路**:
```
[Producer] Cloud Tasks payload.idempotencyKey = "ai-comment-{postId}-{personaId}"
    ↓
[Cloud Tasks] task.name = ".../{idempotencyKey}"
    ↓
[Worker] commentRef = db.collection("comments").doc(idempotencyKey)
    ↓
[Notification] notificationId = "{type}-{sourceEventId}-{recipientId}"（重複排除用）
              + doc.canonicalIdempotencyKey = idempotencyKey（相関追跡用）
    ↓
[Log] 全層で idempotencyKey をログに出力 → 障害調査時に相関可能
```

**通知層でのキー分離**:
通知層では2つのキーを使い分ける:
- **notificationId（重複排除用）**: `{type}-{sourceEventId}-{recipientId}`。`sourceEventId`はイベント固有ID（`commentId`/`reactionId`等）。同一イベントの通知を1ドキュメントに集約する
- **canonicalIdempotencyKey（相関追跡用）**: 通知ドキュメント本文に別フィールドとして保持。上流のCloud Tasks名・ワーカーのドキュメントIDと同じキーで、障害調査時にエンドツーエンドの相関が可能

**理由**: AIコメントのcanonical keyは`ai-comment-{postId}-{personaId}`だが、通知の重複排除は`commentId`単位で行う必要がある（同一投稿への別コメントは別通知として正しく作成すべき）。重複排除キーと相関キーの役割が異なるため、分離設計とする。

**効果**:
- 通知の重複排除はイベント固有IDで正確に動作
- canonical keyは全層で一貫して伝搬され、障害調査時にtask→worker→notificationを即座に結合可能
- 手動再実行やロールバック時の影響範囲特定が容易

### 方針

AI系処理を対象に、4つのレイヤーで冪等性を確保する：

1. **Cloud Tasks レイヤー**: deterministic Task ID で重複タスク投入を防止
2. **ワーカーレイヤー**: 処理開始時の存在チェック+トランザクションで重複実行を防止
3. **Producer レイヤー**: persona選択時の重複除外でリトライ不要の重複を防止
4. **通知レイヤー**: `sendPushNotification`経由の通知のみ対象。deterministic 通知ID + pushStatus 5状態管理（pending/skipped/sending/sent/failed） + CAS で重複FCM送信を防止

### 対策1: Cloud Tasks に deterministic Task ID を設定

**変更ファイル**: `functions/src/helpers/cloud-tasks.ts`

**現状**:
```typescript
const [response] = await client.createTask({ parent: queuePath, task });
// Task ID は自動生成
```

**変更後**:
```typescript
type EnqueueResult = "created" | "duplicate_skipped";

async function scheduleHttpTask(
  options: HttpTaskOptions & { taskId?: string }
): Promise<{ result: EnqueueResult; taskName?: string }> {
  try {
    const task = taskId
      ? { name: `${queuePath}/tasks/${taskId}`, ...taskBody }
      : taskBody;
    const [response] = await client.createTask({ parent: queuePath, task });
    return { result: "created", taskName: response.name ?? undefined };
  } catch (error: unknown) {
    // ALREADY_EXISTS は expected duplicate として正常扱い
    if (
      error instanceof Error &&
      "code" in error &&
      (error as { code: number }).code === 6  // gRPC ALREADY_EXISTS
    ) {
      console.info(`Task duplicate skipped: ${taskId}`);
      return { result: "duplicate_skipped" };
    }
    throw error;  // その他のエラーは再送出
  }
}
```

**ALREADY_EXISTS ハンドリング契約**:
- `ALREADY_EXISTS`（gRPC code 6）は想定内の重複として`duplicate_skipped`を返す
- 呼び出し側はログレベルを`info`（異常ではない）として扱う
- その他のエラー（ネットワーク障害等）は例外として再送出し、上位でリトライ判断する
- 戻り値型が変わるが、既存callerは戻り値を使っていないため影響なし

**Task ID の生成ルール**:
- AIコメント: `ai-comment-${postId}-${aiUserId}`
- AIリアクション: `ai-reaction-${postId}-${aiUserId}`
- AI投稿: `ai-post-${personaId}-${todayStr}`
- サークルAI投稿: `circle-ai-post-${circleId}-${aiUserId}-${date}`
- サークル削除: `circle-cleanup-${circleId}-${batchIndex}`

**効果**: 同一の投稿+AIユーザーの組み合わせでタスクが重複投入されなくなる

**注意**: Cloud Tasks は完了済みタスクと同じ名前のタスクを一定期間（最大7日間）作成できない。Task ID にタイムスタンプ等を含めるか、投入前の存在チェックを検討。

**投入経路の網羅的対応**:
| 投入元ファイル | 対象タスク | 行番号 |
|--------------|-----------|--------|
| `triggers/posts.ts` | AIコメント生成 | 209-216 |
| `triggers/posts.ts` | AIリアクション生成 | 250-258 |
| `callable/ai.ts` | AI投稿生成 | 196-204 |
| `scheduled/ai-posts.ts` | AI投稿生成（定期） | 90 |

**注意: `scheduled/ai-posts.ts` の統一**
`scheduled/ai-posts.ts`は現在`CloudTasksClient.createTask()`を直接呼んでおり、`scheduleHttpTask`を経由していない。S1実装時にhelper経由に統一し、deterministic Task IDが適用されるようにする。

### 対策2: ワーカーに idempotency チェックを追加

**変更ファイル**: `functions/src/http/ai-generation.ts`

#### AIコメント生成（generateAICommentV1）

**現状**: Jaccard類似度チェックのみ（行305-342）。同一personaの重複コメントを直接防止するガードなし。コメントIDは自動採番で、`batch.commit()`で書き込み（行368-394）。
**変更**: deterministic document ID（`ai-comment-${postId}-${personaId}`）を導入し、トランザクション内で存在チェック+作成を原子化。

```typescript
// deterministic comment ID で冪等性を確保
const commentId = `ai-comment-${postId}-${persona.id}`;
const commentRef = db.collection("comments").doc(commentId);

await db.runTransaction(async (tx) => {
  const existing = await tx.get(commentRef);
  if (existing.exists) return; // 既にあればスキップ（並行リトライ安全）

  tx.set(commentRef, {
    postId,
    userId: persona.id,
    text: commentText,
    isAI: true,
    // ... その他フィールド
  });
  tx.update(postRef, { commentCount: FieldValue.increment(1) });

  // リアクションもトランザクション内で作成
  const reactionRef = db.collection("reactions").doc(`ai-reaction-${postId}-${persona.id}`);
  tx.set(reactionRef, { ... });
  tx.update(postRef, { [`reactions.${reactionType}`]: FieldValue.increment(1) });
});
```

**連鎖影響への効果**: トランザクション内でコメント+リアクション+カウンタを原子的に作成。並行リトライが来ても`existing.exists`で安全にスキップされ、下流の連鎖的重複もすべて防止される。

#### AIリアクション生成（generateAIReactionV1）

**現状**: 存在チェックあり（行428-439）だが、チェックと作成の間にレース条件あり。auto-IDドキュメントのため、クエリベースのトランザクションでは並行実行時に別ドキュメントが作成される余地がある。
**変更**: AIコメントと同様にdeterministic document ID（`ai-reaction-${postId}-${personaId}`）を導入し、トランザクション内で存在チェック+作成を原子化。

```typescript
// deterministic reaction ID で冪等性を確保（AIコメントと同じパターン）
const reactionId = `ai-reaction-${postId}-${persona.id}`;
const reactionRef = db.collection("reactions").doc(reactionId);

await db.runTransaction(async (tx) => {
  const existing = await tx.get(reactionRef);
  if (existing.exists) return; // 既にあればスキップ（並行リトライ安全）

  tx.set(reactionRef, {
    postId,
    userId: persona.id,
    type: reactionType,
    isAI: true,
    // ... その他フィールド
  });
  tx.update(postRef, { [`reactions.${reactionType}`]: FieldValue.increment(1) });
});
```

**AIコメントとの一貫性**: コメント・リアクション両方がdeterministic doc ID + トランザクションで統一され、同一の冪等性パターンで保護される。

#### AI投稿生成（executeAIPostGeneration）

**現状**: `postId`は`scheduled/ai-posts.ts`で`db.collection("posts").doc().id`（ランダムUUID）として生成される（行67）。スケジューラがリトライすると新しいpostIdが生成されるため、canonical idempotency key `ai-post-{postId}` が毎回異なる値になり、冪等性が破綻する。

**変更1: postIdを業務キーベースに変更**（全producer共通）

AI投稿の全producer（`scheduled/ai-posts.ts` および `callable/ai.ts`）で同一の業務キー生成規約を使用する。

```typescript
// 共通の業務キー生成関数（helpers/ai-keys.ts に配置）
export function generateAIPostId(personaId: string, dateStr?: string): string {
  const todayStr = dateStr ?? new Date().toISOString().split("T")[0];
  return `ai-post-${personaId}-${todayStr}`;
}
```

```typescript
// scheduled/ai-posts.ts（変更前）
const postId = db.collection("posts").doc().id;  // ランダム

// scheduled/ai-posts.ts（変更後）
const postId = generateAIPostId(persona.id);
// → リトライしても同じpostIdが生成される
```

```typescript
// callable/ai.ts（変更前）行189
const postId = db.collection("posts").doc().id;  // ランダム

// callable/ai.ts（変更後）
const postId = generateAIPostId(persona.id);
// → 手動実行でも同一persona・同一日付で冪等
```

**効果**:
- 全AI投稿経路（scheduled/manual）で同じcanonical key contractに統一
- リトライ時も同じpostIdが生成されるため、Cloud Tasks名・ドキュメントID・canonical keyがすべて一致
- 同一personaの同日重複投稿を構造的に防止
- `aiPostHistory`による除外チェック（行43-48）と合わせて二重防御

**変更2: ワーカー側の冪等性チェック**（`ai-generation.ts`側）

```typescript
const postRef = db.collection("posts").doc(postId);
const existing = await postRef.get();
if (existing.exists) {
  // 投稿が既に存在 → 統計更新も含めてスキップ
  response.status(200).send("Post already exists, skipped");
  return;
}

// 投稿作成 + 統計更新をまとめて実行
await db.runTransaction(async (tx) => {
  const postSnap = await tx.get(postRef);
  if (postSnap.exists) return; // 二重チェック

  tx.set(postRef, { ... });
  tx.update(db.collection("users").doc(persona.id), {
    totalPosts: FieldValue.increment(1),
    totalPraises: FieldValue.increment(totalReactions),
  });
});
```

**Canonical Idempotency Keyの整合**: AI投稿のキーは `ai-post-{personaId}-{yyyyMMdd}` となり、postId自体が業務キーベースとなるため、全層で一貫したキーとして機能する。

### 対策3: Producer側のdeterministic persona選択

**変更ファイル**: `functions/src/triggers/posts.ts`

**現状**（行228-235）:
```typescript
const reactionCount = Math.floor(Math.random() * 6) + 5; // 5-10
for (let i = 0; i < reactionCount; i++) {
  const persona = AI_PERSONAS[Math.floor(Math.random() * AI_PERSONAS.length)];
  // → 同一personaが複数回選ばれる可能性あり
  // → リトライ時に選択persona集合が変わり、意図しない追加タスクが投入される
}
```

**問題点**:
1. `Math.random()`による重複許可選択 → 同一personaが複数回選ばれる
2. リトライ時に`Math.random()`が異なる結果を返す → persona集合が変わり、deterministic doc IDでは防げない新規タスクが投入される

**変更後**:
```typescript
import { createHash } from "crypto";

// postIdをシードにしたdeterministic shuffle（リトライ間で結果が同一）
function deterministicShuffle<T>(items: T[], seed: string): T[] {
  const hashed = items.map((item, index) => {
    const hash = createHash("sha256")
      .update(`${seed}-${index}`)
      .digest("hex");
    return { item, hash };
  });
  hashed.sort((a, b) => a.hash.localeCompare(b.hash));
  return hashed.map(h => h.item);
}

// reactionCountもpostIdから決定的に算出（リトライ間で変わらない）
const countHash = createHash("sha256").update(`${postId}-reaction-count`).digest();
const reactionCount = Math.min(
  (countHash[0] % 6) + 5,  // 5-10の範囲でdeterministic
  AI_PERSONAS.length
);

const shuffled = deterministicShuffle(AI_PERSONAS, postId);
const selectedForReaction = shuffled.slice(0, reactionCount);

for (const persona of selectedForReaction) {
  // リトライしても同一のpersona集合に対してタスク投入
}
```

**効果**:
- **重複除外**: shuffle+sliceにより同一personaの重複選択を防止
- **リトライ安全性**: postIdをシードにしたdeterministic shuffleにより、リトライ時も同一のpersona集合が選択される。ワーカー側のdeterministic doc ID（対策2）と合わせて二重防御
- **reactionCountの決定性**: 件数もpostIdから決定的に算出し、リトライ間で変わらない

**AIコメントのpersona選択にも同様に適用**:
AIコメント生成（行195-223）のpersona選択にも同じ`deterministicShuffle`を適用し、リトライ間で選択persona集合が変わらないことを保証する。

### 対策4: 通知の重複送信防止

**変更ファイル**: `functions/src/triggers/notifications.ts`, `functions/src/helpers/notification.ts`

#### 4a: 通知ドキュメントにdeterministic IDを使用

**適用範囲**: AI系+コメント/リアクション通知のみ（`sendPushNotification`経由の通知）。サークル更新通知等の`notifications.add()`を直接呼ぶ経路は本対策のスコープ外とし、将来の通知ヘルパー統一時に対応する。

**現状**: 通知ドキュメントのIDは自動生成。上流トリガーのリトライで同一イベントに対して別IDの通知ドキュメントが作成される。

**変更**: `sendPushNotification`に`sourceId`引数を追加し、イベント固有IDに基づくdeterministic通知IDを生成。

```typescript
// helpers/notification.ts - sendPushNotification に sourceId 引数を追加
export async function sendPushNotification(
  recipientId: string,
  type: string,
  sourceId: string,  // イベント固有ID（commentId / reactionId 等）
  title: string,
  body: string,
  data?: Record<string, unknown>
): Promise<void> {
  const notificationId = `${type}-${sourceId}-${recipientId}`;
  // 例: "comment-commentId123-user456", "reaction-reactionId789-user456"
  //   ※ sourceId は postId ではなく commentId/reactionId を使用
  //   （同一投稿への別コメント/リアクションは別通知として正しく作成される）

  const notifRef = db.collection("users").doc(recipientId)
    .collection("notifications").doc(notificationId);

  // create-only: 既存ドキュメントがある場合は何もしない（pushStatusの巻き戻し防止）
  const existing = await notifRef.get();
  if (existing.exists) return; // リトライ時: 既に通知済みなのでスキップ

  // 新規作成時のみ書き込み（pushStatusの初期値はtrigger側が管理）
  await notifRef.set({
    ...notificationData,
    canonicalIdempotencyKey: data?.idempotencyKey ?? null,
    // pushStatus は含めない → onDocumentCreated trigger が pending を初期設定
  });
  // onDocumentCreated が発火 → trigger側でpushStatus管理を開始
}
```

**sourceId の指定ルール**:
| 通知種別 | sourceId | 例 |
|---------|----------|-----|
| コメント通知 | commentId | `comment-abc123-user456` |
| リアクション通知 | reactionId | `reaction-def789-user456` |
| フォロー通知 | followerId | `follow-ghi012-user456` |

**効果**: 同一イベント（同じコメント/リアクション）に対する通知が1ドキュメントに集約。上流リトライでも重複通知ドキュメントが作られない。同一投稿への別コメント/リアクションは別IDで正しく通知される。

**S1対象外の通知producer一覧（direct writer）**:

以下の経路は`sendPushNotification`を経由せず`notifications.add()`または auto-ID `.doc().set()`で通知を作成している。これらはCallable関数からのユーザー操作起因であり、Cloud Functionsのイベントリトライとは異なるため重複リスクは低い。将来の通知ヘルパー統一時に対応する。

| ファイル | 関数 | 通知パターン |
|---------|------|------------|
| `callable/circles.ts` | `deleteCircle` | `.add()` |
| `callable/circles.ts` | `approveJoinRequest` | `.add()` |
| `callable/circles.ts` | `rejectJoinRequest` | `.add()` |
| `callable/circles.ts` | `sendJoinRequest` | `.add()` |
| `callable/reports.ts` | `reportContent` | `.add()` x2 |
| `callable/inquiries.ts` | `createInquiry` | `.add()` |
| `callable/inquiries.ts` | `sendInquiryMessage` | `.add()` |
| `callable/inquiries.ts` | `sendInquiryReply` | `.add()` |
| `callable/inquiries.ts` | `updateInquiryStatus` | `.add()` |
| `callable/posts.ts` | `createPostWithModeration` | `.add()` |
| `callable/comments.ts` | `likeCommentAsPostOwner` | `.doc().set()` (tx内) |
| `callable/admin.ts` | `banUser` | `.doc().set()` |
| `callable/admin.ts` | `permanentBanUser` | `.doc().set()` |
| `callable/admin.ts` | `unbanUser` | `.doc().set()` |
| `callable/admin.ts` | `adminDeletePostWithPenalty` | `.doc().set()` |
| `triggers/circles.ts` | `onCircleUpdated` | `.add()` |
| `scheduled/circles.ts` | `checkGhostCircles` | `.add()` x2 |
| `scheduled/cleanup.ts` | `sendDeletionWarning` | `.add()` |

#### 4b: pushStatus 5状態管理 + CAS

**現状**: `sendPushOnly()`がFCMエラーをcatchしてログ出力のみ（行68-82）。送信成功/失敗に関わらずステータスが不明。並行実行時にFCM二重送信の可能性。

**変更**: `pushStatus`を5状態（pending/skipped/sending/sent/failed）に変更し、CAS（Compare-And-Set）で送信権を排他的に獲得。`sendPushOnly()`がエラーを適切に返す。

```typescript
// helpers/notification.ts
type SendPushResult =
  | { outcome: "sent" }
  | { outcome: "skipped"; skippedReason: string }
  | { outcome: "failed" };

export async function sendPushOnly(
  userId: string, title: string, body: string,
  data?: Record<string, unknown>
): Promise<SendPushResult> {
  // FCMトークンの存在チェック（CAS後のレースに対応）
  const userDoc = await db.collection("users").doc(userId).get();
  const fcmToken = userDoc.data()?.fcmToken;
  if (!fcmToken) {
    console.info(`No FCM token for user ${userId}, skipping push`);
    return { outcome: "skipped", skippedReason: "missing_fcm_token" };
  }

  try {
    // ... FCM送信処理 ...
    await admin.messaging().send(message);
    return { outcome: "sent" };
  } catch (error: unknown) {
    // 無効トークン処理（既存ロジック維持）
    if (error && typeof error === "object" && "code" in error) {
      const firebaseError = error as { code: string };
      if (
        firebaseError.code === "messaging/invalid-registration-token" ||
        firebaseError.code === "messaging/registration-token-not-registered"
      ) {
        await db.collection("users").doc(userId).update({
          fcmToken: FieldValue.delete(),
        });
        return { outcome: "skipped", skippedReason: "invalid_fcm_token" };
      }
    }
    console.error(`Error sending push notification to ${userId}:`, error);
    return { outcome: "failed" };
  }
}
```

```typescript
// triggers/notifications.ts
// pushStatus の所有権は trigger が単独で持つ（helper は pushStatus を書き込まない）
export const onNotificationCreated = onDocumentCreated(
  "users/{userId}/notifications/{notificationId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const notifRef = event.data.ref;

    // === 単一トランザクションで初期化+skipped判定+CASを原子的に実行 ===
    // pushStatus が未設定 or "pending" の場合のみ処理を進める（状態の巻き戻し防止）
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    const skipReason = getSkipReason(userData, data);

    const acquired = await db.runTransaction(async (tx) => {
      const freshSnap = await tx.get(notifRef);
      const freshData = freshSnap.data();
      if (!freshData) return false;

      const currentStatus = freshData.pushStatus;

      // 既に終端状態（sent/failed/skipped/sending）→ 何もしない（巻き戻し防止）
      if (currentStatus && currentStatus !== "pending") {
        return false;
      }

      // skipped 判定（CAS取得前）
      if (skipReason) {
        tx.update(notifRef, {
          pushStatus: "skipped",
          pushSkippedReason: skipReason,
          pushStatusUpdatedAt: FieldValue.serverTimestamp(),
        });
        return false; // skipped は送信しない
      }

      // CAS: pending（または未設定）→ sending に遷移
      tx.update(notifRef, { pushStatus: "sending" });
      return true;
    });

    if (!acquired) return; // 送信権を獲得できなかった or skipped

    // FCM送信（送信権を獲得した1実行のみがここに到達）
    const result = await sendPushOnly(userId, title, body, pushData);

    // 送信結果に応じてステータス更新（missing_fcm_tokenも区別可能）
    if (result.outcome === "skipped") {
      await notifRef.update({
        pushStatus: "skipped",
        pushSkippedReason: result.skippedReason ?? "unknown",
        pushStatusUpdatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      await notifRef.update({
        pushStatus: result.outcome, // "sent" or "failed"
        pushStatusUpdatedAt: FieldValue.serverTimestamp(),
      });
    }
  }
);
```

**pushStatus の5状態管理**:
```
未設定 or pending（ドキュメント作成直後）
  ├─→ skipped（通知不要: pre-CAS判定 or post-CASトークンレース）
  └─→ sending（CASで送信権獲得）
        ├─→ sent（FCM送信成功）
        ├─→ skipped（FCMトークン不在/無効 — post-CASレース）
        └─→ failed（FCMエラー）
```

**各状態の意味**:
| 状態 | 意味 | 遷移条件 |
|------|------|---------|
| 未設定/`pending` | 未処理（triggerが処理対象とする前提状態） | 通知ドキュメント作成時。triggerは`pushStatus`が未設定または`pending`の場合のみ処理を進める |
| `skipped` | 送信不要（正常終端） | **pre-CAS**: pushPolicy=never / 通知設定無効 / ユーザー未存在 / タイトル・本文欠落 / FCMトークン未登録。**post-CAS**: FCMトークンが送信時に不在(`missing_fcm_token`)または無効(`invalid_fcm_token`) |
| `sending` | 送信権獲得済み、FCM送信中 | CASで未設定/`pending` → `sending`に遷移成功 |
| `sent` | FCM送信成功 | `sendPushOnly()`が`{ outcome: "sent" }`を返した |
| `failed` | FCM送信失敗（記録・監視用） | `sendPushOnly()`が`{ outcome: "failed" }`を返した |

**pushSkippedReason の値一覧**:
| reason | 条件 |
|--------|------|
| `push_policy_never` | ユーザーのpushPolicy設定がnever |
| `comment_notification_disabled` | コメント通知が無効 |
| `reaction_notification_disabled` | リアクション通知が無効 |
| `user_not_found` | ユーザードキュメントが存在しない |
| `missing_title_or_body` | 通知タイトルまたは本文が欠落 |
| `missing_fcm_token` | FCMトークンが未登録（プッシュ通知拒否またはアンインストール） |
| `invalid_fcm_token` | FCMトークンが無効（送信試行後にFirebaseから拒否。トークンは自動削除） |

**CAS対象**: 未設定/`pending` → `sending` のみ。`skipped`への遷移は2箇所で発生:
1. **pre-CAS（トランザクション内）**: 通知設定・ユーザー状態チェックで送信不要と判定
2. **post-CAS（sendPushOnly内）**: CAS取得後にFCMトークンが不在/無効と判明した場合

**pushStatus の所有権ルール**:
- **trigger（`onNotificationCreated`）が唯一の所有者**。pushStatusの初期設定・全遷移を管理する
- **helper（`sendPushNotification`）はpushStatusを書き込まない**。通知ドキュメントの作成（identity/correlationフィールド）のみを担当し、既存ドキュメントがある場合は何もしない（create-only）
- これにより、リトライ時にhelperが既に`sent`/`skipped`になった通知の状態を`pending`に巻き戻すことを防止

**並行実行への耐性**: `onDocumentCreated`が同一イベントで並行に2回処理されても、トランザクションのCASで`pending → sending`に遷移できるのは1実行だけ。もう一方は`acquired = false`でスキップされ、FCM二重送信を防止する。

**注意**: `failed`は記録・監視用のステータス。`onDocumentCreated`は更新では再発火せず、`sendPushOnly()`が`success: false`を返すと関数は正常終了するため、自動再送は発生しない。再送が必要になった場合は、`failed`通知を拾う専用スケジューラの追加を将来検討する。`skipped`と`failed`の区別により、運用時に「送らなかった（正常）」と「送れなかった（異常）」を明確に識別できる。

---

## 変更ファイル一覧

| ファイル | 変更内容 |
|---------|---------|
| `functions/src/helpers/ai-keys.ts` | **新規**: `generateAIPostId()` / `deterministicShuffle()` 共通ヘルパー |
| `functions/src/helpers/cloud-tasks.ts` | Task ID パラメータ追加、deterministic ID 生成、ALREADY_EXISTS ハンドリング |
| `functions/src/triggers/posts.ts` | タスク投入時に Task ID を指定 + deterministic persona選択（postIdシード） |
| `functions/src/callable/ai.ts` | タスク投入時に Task ID を指定 + postIdを業務キーベース（`generateAIPostId`）に変更 |
| `functions/src/scheduled/ai-posts.ts` | `CloudTasksClient`直呼びを`scheduleHttpTask`に統一 + Task ID を指定 + postIdを業務キーベース（`ai-post-{personaId}-{yyyyMMdd}`）に変更 |
| `functions/src/http/ai-generation.ts` | AIコメント/リアクション/投稿の冪等性チェック追加（deterministic doc ID + トランザクション） |
| `functions/src/triggers/notifications.ts` | pushStatus 5状態管理（pending/skipped/sending/sent/failed） + CAS |
| `functions/src/helpers/notification.ts` | deterministic 通知ID + canonicalIdempotencyKeyフィールド追加 + create-only書き込み（pushStatusはtrigger管理） + sendPushOnly戻り値変更 |

---

## リスクと注意点

1. **Cloud Tasks の Task ID 制約**: 完了済みタスクと同名のタスクは7日間作成不可。AI投稿の削除→再生成が7日以内にブロックされる可能性があるが、AI投稿は運営による手動削除以外で削除されず、一般AI投稿は現在機能停止中のため実運用上のリスクは極めて低い。将来的に再生成が必要になった場合はTask IDプレフィックスの分離等で対処する
2. **Firestoreトランザクション**: リアクション・投稿の冪等化でトランザクションを使うため、書き込み競合時のリトライ回数に注意
3. **既存データへの影響**: なし（新規処理のガードのみ追加、既存データに変更なし）
4. **デプロイ順序**: Cloud Tasks のTask ID変更はワーカー側と同時にデプロイする必要あり
5. **sendPushOnly戻り値変更**: 戻り値を`SendPushResult`（`sent`/`skipped`/`failed`）に拡張。既存の呼び出し箇所で戻り値を使っていないため、後方互換性に問題なし。CAS後にFCMトークンが消えた場合も`skipped`+`missing_fcm_token`として正確に分類される
6. **deterministic通知ID**: helperはcreate-only（既存ドキュメントがあれば書き込みスキップ）。pushStatusの管理はtriggerが単独で所有するため、リトライ時にユーザーの既読状態やpushStatusが巻き戻ることはない

---

## テスト計画

- [ ] AIコメント生成を同一 postId+aiUserId で2回呼び出し → 2回目がスキップされることを確認
- [ ] AIリアクション生成を同一 postId+aiUserId で2回呼び出し → 2回目がスキップされることを確認
- [ ] AI投稿生成を同一 postId で2回呼び出し → 2回目がスキップ、totalPosts が1回のみ加算されることを確認
- [ ] AIリアクションのpersona選択 → 同一persona が重複選択されないことを確認
- [ ] 通知トリガーを同一 notificationId で2回発火 → FCMが1回のみ送信されることを確認
- [ ] 通知作成を同一イベントで2回実行 → 同一IDで1ドキュメントのみ作成されることを確認
- [ ] FCM送信失敗時 → pushStatus が "failed" に設定されることを確認
- [ ] FCMトークン未登録ユーザーへの通知 → pushStatus が "skipped"、pushSkippedReason が "missing_fcm_token" になることを確認
- [ ] pushPolicy=neverのユーザーへの通知 → pushStatus が "skipped"、pushSkippedReason が "push_policy_never" になることを確認
- [ ] 通知が sent/skipped 後にリトライ発生 → helperのcreate-onlyガードで再書き込みされないことを確認
- [ ] Cloud Tasks に同一 Task ID で2回投入 → エラーハンドリングで安全にスキップされることを確認
- [ ] 正常系: 投稿作成 → AIコメント・リアクションが正常に生成されることを確認

---

## Codexレビュー履歴

- **第1回レビュー（2026-03-11）**: 6件blocking → 全件修正対応
- **第2回レビュー（2026-03-11）**: 3件blocking + 1件major → 全件修正対応
  - 2-1: 通知ID `sourceId` を `commentId`/`reactionId` に変更（`postId`では別通知が潰れる）
  - 2-2: AIコメントにdeterministic doc ID + トランザクション導入（レース条件解消）
  - 2-3: `pushStatus=failed` の再送は要件外と明記（「リトライ時」表現を削除）
  - 2-4: 通知冪等化の適用範囲をAI系+コメント/リアクションに限定と明記
  - 追加: `triggers/circles.ts` をCloud Tasks投入経路から削除（実コードで非該当）
- **第3回レビュー（2026-03-12）**: 2件blocking + 1件major → 全件修正対応
  - A1: S1対象スコープをAI系に限定と明記、非対象Cloud Tasks経路を列挙
  - A2: 通知の非対象producer一覧（18箇所）を設計書に追記
  - A3: `scheduleHttpTask`にALREADY_EXISTSハンドリング契約を追加
  - 追加: `scheduled/ai-posts.ts`の直呼びを`scheduleHttpTask`に統一する方針を明記
- **第4回レビュー（2026-03-12）**: 2件blocking + 1件major → 全件修正対応
  - ARCH-01: AIリアクションにdeterministic doc ID（`ai-reaction-${postId}-${personaId}`）を導入
  - ARCH-02: 通知送信にCAS（`pending → sending`）を導入し並行実行時のFCM二重送信を防止
  - ARCH-03: Canonical Idempotency Keyセクションを新設、全層でエンドツーエンドのキー伝搬設計を追加
- **第5回レビュー（2026-03-12）**: 1件blocking + 1件major → 全件修正対応
  - ARCH-04: Producer側persona選択をpostIdシードのdeterministic shuffleに変更（リトライ間で結果同一）
  - ARCH-05: AI投稿のpostIdを業務キーベース（`ai-post-{personaId}-{yyyyMMdd}`）に変更（リトライで別キー問題を解消）
- 詳細: [レビュードキュメント](../reviews/2026-03-11_S1_idempotency_design_review.md)

---

## 次のアクション担当者

レビュワー → 修正後の再レビュー → ユーザー → 設計承認後、実行者が実装に着手
