# リアクション機能の問題と解決策

## 概要

リアクション機能における既知の問題と、その解決策をまとめた設計書。

---

## 問題1: アニメーションちらつき問題

### 現象

リアクション追加時のアニメーション（大きく表示→小さくなる）を**全ユーザーに表示**しようとすると、タイムラインがちらつく。

### 原因

1. Firestoreのリアルタイム更新で`reactions`マップが変更される
2. `PostCard`全体が再ビルドされる
3. `ReactionBackground`の`didUpdateWidget`が発火
4. アニメーションが再トリガーされる
5. 他のユーザーから見ると意図しないタイミングでアニメーションが発生

### 現状の対応（暫定）

**リアクション追加者のみにアニメーションを表示**

```dart
// reaction_button.dart
if (!_isReacted) {
  _controller.reset();
  _controller.forward(); // 追加者のみアニメーション
}
```

### 根本解決案

| 案 | 内容 | 工数 | リスク |
|----|------|------|--------|
| **A. Overlay使用** | アニメーションをOverlayで描画し、投稿カードとは独立させる | 中 | 位置計算が複雑 |
| **B. ローカルステート分離** ✅ | アニメーション用のローカル状態を持ち、Firestore更新と分離 | 中 | 状態管理が複雑化 |
| ~~C. 現状維持~~ | 追加者のみアニメーション表示で妥協 | - | UX上の妥協 |

### 推奨

**B案で解決（2025-12-21）**：
- `PostCard`に`_localReactions`を追加してローカル状態を管理
- `ReactionBackground`はローカル状態を参照
- リアクション追加時はコールバックでローカル更新 → Firestoreはバックグラウンド更新
- これにより、追加者のみにアニメーションが表示され、他ユーザーへのちらつきなし

---

## 問題2: リアクション削除時のデータ不整合

### 現象

リアクション削除時、`reactions`コレクションからドキュメントを削除せず、`posts`の`reactions`カウントのみ減算している。

### 現状のコード

```dart
// reaction_button.dart (93-101行)
} else {
  // リアクション削除: 直接Firestoreを更新（カウントのみ）
  final postRef = FirebaseFirestore.instance
      .collection('posts')
      .doc(widget.postId);

  await postRef.update({
    'reactions.${widget.type.value}': FieldValue.increment(-1),
  });
}
```

### 問題点

1. **データ不整合**: `reactions`コレクションにドキュメントが残る
2. **回数制限の誤動作**: 削除後も`reactions`コレクションにカウントされ、5回制限に達しやすい
3. **通知の重複リスク**: `onReactionAddedNotify`トリガーが不正確になる可能性

### 解決策

#### A案: Cloud Functions経由で削除（推奨）

```typescript
// functions/src/index.ts
export const removeUserReaction = onCall(
  { region: "asia-northeast1" },
  async (request) => {
    const { postId, reactionType } = request.data;
    const userId = request.auth?.uid;

    if (!userId) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }

    const batch = db.batch();

    // 1. reactionsコレクションから削除
    const reactionQuery = await db.collection("reactions")
      .where("postId", "==", postId)
      .where("userId", "==", userId)
      .where("reactionType", "==", reactionType)
      .limit(1)
      .get();

    if (!reactionQuery.empty) {
      batch.delete(reactionQuery.docs[0].ref);
    }

    // 2. postsのカウントを減算
    const postRef = db.collection("posts").doc(postId);
    batch.update(postRef, {
      [`reactions.${reactionType}`]: admin.firestore.FieldValue.increment(-1),
    });

    await batch.commit();

    return { success: true };
  }
);
```

#### B案: クライアント側でトランザクション

```dart
await FirebaseFirestore.instance.runTransaction((transaction) async {
  // reactionsコレクションから削除
  final reactionQuery = await FirebaseFirestore.instance
      .collection('reactions')
      .where('postId', isEqualTo: postId)
      .where('userId', isEqualTo: userId)
      .where('reactionType', isEqualTo: reactionType)
      .limit(1)
      .get();

  if (reactionQuery.docs.isNotEmpty) {
    transaction.delete(reactionQuery.docs.first.reference);
  }

  // カウント減算
  transaction.update(postRef, {
    'reactions.$reactionType': FieldValue.increment(-1),
  });
});
```

### 推奨

**A案（Cloud Functions経由）** を推奨。理由：

1. セキュリティルールがシンプル
2. 追加時と削除時の処理が統一される
3. 将来的に削除時にも通知やポイント処理を追加しやすい

---

## 実装優先度

| 問題 | 優先度 | 理由 |
|------|--------|------|
| アニメーションちらつき | **P3** | 現状対応済み、致命的ではない |
| リアクション削除 | **P2** | データ不整合が発生する可能性あり |

---

## 更新履歴

| 日付 | 内容 |
|------|------|
| 2025-12-20 | 初版作成 |
