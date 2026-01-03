# ユーザーBAN機能 設計書

## 概要

悪質ユーザーへの対応として、2段階のBAN機能を実装する。
一時BAN（機能制限）と永久BAN（アカウント凍結）を使い分け、誤BAN防止と復帰可能性を担保する。

---

## 1. BAN状態の種類

| 状態 | 説明 | ログイン | 機能 |
|------|------|---------|------|
| `none` | 通常 | ✅ | ✅ 全機能 |
| `temporary` | 一時BAN | ✅ | ⚠️ 自分のプロフィールのみ閲覧可 |
| `permanent` | 永久BAN | ❌ | ❌ ログイン不可 |

---

## 2. 一時BAN

### 2.1 トリガー

- 管理者がユーザープロフィール画面から「BANする」ボタンを押下

### 2.2 制限内容

| 機能 | 制限 |
|------|------|
| タイムライン閲覧 | ❌ 不可 |
| 投稿作成 | ❌ 不可 |
| コメント・リアクション | ❌ 不可 |
| サークル | ❌ 不可 |
| タスク・目標 | ❌ 不可 |
| 自分のプロフィール閲覧 | ✅ 可 |
| 管理者との対応画面 | ✅ 可 |

### 2.3 BAN対応画面

管理者と被BANユーザーがコミュニケーションを取るための専用画面。

| 項目 | 詳細 |
|------|------|
| 画面名 | `BanAppealScreen`（仮） |
| アクセス | 一時BANユーザーのプロフィール画面から |
| 機能 | メッセージ送受信 |

### 2.4 解除フロー

```
[一時BAN] ─(管理者が問題なしと判断)─→ [通常] + 警告フラグ
           │
           └(管理者が問題ありと判断)──→ [永久BAN]
```

---

## 3. 永久BAN

### 3.1 トリガー

- 管理者がBAN対応画面で「永久BANにする」を選択

### 3.2 挙動

| 項目 | 詳細 |
|------|------|
| ログイン | ❌ 不可 |
| データ保持 | 半年間保持 |
| 復帰 | 半年以内であれば可能（管理者判断） |
| データ削除 | 半年後に自動削除 |

### 3.3 既存投稿の扱い

- 表示継続（削除すると他ユーザーに影響）

---

## 4. サークルオーナーがBANされた場合

### 4.1 一時BAN時

| シナリオ | 対応 |
|---------|------|
| 副オーナーあり | 副オーナーに通知、サークル運営継続 |
| 副オーナーなし | 管理者がサークル内投稿で次期オーナーを募集 |

### 4.2 永久BAN時

| シナリオ | 対応 |
|---------|------|
| 副オーナーあり | 副オーナーがオーナーに自動昇格、通知 |
| 副オーナーなし（対応あり） | 管理者募集後、新オーナー決定でサークル継続 |
| 副オーナーなし（対応なし） | 管理者がサークル削除 |
| オーナー＆副オーナー両方BAN | サークル自動削除、メンバーに通知 |

### 4.3 一時BANから復帰時

- オーナー → 副オーナーに降格
- 現オーナー（元副オーナー）が許可すればオーナーに復帰可能

---

## 5. データ構造

### 5.1 usersコレクション追加フィールド

```typescript
{
  banStatus: 'none' | 'temporary' | 'permanent',
  banHistory: [
    {
      type: 'temporary' | 'permanent',
      reason: string,           // BAN理由
      bannedAt: Timestamp,
      bannedBy: string,         // 管理者UID
      resolvedAt: Timestamp?,
      resolution: 'cleared' | 'escalated' | null
    }
  ],
  permanentBanScheduledDeletionAt: Timestamp?,  // 永久BAN後の削除予定日
  warningCount: number,  // 一時BAN解除後の警告回数
}
```

### 5.2 banAppeals コレクション（新規）

```typescript
// BAN対応画面のメッセージ
{
  id: string,
  bannedUserId: string,
  messages: [
    {
      senderId: string,
      senderType: 'user' | 'admin',
      content: string,
      createdAt: Timestamp
    }
  ],
  status: 'active' | 'resolved',
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

---

## 6. Cloud Functions

| 関数名 | 説明 |
|--------|------|
| `banUser` | ユーザーを一時BANにする |
| `permanentBanUser` | ユーザーを永久BANにする |
| `unbanUser` | BANを解除する |
| `cleanupBannedUsers` | 半年経過した永久BANユーザーのデータ削除（スケジュール実行） |

---

## 7. 通知

| 通知タイプ | 対象 | タイミング |
|-----------|------|-----------|
| `user_banned` | 被BANユーザー | BAN時 |
| `user_unbanned` | 被BANユーザー | BAN解除時 |
| `circle_owner_banned` | 副オーナー/メンバー | オーナーBAN時 |
| `circle_deleted_owner_ban` | メンバー | オーナー＆副オーナーBAN時 |

---

## 8. セキュリティ考慮

| 項目 | 対応 |
|------|------|
| 管理者自身のBAN | ❌ 禁止 |
| 最後の管理者のBAN | ❌ 禁止 |
| BAN理由の記録 | ✅ 必須 |
| 累計BAN回数の記録 | ✅ 実装（2回目以降は厳しく対応） |

---

## 更新履歴

- 2026-01-03: 初版作成
