# S1: Cloud Functions idempotency key 導入

**作成日**: 2026-03-11
**優先度**: P0
**ステータス**: 詳細設計中
**次のアクション担当者**: ユーザー → 設計承認

---

## 背景

Cloud Functions のトリガー・Cloud Tasks ワーカーにリトライ耐性（冪等性）がなく、再試行時に以下の副作用が二重実行される。

---

## 問題の全体像

```
onPostCreated トリガー
  ├─ Cloud Tasks タスク投入（Task ID 自動生成 → 重複タスク防止なし）
  │   ├─ generateAICommentV1  → コメント+リアクション+カウンタ二重記録
  │   └─ generateAIReactionV1 → リアクション+カウンタ二重記録（チェックあるがレース条件）
  │
  ├─ onCommentCreatedNotify → sendPushNotification → onNotificationCreated → FCM重複送信
  └─ onReactionAddedNotify  → sendPushNotification → onNotificationCreated → FCM重複送信
```

---

## 現状の問題点（コード調査結果）

| 処理 | ファイル | 重複防止 | リトライ時の副作用 |
|------|---------|---------|------------------|
| AIコメント生成 | ai-generation.ts | なし | コメント+リアクション+カウンタ二重記録 |
| AIリアクション生成 | ai-generation.ts | あり（不完全） | レース条件で重複リアクション |
| AI投稿生成 | ai-generation.ts | なし | 統計が複数回加算 |
| 通知プッシュ送信 | notifications.ts | なし | FCM重複送信 |
| コメント通知 | notifications.ts | なし | 二段階処理で重複 |
| リアクション通知 | notifications.ts | なし | 二段階処理で重複 |
| Cloud Tasks投入 | cloud-tasks.ts | Task ID未指定 | 同一タスクが複数投入可能 |

---

## 対策設計

### 方針

3つのレイヤーで冪等性を確保する：

1. **Cloud Tasks レイヤー**: deterministic Task ID で重複タスク投入を防止
2. **ワーカーレイヤー**: 処理開始時に idempotency ドキュメントで重複実行を防止
3. **通知レイヤー**: pushStatus チェックで重複FCM送信を防止

### 対策1: Cloud Tasks に deterministic Task ID を設定

**変更ファイル**: `functions/src/helpers/cloud-tasks.ts`

**現状**:
```typescript
const [response] = await client.createTask({ parent: queuePath, task });
// Task ID は自動生成
```

**変更後**:
```typescript
const [response] = await client.createTask({
  parent: queuePath,
  task: {
    name: `${queuePath}/tasks/${taskId}`,  // deterministic ID
    ...task,
  },
});
```

**Task ID の生成ルール**:
- AIコメント: `ai-comment-${postId}-${aiUserId}`
- AIリアクション: `ai-reaction-${postId}-${aiUserId}`
- AI投稿: `ai-post-${postId}`
- サークルAI投稿: `circle-ai-post-${circleId}-${aiUserId}-${date}`
- サークル削除: `circle-cleanup-${circleId}-${batchIndex}`

**効果**: 同一の投稿+AIユーザーの組み合わせでタスクが重複投入されなくなる

**注意**: Cloud Tasks は完了済みタスクと同じ名前のタスクを一定期間（最大7日間）作成できない。Task ID にタイムスタンプ等を含めるか、投入前の存在チェックを検討。

### 対策2: ワーカーに idempotency チェックを追加

**変更ファイル**: `functions/src/http/ai-generation.ts`

#### AIコメント生成（generateAICommentV1）

**現状**: コメント保存時に類似度チェックのみ。
**変更**: 処理開始時に既存コメントの存在チェックを追加。

```typescript
// 冪等性チェック: 同じAIユーザーが同じ投稿に既にコメントしていれば スキップ
const existing = await db.collection("comments")
  .where("postId", "==", postId)
  .where("userId", "==", persona.id)
  .limit(1)
  .get();

if (!existing.empty) {
  response.status(200).send("Comment already exists, skipped");
  return;
}
```

#### AIリアクション生成（generateAIReactionV1）

**現状**: 存在チェックあり、だがレース条件あり。
**変更**: Firestoreトランザクション内で存在チェック+作成を原子化。

```typescript
await db.runTransaction(async (tx) => {
  const existing = await tx.get(
    db.collection("reactions")
      .where("postId", "==", postId)
      .where("userId", "==", persona.id)
      .limit(1)
  );
  if (!existing.empty) return; // 既にあればスキップ

  tx.set(reactionRef, { ... });
  tx.update(postRef, { [`reactions.${type}`]: FieldValue.increment(1) });
});
```

#### AI投稿生成（executeAIPostGeneration）

**変更**: 投稿IDを deterministic にし、`set()` の前に存在チェック。

```typescript
const postRef = db.collection("posts").doc(postId);
const existing = await postRef.get();
if (existing.exists) {
  response.status(200).send("Post already exists, skipped");
  return;
}
```

### 対策3: 通知の重複送信防止

**変更ファイル**: `functions/src/triggers/notifications.ts`

**現状**: `onNotificationCreated` で無条件に `sendPushOnly()` を呼び出し。
**変更**: `pushStatus` フィールドをチェックし、未送信時のみ送信。

```typescript
export const onNotificationCreated = onDocumentCreated(
  "users/{userId}/notifications/{notificationId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    // 冪等性チェック: 既に送信済みなら スキップ
    if (data.pushStatus === "sent") return;

    // ... FCM送信処理 ...

    // 送信成功後にステータス更新
    await event.data.ref.update({
      pushStatus: "sent",
      pushSentAt: FieldValue.serverTimestamp(),
    });
  }
);
```

**注意**: トリガーのリトライでは同じドキュメントの初期データが渡されるため、`pushStatus` が `"sent"` に更新された後のリトライでも、トリガーに渡されるデータは作成時点のもの。そのため、**トリガー内でドキュメントを再読み込み**する必要がある。

```typescript
// リトライ安全: 最新の状態を再読み込み
const freshSnap = await event.data.ref.get();
const freshData = freshSnap.data();
if (freshData?.pushStatus === "sent") return;
```

---

## 変更ファイル一覧

| ファイル | 変更内容 |
|---------|---------|
| `functions/src/helpers/cloud-tasks.ts` | Task ID パラメータ追加、deterministic ID 生成 |
| `functions/src/triggers/posts.ts` | タスク投入時に Task ID を指定 |
| `functions/src/http/ai-generation.ts` | AIコメント/リアクション/投稿の冪等性チェック追加 |
| `functions/src/triggers/notifications.ts` | pushStatus チェックで重複FCM送信防止 |
| `functions/src/helpers/notification.ts` | 通知作成時に pushStatus 初期値設定 |

---

## リスクと注意点

1. **Cloud Tasks の Task ID 制約**: 完了済みタスクと同名のタスクは7日間作成不可。投稿削除→再投稿のケースで問題になる可能性 → Task ID に日付を含めるか検討
2. **Firestoreトランザクション**: リアクションの冪等化でトランザクションを使うため、書き込み競合時のリトライ回数に注意
3. **既存データへの影響**: なし（新規処理のガードのみ追加、既存データに変更なし）
4. **デプロイ順序**: Cloud Tasks のTask ID変更はワーカー側と同時にデプロイする必要あり

---

## テスト計画

- [ ] AIコメント生成を同一 postId+aiUserId で2回呼び出し → 2回目がスキップされることを確認
- [ ] AIリアクション生成を同一 postId+aiUserId で2回呼び出し → 2回目がスキップされることを確認
- [ ] 通知トリガーを同一 notificationId で2回発火 → FCMが1回のみ送信されることを確認
- [ ] Cloud Tasks に同一 Task ID で2回投入 → エラーハンドリングで安全にスキップされることを確認
- [ ] 正常系: 投稿作成 → AIコメント・リアクションが正常に生成されることを確認

---

## 次のアクション担当者

ユーザー → 設計承認後、実行者が実装に着手
