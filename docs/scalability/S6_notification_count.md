# S6: 通知未読カウントの非正規化 -- 詳細設計書

**作成日**: 2026-03-13
**優先度**: P1
**ステータス**: 設計中
**次のアクション担当者**: 全体管理者 (設計レビュー)

---

## 1. 現状分析

### 1.1 問題: 未読カウントの全件クエリ

`lib/shared/repositories/notification_repository.dart:50-57`:

```dart
Stream<int> getUnreadCountStream(String userId) {
  return _firestore
      .collection('users').doc(userId).collection('notifications')
      .where('isRead', isEqualTo: false)
      .snapshots()
      .map((snapshot) => snapshot.docs.length);
}
```

**問題点:**
- `where('isRead', isEqualTo: false)` + `snapshots()` で、未読通知の全ドキュメントをリアルタイム監視している
- 未読が増えるほどスナップショットリスナーが受信するドキュメント数が線形に増加
- ホーム画面のアプリバーで常時監視しているため、アプリ起動中ずっとリスナーが維持される
- カテゴリ別未読カウント（`getUnreadCountStreamByCategory`）も同じパターンで、通知画面では3つのカテゴリ分のリスナーが同時に動く
- 結果として、1ユーザーあたり最大4つの未読カウントリスナーが同時に動く可能性がある

### 1.2 コスト影響（変更前）

| 状況 | リスナー数 | 初回読み取り（未読50件の場合） | 更新時読み取り |
|------|-----------|------|------|
| ホーム画面（全体未読バッジ） | 1 | 50 reads | 変更分のみ（差分課金） |
| 通知画面（3カテゴリ別バッジ） | 3 | 最大 50 reads x 3 = 150 reads | 変更分のみ |
| 合計（通知画面表示中） | 4 | 最大 200 reads | 変更分のみ |

Firestoreのスナップショットリスナーは初回に全マッチドキュメントを読み取り、以降は差分（追加/更新/削除）のみ課金される。しかし、画面遷移のたびにリスナーが再作成されるため、初回読み取りコストが繰り返し発生する。

### 1.3 `markAllAsRead` の全件取得問題

`notification_repository.dart:87-101`:

```dart
Future<void> markAllAsRead(String userId) async {
  final snapshot = await _firestore
      .collection('users').doc(userId).collection('notifications')
      .where('isRead', isEqualTo: false)
      .get();  // 全未読を取得
  for (var doc in snapshot.docs) {
    batch.update(doc.reference, {'isRead': true});
  }
  await batch.commit();
}
```

**問題点:**
- 未読通知が多い場合、全件を取得してからバッチ更新するため、読み取りコストが高い
- Firestoreのバッチは500件上限のため、未読が500件を超えるとエラーになる
- ただし、現実的にはユーザー1人の未読通知が500件を超えることは稀（1日数件〜数十件の通知頻度）

### 1.4 通知作成パス（全22箇所）

サーバー側で通知ドキュメントが作成される箇所を網羅的に調査した結果、以下の22箇所が存在する。

**`sendPushNotification()` 経由（決定論的ID `{type}-{sourceId}-{userId}`）:**

| # | ファイル | type | カテゴリ |
|---|---------|------|---------|
| 1 | `triggers/notifications.ts:188` | comment | timeline |
| 2 | `triggers/notifications.ts:237` | reaction | timeline |

**`.add()` または `.doc()` + `.set()` で直接作成:**

| # | ファイル | type | カテゴリ |
|---|---------|------|---------|
| 3 | `callable/circles.ts:151` | circle_deleted | circle |
| 4 | `callable/circles.ts:442` | join_request_approved | circle |
| 5 | `callable/circles.ts:518` | join_request_rejected | circle |
| 6 | `callable/circles.ts:605` | join_request_received | circle |
| 7 | `callable/inquiries.ts:85` | inquiry_received | support |
| 8 | `callable/inquiries.ts:177` | inquiry_user_reply | support |
| 9 | `callable/inquiries.ts:266` | inquiry_reply | support |
| 10 | `callable/inquiries.ts:448` | inquiry_status_changed | support |
| 11 | `callable/posts.ts:414` | review_needed | support |
| 12 | `callable/reports.ts:95` | post_hidden | support |
| 13 | `callable/reports.ts:123` | admin_report | support |
| 14 | `triggers/circles.ts:207` | circle_settings_changed | circle |
| 15 | `scheduled/circles.ts:97` | circle_ghost_warning | circle |
| 16 | `scheduled/circles.ts:140` | circle_ghost_deleted | circle |
| 17 | `scheduled/cleanup.ts:438` | inquiry_deletion_warning | support |
| 18 | `callable/admin.ts:326` | user_banned | support |
| 19 | `callable/admin.ts:429` | user_banned | support |
| 20 | `callable/admin.ts:475` | user_unbanned | support |
| 21 | `callable/admin.ts:619` | post_deleted | support |
| 22 | `callable/comments.ts:677` | reaction (thanks) | timeline |

**重要な発見:** 全22箇所で通知ドキュメントが `users/{userId}/notifications` サブコレクションに作成されると、既存の `onNotificationCreated` トリガー（`triggers/notifications.ts:69`）が自動的に発火する。このトリガーを未読カウントインクリメントの統一ポイントとして活用できる。

---

## 2. 設計

### 2.1 基本方針

**「userドキュメントに未読カウントフィールドを非正規化し、通知トリガーでインクリメント、既読操作でデクリメント」**

```
[変更前]
  クライアント → snapshots() で全未読ドキュメントを監視 → .length でカウント

[変更後]
  クライアント → userドキュメントの unreadNotificationCount フィールドを監視（1ドキュメント）
  サーバー → 通知作成時にインクリメント、既読時にデクリメント
```

### 2.2 userドキュメントのフィールド設計

`users/{userId}` に以下のフィールドを追加:

```typescript
{
  // 全体の未読カウント
  unreadNotificationCount: number,  // デフォルト: 0

  // カテゴリ別の未読カウント
  unreadTimelineCount: number,      // デフォルト: 0
  unreadCircleCount: number,        // デフォルト: 0
  unreadSupportCount: number,       // デフォルト: 0
}
```

**カテゴリ別カウントを保持する理由:**
- 通知画面のタブバッジでカテゴリ別未読数を表示している
- カテゴリ別カウントがないと、カテゴリ別未読数のためだけに従来のクエリが必要になり、改善効果が半減する
- フィールド4つ追加のコストは1ドキュメント内なので無視できる

**type からカテゴリへのマッピング（サーバー側ヘルパー）:**

```typescript
// helpers/notification-category.ts (新規)
type NotificationCategory = "timeline" | "circle" | "support";

const TYPE_TO_CATEGORY: Record<string, NotificationCategory> = {
  comment: "timeline",
  reaction: "timeline",
  system: "timeline",
  join_request_received: "circle",
  join_request_approved: "circle",
  join_request_rejected: "circle",
  circle_deleted: "circle",
  circle_settings_changed: "circle",
  circle_ghost_warning: "circle",
  circle_ghost_deleted: "circle",
  inquiry_reply: "support",
  inquiry_status_changed: "support",
  inquiry_received: "support",
  inquiry_user_reply: "support",
  inquiry_deletion_warning: "support",
  admin_report: "support",
  review_needed: "support",
  post_deleted: "support",
  post_hidden: "support",
  user_banned: "support",
  user_unbanned: "support",
};

export function getNotificationCategory(type: string): NotificationCategory {
  return TYPE_TO_CATEGORY[type] ?? "support";
}
```

### 2.3 カウントインクリメント（通知作成時）

**変更対象:** `functions/src/triggers/notifications.ts` の `onNotificationCreated`

既存の `onNotificationCreated` トリガーは全通知作成時に発火するため、ここにカウントインクリメントを追加する。全22箇所の通知作成パスを個別に変更する必要がない。

```typescript
// onNotificationCreated 内、CASトランザクションの前に追加
export const onNotificationCreated = onDocumentCreated(
    {
        document: "users/{userId}/notifications/{notificationId}",
        region: LOCATION,
    },
    async (event) => {
        const snap = event.data;
        if (!snap) return;

        const data = snap.data();
        const userId = event.params.userId;
        const type = String(data?.type ?? "system");
        const isRead = data?.isRead ?? false;

        // === 未読カウントのインクリメント ===
        // isRead: false で作成された通知のみカウント
        if (!isRead) {
            const category = getNotificationCategory(type);
            const categoryField = getCategoryCountField(category);

            const userRef = db.collection("users").doc(userId);
            await userRef.update({
                unreadNotificationCount: FieldValue.increment(1),
                [categoryField]: FieldValue.increment(1),
            });
        }

        // === 以下、既存のFCM送信ロジック（変更なし）===
        // ...
    }
);

function getCategoryCountField(category: NotificationCategory): string {
    switch (category) {
        case "timeline": return "unreadTimelineCount";
        case "circle": return "unreadCircleCount";
        case "support": return "unreadSupportCount";
    }
}
```

**設計判断: トランザクション不要**
- `FieldValue.increment()` はアトミック操作であり、トランザクションなしで安全にインクリメントできる
- 複数のCloud Functionsが同時に同じユーザーの通知を作成しても、`increment()` は正しく動作する
- トランザクションを使うとレイテンシが増加し、コンテンション（競合）が発生しやすくなる

**S1冪等性との整合:**
- `sendPushNotification()` は決定論的ID（`{type}-{sourceId}-{userId}`）を使い、`existing.exists` チェックで二重作成を防止している
- 既に通知ドキュメントが存在する場合、`sendPushNotification()` は早期リターンし、`onNotificationCreated` トリガーは発火しない
- よって、S1で対策済みの通知（comment, reaction）はカウント二重インクリメントが発生しない
- `.add()` で作成される通知（circle, inquiry等）はリトライ時に二重作成される可能性があるが、これらは元々S1の対策対象外であり、発生頻度も低い（管理操作やスケジュール処理）

### 2.4 カウントデクリメント（単一既読）

**変更対象:** `lib/shared/repositories/notification_repository.dart` の `markAsRead`

クライアント側で既読にする際、サーバー側でカウントをデクリメントする必要がある。2つのアプローチを検討する。

**案A: クライアント側で直接デクリメント**

```dart
Future<void> markAsRead(String userId, String notificationId) async {
  final batch = _firestore.batch();

  // 通知を既読にする
  final notifRef = _firestore.collection('users').doc(userId)
      .collection('notifications').doc(notificationId);
  batch.update(notifRef, {'isRead': true});

  // 未読カウントをデクリメント
  final userRef = _firestore.collection('users').doc(userId);
  batch.update(userRef, {
    'unreadNotificationCount': FieldValue.increment(-1),
    // カテゴリ別デクリメントは通知のtypeを知る必要がある
  });

  await batch.commit();
}
```

**問題:** カテゴリ別デクリメントには通知のtypeが必要。`markAsRead` の呼び出し元（`_NotificationTile`）は `notification.type` を持っているため、引数で渡すことで解決可能。

**案B: Firestoreトリガーでサーバー側デクリメント（onNotificationUpdated）**

```typescript
export const onNotificationUpdated = onDocumentUpdated(
    {
        document: "users/{userId}/notifications/{notificationId}",
        region: LOCATION,
    },
    async (event) => {
        const before = event.data?.before.data();
        const after = event.data?.after.data();
        if (!before || !after) return;

        // isRead: false → true に変わった場合のみデクリメント
        if (!before.isRead && after.isRead) {
            const type = String(after.type ?? "system");
            const category = getNotificationCategory(type);
            const categoryField = getCategoryCountField(category);

            const userRef = db.collection("users").doc(event.params.userId);
            await userRef.update({
                unreadNotificationCount: FieldValue.increment(-1),
                [categoryField]: FieldValue.increment(-1),
            });
        }
    }
);
```

**採用: 案A（クライアント側デクリメント）**

理由:
- 案Bは `onDocumentUpdated` トリガーの追加が必要で、Cloud Functions呼び出しコストが発生する（通知を1つ既読にするたびにFunctions実行）
- 案Aはバッチ書き込み1回で完結し、追加のFunctions実行コストがゼロ
- `markAsRead` の呼び出し元は通知のtypeを保持しているため、カテゴリの判定が可能
- セキュリティルール上、クライアントは自分のuserドキュメントを更新可能（ただし `unreadNotificationCount` 等を保護フィールドに追加しない）

**セキュリティ上の考慮:**
- `unreadNotificationCount` をセキュリティルールの保護フィールドに追加しない
  - 追加すると、クライアントからのデクリメントができなくなる
  - このフィールドは表示用であり、不正な値を設定されても深刻なセキュリティリスクはない
  - 仮にクライアントが不正にカウントを操作しても、影響はそのユーザー自身のバッジ表示のみ

### 2.5 全件一括既読

**変更対象:** `notification_repository.dart` の `markAllAsRead`

```dart
Future<void> markAllAsRead(String userId) async {
  final batch = _firestore.batch();
  final snapshot = await _firestore
      .collection('users').doc(userId).collection('notifications')
      .where('isRead', isEqualTo: false)
      .get();

  for (var doc in snapshot.docs) {
    batch.update(doc.reference, {'isRead': true});
  }

  // 未読カウントを全リセット（0にセット）
  final userRef = _firestore.collection('users').doc(userId);
  batch.update(userRef, {
    'unreadNotificationCount': 0,
    'unreadTimelineCount': 0,
    'unreadCircleCount': 0,
    'unreadSupportCount': 0,
  });

  await batch.commit();
}
```

**設計判断: `increment(-N)` ではなく直接 `0` をセット**
- 全件既読なので、カウントは確実に0になる
- `increment(-N)` だと、バッチ実行中に新しい通知が来た場合にカウントがずれる可能性があるが、0セットでも同じ問題がある
- しかし、0セット後に新しい通知が来ると `onNotificationCreated` で再びインクリメントされるため、実際には問題ない
- 0セットの方がシンプルで確実

### 2.6 クライアント側の変更

#### 2.6.1 NotificationRepository の変更

```dart
class NotificationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 未読件数を取得するストリーム（全体）
  // 変更: snapshots() クエリ → userドキュメントの1フィールド監視
  Stream<int> getUnreadCountStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          return (data?['unreadNotificationCount'] as int?) ?? 0;
        });
  }

  // カテゴリ別の未読件数を取得するストリーム
  // 変更: snapshots() クエリ → userドキュメントの1フィールド監視
  Stream<int> getUnreadCountStreamByCategory(
    String userId,
    NotificationCategory category,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          final field = _getCategoryCountField(category);
          return (data?[field] as int?) ?? 0;
        });
  }

  String _getCategoryCountField(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.timeline:
        return 'unreadTimelineCount';
      case NotificationCategory.circle:
        return 'unreadCircleCount';
      case NotificationCategory.support:
        return 'unreadSupportCount';
    }
  }

  // 通知を既読にする
  // 変更: カウントデクリメントを追加、typeパラメータ追加
  Future<void> markAsRead(
    String userId,
    String notificationId,
    NotificationType type,
  ) async {
    final batch = _firestore.batch();

    final notifRef = _firestore.collection('users').doc(userId)
        .collection('notifications').doc(notificationId);
    batch.update(notifRef, {'isRead': true});

    final userRef = _firestore.collection('users').doc(userId);
    final category = getCategoryFromType(type);
    final categoryField = _getCategoryCountField(category);
    batch.update(userRef, {
      'unreadNotificationCount': FieldValue.increment(-1),
      categoryField: FieldValue.increment(-1),
    });

    await batch.commit();
  }

  // 全て既読にする（変更なし、カウントリセット追加）
  Future<void> markAllAsRead(String userId) async {
    final batch = _firestore.batch();
    final snapshot = await _firestore
        .collection('users').doc(userId).collection('notifications')
        .where('isRead', isEqualTo: false)
        .get();

    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    final userRef = _firestore.collection('users').doc(userId);
    batch.update(userRef, {
      'unreadNotificationCount': 0,
      'unreadTimelineCount': 0,
      'unreadCircleCount': 0,
      'unreadSupportCount': 0,
    });

    await batch.commit();
  }

  // 以下、既存メソッドは変更なし
  // getNotificationsStream, getNotificationsStreamByCategory,
  // _getNotificationTypesForCategory
}
```

#### 2.6.2 通知画面の `markAsRead` 呼び出し変更

`notifications_screen.dart` の `_NotificationTile` で `markAsRead` の呼び出しにtypeを追加:

```dart
// 変更前
await ref.read(notificationRepositoryProvider)
    .markAsRead(user.uid, notification.id);

// 変更後
await ref.read(notificationRepositoryProvider)
    .markAsRead(user.uid, notification.id, notification.type);
```

#### 2.6.3 リスナーの最適化

**現状の問題:** `getUnreadCountStream` と `getUnreadCountStreamByCategory` の4つのストリームが、全て同じ `users/{userId}` ドキュメントの `snapshots()` を呼ぶ。Firestoreクライアントは内部的にリスナーを重複排除するため、4つのストリームが同時に存在しても、Firestore側では1つのドキュメントリスナーとして処理される。追加の最適化は不要。

### 2.7 カウント修正スクリプト（運用ツール）

カウントのドリフト（不整合）が発生した場合に備え、管理者向けのカウント再計算Cloud Functionを用意する。

```typescript
// callable/admin.ts に追加
export const recalculateUnreadCounts = onCall(
    { region: LOCATION, timeoutSeconds: 300, enforceAppCheck: true },
    async (request) => {
        const callerId = requireAuth(request);
        const callerIsAdmin = await isAdmin(callerId);
        if (!callerIsAdmin) {
            throw new HttpsError("permission-denied", AUTH_ERRORS.ADMIN_REQUIRED);
        }

        const { targetUserId } = request.data;

        // 特定ユーザーまたは全ユーザーの再計算
        const userIds: string[] = [];
        if (targetUserId) {
            userIds.push(targetUserId);
        } else {
            // 全ユーザー（ページネーション付き）
            // 省略: 実運用ではバッチ処理
        }

        let updatedCount = 0;
        for (const userId of userIds) {
            const notifSnapshot = await db.collection("users").doc(userId)
                .collection("notifications")
                .where("isRead", "==", false)
                .get();

            let timelineCount = 0;
            let circleCount = 0;
            let supportCount = 0;

            for (const doc of notifSnapshot.docs) {
                const type = String(doc.data().type ?? "system");
                const category = getNotificationCategory(type);
                switch (category) {
                    case "timeline": timelineCount++; break;
                    case "circle": circleCount++; break;
                    case "support": supportCount++; break;
                }
            }

            await db.collection("users").doc(userId).update({
                unreadNotificationCount: timelineCount + circleCount + supportCount,
                unreadTimelineCount: timelineCount,
                unreadCircleCount: circleCount,
                unreadSupportCount: supportCount,
            });
            updatedCount++;
        }

        return { success: true, updatedCount };
    }
);
```

---

## 3. セキュリティ考慮

### 3.1 Firestoreセキュリティルール

`unreadNotificationCount`, `unreadTimelineCount`, `unreadCircleCount`, `unreadSupportCount` は**保護フィールドリストに追加しない**。

理由:
- クライアント側の `markAsRead` / `markAllAsRead` でデクリメント/リセットする必要がある
- これらのフィールドは表示用であり、不正操作されてもセキュリティリスクはない（影響はそのユーザー自身のバッジ表示のみ）
- カウントのインクリメントはサーバー側トリガーが担い、クライアントからは `FieldValue.increment(-1)` または `0` のセットのみ

### 3.2 カウント不整合のリスクと対策

| リスク | 発生シナリオ | 影響 | 対策 |
|--------|------------|------|------|
| カウントが負数になる | 既読操作とカウントリセットの競合 | バッジに負数が表示される | クライアント側で `max(0, count)` をガード |
| カウントが実際より多い | 通知削除時のデクリメント漏れ | バッジが消えない | 管理者向け再計算スクリプト |
| カウントが実際より少ない | インクリメント失敗 | 未読があるのにバッジが出ない | `onNotificationCreated` の失敗はリトライされる |

**クライアント側のガード:**

```dart
.map((snapshot) {
  final data = snapshot.data();
  final count = (data?['unreadNotificationCount'] as int?) ?? 0;
  return count < 0 ? 0 : count;  // 負数ガード
});
```

### 3.3 通知削除時のカウント整合

現在のセキュリティルールでは、通知の `delete` はクライアントに許可されている（`allow read, update, delete: if isAuthenticated() && isOwner(userId)`）。

ただし、現行コードには通知を削除する機能は実装されていない（UIに削除ボタンがない）。将来的に通知削除機能を追加する場合は、削除時に `isRead` を確認してカウントをデクリメントする必要がある。

現時点では対応不要。

---

## 4. コスト影響分析

### 4.1 読み取りコスト比較

| 状況 | 変更前 | 変更後 | 削減 |
|------|--------|--------|------|
| ホーム画面初回表示（未読50件） | 50 reads (未読ドキュメント全件) | 1 read (userドキュメント) | -49 reads (98%削減) |
| 通知画面初回表示（未読50件、3カテゴリ） | 最大 150 reads | 0 reads (userドキュメントは既にキャッシュ済み) | -150 reads (100%削減) |
| 画面遷移のたびの再リスナー | 未読件数分のreads | 0 reads (同一ドキュメントのリスナーは共有される) | 100%削減 |

**注:** userドキュメントは認証・プロフィール表示などで既にリスナーが張られている可能性が高い。その場合、未読カウント用の追加リスナーはFirestoreクライアントの重複排除により追加読み取りが発生しない。

### 4.2 書き込みコスト比較

| 操作 | 変更前 | 変更後 | 差分 |
|------|--------|--------|------|
| 通知作成 | 1 write (通知ドキュメント) | 1 write (通知) + 1 write (userカウント) | +1 write |
| 単一既読 | 1 write (通知ドキュメント) | 1 batch write (通知 + userカウント) | +1 write |
| 全件既読（50件） | 50 reads + 50 writes | 50 reads + 50 writes + 1 write | +1 write |

### 4.3 Cloud Functions実行コスト

| 変更 | 影響 |
|------|------|
| `onNotificationCreated` にインクリメント処理追加 | 既存トリガーに1行の `update()` を追加するだけ。新たなFunctionsインスタンスは不要。実行時間は微増（1 Firestore write追加） |
| `onDocumentUpdated` トリガー | **追加しない（案A採用）**。追加コストゼロ |

### 4.4 総合評価

- **読み取り:** 大幅削減（ユーザー1人あたり、画面表示のたびに数十〜百reads以上の削減）
- **書き込み:** 微増（通知1件あたり+1 write、既読1回あたり+1 write）
- **Functions実行:** 変更なし
- **結論:** 読み取り削減効果 >> 書き込み増加コスト。コスト面でプラス。

---

## 5. マイグレーション計画

### 5.1 段階的デプロイ

**ステップ1: サーバー側デプロイ（Cloud Functions）**

1. `helpers/notification-category.ts` を新規作成（カテゴリマッピング）
2. `triggers/notifications.ts` の `onNotificationCreated` にインクリメント処理を追加
3. `callable/admin.ts` に `recalculateUnreadCounts` を追加
4. Cloud Functionsをデプロイ

この時点で、新しく作成される通知からカウントが正しくインクリメントされる。ただし既存の未読通知のカウントは0のまま。

**ステップ2: 既存データのバックフィル**

`recalculateUnreadCounts` を管理者として実行し、全ユーザーのカウントを正しい値に初期化する。

```
// Firebaseコンソールまたは管理画面から実行
recalculateUnreadCounts({ targetUserId: null })  // 全ユーザー
```

**ステップ3: クライアント側デプロイ（Flutter）**

1. `notification_repository.dart` のストリームをフィールド監視に変更
2. `markAsRead` にtypeパラメータとデクリメント処理を追加
3. `markAllAsRead` にカウントリセットを追加
4. `notifications_screen.dart` の `markAsRead` 呼び出しを更新
5. アプリをリリース

### 5.2 後方互換性

**旧クライアント（変更前のアプリ）:**
- `markAsRead` はデクリメントしないが、未読カウント表示は旧方式（snapshots クエリ）のまま動作する
- カウントフィールドが実態とずれるが、旧アプリはそのフィールドを参照しない

**新クライアント + バックフィル前:**
- `unreadNotificationCount` が存在しない/0のため、バッジが表示されない
- バックフィル実行後に正しい値が反映される

**ロールバック:**
- クライアント側のみの変更。旧バージョンのアプリは引き続き動作する
- Cloud Functions側のインクリメント処理は、カウントフィールドが使われなくても副作用は軽微（余分な1 writeのみ）

### 5.3 バックフィルの安全性

- `recalculateUnreadCounts` は読み取り → 書き込みの単純な処理
- Firestoreの既存データ構造を変更しない（フィールド追加のみ）
- 全ユーザーの処理はページネーションで分割し、タイムアウトを防止

---

## 6. 変更ファイル一覧

| # | ファイル | 変更内容 | 影響度 |
|---|---------|---------|--------|
| 1 | `functions/src/helpers/notification-category.ts` | **新規作成**: type→カテゴリマッピング、カテゴリフィールド名ヘルパー | **小** |
| 2 | `functions/src/triggers/notifications.ts` | `onNotificationCreated` にカウントインクリメント追加（約10行） | **中** |
| 3 | `functions/src/callable/admin.ts` | `recalculateUnreadCounts` 関数追加（運用ツール） | **小** |
| 4 | `lib/shared/repositories/notification_repository.dart` | `getUnreadCountStream` / `getUnreadCountStreamByCategory` をフィールド監視に変更、`markAsRead` にtype引数・デクリメント追加、`markAllAsRead` にリセット追加 | **大** |
| 5 | `lib/features/notifications/presentation/screens/notifications_screen.dart` | `markAsRead` 呼び出しにtype引数追加 | **小** |
| 6 | `firebase/firestore.rules` | 変更なし（`unreadNotificationCount` を保護フィールドに追加しない） | **なし** |

---

## 7. リスクと注意点

| # | リスク | 影響度 | 対策 |
|---|--------|--------|------|
| R1 | カウントのドリフト（不整合蓄積） | **中** | 管理者向け `recalculateUnreadCounts` で随時修正可能。定期実行（月1等）も検討 |
| R2 | `markAsRead` の呼び出し元変更漏れ | **中** | `markAsRead` のシグネチャ変更（typeパラメータ必須化）でコンパイルエラーとして検出 |
| R3 | 全件既読とインクリメントの競合 | **低** | `markAllAsRead` でカウントを0にセット後、直後に `onNotificationCreated` が発火してインクリメントされた場合、正しい値（1）になる。問題なし |
| R4 | バックフィル中のカウントずれ | **低** | バックフィルは短時間（数分）で完了。その間に作成された通知はトリガーでインクリメントされるため、バックフィル直後は多少ずれる可能性があるが、次の `recalculateUnreadCounts` で修正可能 |
| R5 | 既読済み通知の再読み込みでの二重デクリメント | **低** | `markAsRead` は `isRead: true` に更新するが、既に `isRead: true` の通知に対して呼ぶとカウントが不正にデクリメントされる。呼び出し元で `!notification.isRead` をチェックしており（`notifications_screen.dart:274`）、問題なし |

### ロールバック

- **クライアント:** 旧バージョンのアプリは `snapshots()` クエリで動作し続ける。影響なし
- **サーバー:** `onNotificationCreated` のインクリメント処理を削除するだけ。カウントフィールドは残るが、参照されなくなるだけで害はない
- **データ:** カウントフィールドが残るが、ストレージコストは無視できる（1ドキュメントあたり4フィールド）

---

## 8. テスト観点

### クライアント側

| # | テスト項目 |
|---|-----------|
| T1 | ホーム画面のバッジに全体未読数が正しく表示される |
| T2 | 通知画面の各カテゴリタブにカテゴリ別未読数が正しく表示される |
| T3 | 通知タップで既読にした後、バッジの数字が1減る |
| T4 | 全件既読ボタン押下後、全バッジが消える |
| T5 | 未読0の状態でバッジが表示されない |
| T6 | カウントが負数の場合に0として表示される（ガード） |
| T7 | 新しい通知受信時にバッジの数字がリアルタイムで増える |
| T8 | 99以上の未読で「99+」が表示される |

### サーバー側

| # | テスト項目 |
|---|-----------|
| T9 | 通知作成時に `unreadNotificationCount` がインクリメントされる |
| T10 | 通知作成時にカテゴリ別カウントが正しいフィールドでインクリメントされる |
| T11 | 全21種類のtypeが正しいカテゴリにマッピングされる |
| T12 | `isRead: true` で作成された通知（将来的に発生する可能性）ではカウントがインクリメントされない |
| T13 | `recalculateUnreadCounts` が正しいカウントを計算する |
| T14 | 決定論的IDの通知（comment, reaction）が二重作成されない（S1冪等性の確認） |

### 結合テスト

| # | テスト項目 |
|---|-----------|
| T15 | コメント通知 → バッジ表示 → タップで既読 → バッジ減少 の一連フロー |
| T16 | 複数カテゴリの通知が同時に来た場合のカウント正確性 |
| T17 | 旧クライアントと新クライアントの混在環境での動作 |
