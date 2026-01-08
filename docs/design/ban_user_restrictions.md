# BANユーザー制限機能 設計書

## 概要

BANされたユーザーに対して、アプリ内の各機能を適切に制限し、一貫したユーザー体験を提供する。

---

## 1. 制限対象機能一覧

### 1.1 投稿・コメント・リアクション

| 機能 | 制限内容 | 実装箇所 | チェック方法 |
|-----|---------|---------|-------------|
| **投稿作成（TL）** | 投稿不可 | `main_shell.dart` | `currentUser.isBanned` → SnackBar |
| **投稿作成（サークル）** | 投稿不可 | `circle_detail_screen.dart` FAB | `currentUser.isBanned` → SnackBar |
| **コメント作成** | 入力欄非表示 | `post_detail_screen.dart` | `currentUser.isBanned` → メッセージ表示 |
| **リアクション** | 操作不可 | `post_card.dart` `_showReactionOverlay` | Firestoreチェック → SnackBar |

### 1.2 サークル関連

| 機能 | 制限内容 | 実装箇所 | チェック方法 |
|-----|---------|---------|-------------|
| **サークル参加（公開）** | 参加不可 | `circle_detail_screen.dart` `_handleJoin` | `currentUser.isBanned` → SnackBar |
| **サークル参加申請（招待制）** | 申請不可 | `circle_detail_screen.dart` `_handleJoin` | `currentUser.isBanned` → SnackBar |
| **サークル作成** | 作成不可（要確認） | - | 未実装 |
| **サークル編集** | 編集不可（オーナー限定） | Firestoreルール | `isNotBanned()` |
| **サークル削除** | 削除不可（オーナー限定） | Firestoreルール | `isNotBanned()` |

### 1.3 その他

| 機能 | 制限内容 | 実装箇所 | チェック方法 |
|-----|---------|---------|-------------|
| **通報** | 可能（BAN中でも通報は許可） | - | 制限なし |
| **閲覧** | 全て可能 | - | 制限なし |
| **問い合わせ** | 可能（異議申し立て用） | - | 制限なし |
| **プロフィール編集** | 要検討 | - | 未実装 |

---

## 2. Firestoreセキュリティルール

### 2.1 `isNotBanned()` ヘルパー関数

```javascript
// firebase/firestore.rules
function isNotBanned() {
  return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isBanned != true;
}
```

### 2.2 適用コレクション

| コレクション | create | update | delete |
|-------------|--------|--------|--------|
| `posts` | ✅ `isNotBanned()` | ✅ | ✅ |
| `comments` | ✅ `isNotBanned()` | - | ✅ |
| `reactions` | ✅ `isNotBanned()` | - | - |
| `circles` | ✅ `isNotBanned()` | ✅ | ✅ |
| `circleJoinRequests` | ✅ `isNotBanned()` | ✅ | ✅ |

---

## 3. Cloud Functions

### 3.1 BANチェック実装済み関数

| 関数名 | チェック内容 |
|-------|-------------|
| `createPostWithRateLimit` | ユーザーの`isBanned`フラグ確認 |
| `createComment` | ユーザーの`isBanned`フラグ確認 |
| `addUserReaction` | Firestoreルールで制限 |

### 3.2 BANメッセージ

```typescript
// 統一メッセージ
throw new HttpsError(
  "permission-denied",
  "アカウントが制限されているため、現在この機能は使用できません。マイページ画面から運営へお問い合わせください。"
);
```

---

## 4. クライアント側UI

### 4.1 表示パターン

| パターン | 使用場面 | 実装例 |
|---------|---------|-------|
| **SnackBar** | ボタン押下時 | 投稿/リアクション/サークル参加 |
| **入力欄非表示 + メッセージ** | 常時表示エリア | コメント入力欄 |
| **ボタン非表示** | 未実装 | 将来的に検討 |

### 4.2 統一メッセージ

```dart
// SnackBar用
const SnackBar(
  content: Text('アカウントが制限されているため、この操作はできません'),
  backgroundColor: Colors.red,
  duration: Duration(seconds: 2),
)

// 入力欄代替メッセージ
Text('アカウント制限中のため、コメントできません')
```

---

## 5. BAN解除フロー

1. ユーザーがマイページから「運営へ問い合わせる」をタップ
2. BAN異議申し立てチャット画面で運営とやりとり
3. 運営が`unbanUser` Cloud Functionを実行
4. `isBanned`フラグが`false`に更新
5. 全機能が再度利用可能に

---

## 6. サブスクリプションとの関係

### 6.1 方針

- BAN時もサブスクリプションは継続（Google Playから強制解約不可）
- サブスク特典（広告非表示・閲覧機能）は維持
- 投稿・コメント等の制限は維持

### 6.2 ユーザーへの案内

BAN時に以下のメッセージを表示して解約を推奨:
> 「サブスクリプションを継続中の場合、Google Playストアから解約をお勧めします」

---

## 7. 実装チェックリスト

- [x] 投稿作成（TL）- `main_shell.dart`
- [x] 投稿作成（サークル）- `circle_detail_screen.dart`
- [x] コメント作成 - `post_detail_screen.dart`
- [x] リアクション - `post_card.dart`
- [x] サークル参加/申請 - `circle_detail_screen.dart`
- [x] Firestoreルール - `firestore.rules`
- [x] Cloud Functions - `index.ts`
- [ ] サークル作成（要確認）
- [ ] プロフィール編集（要検討）

---

## 更新履歴

| 日付 | 内容 |
|------|------|
| 2026-01-08 | 初版作成 |
