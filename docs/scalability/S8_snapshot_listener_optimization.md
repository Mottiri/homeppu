# S8: Firestore スナップショットリスナー最適化

**ステータス**: 未着手
**優先度**: P1
**工数目安**: 1-2週間
**作成日**: 2026-03-25

---

## 1. 背景

テスト段階（実ユーザー0人）でFirestoreの月間使用量が **160K reads / 22K writes** に達している。
主因はクライアント側の `.snapshots()` によるリアルタイムリスナーの過剰使用。

リアルタイムリスナーは接続中ずっとreadsを消費し続けるため、ユーザー数に比例してコストが爆発する。

### 想定コストインパクト

| ユーザー数 | 現行（推定月額） | 最適化後（推定月額） |
|-----------|----------------|-------------------|
| 0人（現在） | 160K reads | 大幅削減 |
| 1K DAU | 〜$50 | 〜$5 |
| 10K DAU | 〜$500 | 〜$40 |
| 100K DAU | 〜$5,000 | 〜$300 |

---

## 2. 現状分析

### リスナー総数

- **28箇所**の `.snapshots()` 呼び出し（13ファイル）
- ピーク時 **最大59同時リスナー**（管理者画面を開いた場合）

### ピーク時リスナー内訳

| カテゴリ | 常時 | 画面表示時 | ピーク |
|---------|------|----------|-------|
| サークルカード申請バッジ | 0 | 10〜30 | 30 |
| 通知（一覧+未読数） | 0 | 7 | 7 |
| 管理者バッジ（常時） | 1 | 0 | 1 |
| 管理者ボトムシート | 0 | 3 | 3 |
| 問い合わせ未読バッジ | 1 | 0 | 1 |
| ホーム画面ユーザーデータ | 0 | 1 | 1 |
| currentUserProvider | 1 | 0 | 1 |
| サークル詳細系 | 0 | 2 | 2 |
| 問い合わせ詳細系 | 0 | 3 | 3 |
| スタンプシート系 | 0 | 2 | 2 |
| 管理者個別画面 | 0 | 3 | 3 |
| 投稿詳細 | 0 | 1 | 1 |
| **合計** | **3** | | **最大55+** |

※サークルカードは表示数に比例して増加

### リスナーインベントリ

#### A. サークル関連（最大コスト）

| ファイル | メソッド/箇所 | コレクション | 問題 | 影響度 |
|---------|-------------|------------|------|-------|
| `circles_screen.dart:1384` | `streamJoinRequests()` per card | `circleJoinRequests` | **カード1枚ごとに1リスナー**。10サークル表示=10リスナー | **🔴 Critical** |
| `circle_service.dart:355` | `streamJoinRequests()` | `circleJoinRequests` | 上記のソース | 🔴 |
| `circle_service.dart:375` | `streamPendingRequestCounts()` | `circleJoinRequests` | whereIn で一括だが頻繁に呼ばれる | 🟡 Medium |
| `circle_service.dart:237` | `streamCircle()` | `circles/{id}` | 詳細画面で使用、1画面1リスナー | 🟢 Low |
| `circle_service.dart:554` | `streamPinnedPosts()` | `posts` | サークル詳細で使用 | 🟢 Low |

#### B. 通知関連

| ファイル | メソッド/箇所 | コレクション | 問題 | 影響度 |
|---------|-------------|------------|------|-------|
| `notification_repository.dart:20` | `getNotificationsStream()` | `users/{uid}/notifications` | 全通知ストリーム | 🟡 Medium |
| `notification_repository.dart:41` | `getNotificationsStreamByCategory()` | `users/{uid}/notifications` | **カテゴリタブ1つごとに1リスナー**（3カテゴリ = 3リスナー） | 🟡 Medium |
| `notification_repository.dart:56` | `getUnreadCountStream()` | `users/{uid}/notifications` | 未読数（全体） | 🟡 Medium |
| `notification_repository.dart:72` | `getUnreadCountStreamByCategory()` | `users/{uid}/notifications` | 未読数（カテゴリ別）、3カテゴリ = 3リスナー | 🟡 Medium |

※通知タブは `timeline` / `circle` / `support` の **3カテゴリ**。通知画面表示中は一覧3 + 未読数3 + 全体未読1 = **計7リスナー**。

#### C. 管理者画面

| ファイル | メソッド/箇所 | コレクション | 問題 | 影響度 |
|---------|-------------|------------|------|-------|
| `admin_menu_bottom_sheet.dart:163` | `_getPendingInquiriesCount()` | `inquiries` | タブバッジ用 | 🟡 Medium |
| `admin_menu_bottom_sheet.dart:171` | `_getPendingReportsCount()` | `reports` | タブバッジ用 | 🟡 Medium |
| `admin_menu_bottom_sheet.dart:352` | `_getPendingBanAppealsCount()` | `banAppeals` | サポートタブ内 | 🟢 Low |
| `admin_menu_bottom_sheet.dart:506` | `_getTotalPendingCount()` | inquiries+reports | アイコンバッジ用（**常時アクティブ**） | 🟡 Medium |
| `admin_review_screen.dart:38` | StreamBuilder | `pendingReviews` | 管理画面のみ | 🟢 Low |
| `admin_reports_screen.dart:91` | StreamBuilder | `reports` | 管理画面のみ | 🟢 Low |
| `admin_ban_users_screen.dart:32` | StreamBuilder | `banAppeals` | 管理画面のみ | 🟢 Low |

#### D. 問い合わせ関連

| ファイル | メソッド/箇所 | コレクション | 問題 | 影響度 |
|---------|-------------|------------|------|-------|
| `inquiry_service.dart:144` | `getMyInquiries()` | `inquiries` | 一覧画面 | 🟢 Low |
| `inquiry_service.dart:157` | `getInquiry()` | `inquiries/{id}` | 詳細画面 | 🟢 Low |
| `inquiry_service.dart:168` | `getMessages()` | `inquiries/{id}/messages` | メッセージ一覧 | 🟢 Low |
| `inquiry_service.dart:250` | `getUnreadCount()` | `inquiries` | 未読バッジ（**常時アクティブ**） | 🟡 Medium |
| `inquiry_service.dart:266` | `getAllInquiries()` | `inquiries` | 管理者のみ | 🟢 Low |

#### E. その他

| ファイル | メソッド/箇所 | コレクション | 問題 | 影響度 |
|---------|-------------|------------|------|-------|
| `auth_provider.dart:40` | `currentUserProvider` | `users/{uid}` | 常時アクティブ（必須） | 🟢 Low |
| `home_screen.dart:405` | StreamBuilder | `users/{uid}` | `currentUserProvider` と**重複** — フォロー中タブでfollowing配列を取得するために別途リスナーを張っている | 🟡 Medium |
| `stamp_sheet_service.dart:358` | `watchAllPlacementsByPage()` | `users/{uid}/stampSheet` | スタンプシート画面 | 🟢 Low |
| `stamp_sheet_service.dart:419` | `watchArchives()` | `users/{uid}/stampSheetArchives` | アーカイブ画面 | 🟢 Low |
| `post_detail_screen.dart:76` | `_postStream` | `posts/{id}` | `StreamBuilder` が購読管理するため問題なし | 🟢 Low |
| `post_detail_screen.dart:1009` | StreamBuilder（投稿データ） | `posts/{id}` | 上記と同一ストリームを使用 | 🟢 Low |
| `admin_report_content_screen.dart:49` | StreamBuilder（通報内容） | `reports` | 管理画面のみ | 🟢 Low |
| `ban_appeal_screen.dart:302` | StreamBuilder（BAN申立） | `banAppeals/{id}` | 管理画面のみ | 🟢 Low |

※ `post_detail_screen` の `_postStream` は `StreamBuilder` に渡されており、`StreamBuilder` がウィジェット破棄時に自動的に購読をキャンセルする。手動での `StreamSubscription` 管理は不要。

---

## 3. 最適化計画

### 目標

常時アクティブリスナーを **3 → 1** に、ピーク時を **59 → 5〜10** に削減。

### 3-1. 🔴 サークルカードの申請バッジ（Critical — 最優先）

**現状**: `circles_screen.dart:1384` でカード1枚ごとに `streamJoinRequests()` を呼び出し。
10サークル表示 = 10リスナー。スクロールで増加。

**対策**: 一括バッチクエリに置き換え

```dart
// Before: カードごとにリスナー（N個）
StreamBuilder<List<Map<String, dynamic>>>(
  stream: circleService.streamJoinRequests(circle.id),
  ...
)

// After: 全オーナーサークルの申請数を1クエリで取得
// circleService.streamPendingRequestCounts() を活用し、
// 画面レベルで1つのStreamBuilderにまとめる
```

**注意**: `streamPendingRequestCounts()` は内部で `whereIn` を使用しており、Firestoreの `whereIn` は最大30件の制限がある。オーナーが31サークル以上を持つ場合、circleIdsを30件ずつチャンク分割して複数クエリを発行し、結果をマージする実装が必要。

**期待効果**: リスナー数 N → 1〜2（90%以上削減）

### 3-2. 🟡 通知一覧リスナーの統合（アクティブタブのみ）

**現状**: 通知画面表示中、カテゴリ別一覧3リスナー + 未読数4リスナー + 全通知1リスナー = **計7〜8リスナー**。ただし未読数リスナー4本は全て同じ `users/{uid}` ドキュメントの `snapshots()` を呼んでおり、Firestoreクライアントが内部的にリスナーを重複排除するため、**Firestore側では実質1リスナー**として処理される（S6設計書 L462参照）。

つまり実際のFirestoreリスナーコストは一覧3 + 未読数1（重複排除後）= **実質4リスナー**。

**対策**: アクティブタブのみ一覧リスナーを保持し、タブ切替時に前のリスナーをdispose → 新しいタブのリスナーを作成。一覧3リスナー → 1リスナー。

**注意**:
- 未読数リスナーはFirestoreが重複排除済みのため、統合による追加削減はない。
- 「全通知を1ストリームで取得してクライアント側フィルタ」方式は、既読を含む全件読み込みとなりコスト増になるため採用しない。現在の未読数クエリは `where('isRead', ==, false)` で未読ドキュメントだけを読む効率的な方式。

**期待効果**: リスナー数 実質4 → 実質2（一覧1 + 未読数1（重複排除後））

### 3-3. 🟡 管理者バッジのリスナー最適化

**現状**: `AdminMenuIcon` が常に `_getTotalPendingCount()` のリスナーを保持（**常時1リスナー**）。このリスナーは inquiries の `snapshots()` に `asyncMap` で reports の `get()` を毎回呼ぶ構造になっており、inquiries に変更があるたびに reports の全件再読み込みが発生する。さらにボトムシート内で3つの追加リスナー。

**対策**:
- `_getTotalPendingCount()` の `asyncMap` + `get()` パターンを、inquiries と reports それぞれ独立した `snapshots()` リスナーに分離し、`Rx.combineLatest` で合算する。これにより reports の無駄な再読み込みがなくなる。
- 管理者画面を開いている間だけリスナーを張り、閉じたらdisposeする（常時リスナーを廃止）。

**注意**: Firestoreのリスナーは初回読み込み後、変更があったドキュメントだけ課金される。ポーリング方式は毎回全結果セットを再読み込みするため、アイドル状態ではリスナーの方がreadsが少ない。そのためポーリング化は採用しない。

**期待効果**: 常時リスナー 1 → 0（管理者画面表示時のみリスナー作成）、reports の無駄な再読み込み削減

### 3-4. 🟡 問い合わせ未読バッジの最適化

**現状**: `inquiry_service.dart:250` の `getUnreadCount()` が `inquiries` コレクションに対して `where('hasUnreadReply', ==, true)` のリアルタイムリスナーを常時保持。

**注意**: 問い合わせ未読は `inquiries` コレクションの `hasUnreadReply` フィールドで管理されており、S6の通知未読カウント（`users/{uid}` の `unreadNotificationCount` 等）とは**全く異なるセマンティクス**。S6に統合することはできない。

**対策**: 問い合わせ画面を開いている間だけリスナーを張り、閉じたらdisposeする。バッジ表示用には `users/{uid}` ドキュメントに `hasUnreadInquiry`（boolean）を非正規化し、`currentUserProvider` 経由で取得する。

**必要な追加作業**:
1. `users/{uid}` に `hasUnreadInquiry: boolean` フィールドを追加
2. `UserModel` に該当フィールドを追加
3. Cloud Functions `sendInquiryReply` で `hasUnreadInquiry: true` に更新
4. クライアント側 `markAsRead` で未読が0件になったら `hasUnreadInquiry: false` に更新

**期待効果**: 常時リスナー 1 → 0（バッジは `currentUserProvider` で代替）

### 3-5. 🟡 ホーム画面ユーザーデータの統合

**現状**: `home_screen.dart:405` でフォロー中タブ表示時に `users/{uid}` ドキュメントへの独自リスナーを張っている。`currentUserProvider` と同じドキュメントを二重にリッスン。

**対策**: `currentUserProvider` が提供する `UserModel` に `following` リストを含めるか、フォローリストを別途キャッシュして `currentUserProvider` 経由で取得する。

**期待効果**: リスナー 1 → 0（既存リスナーで代替）

### 3-6. 🟢 低優先度（ユーザー数増加時に検討）

- `streamCircle()`: 詳細画面でのみ使用、1画面1リスナーなので許容
- `streamPinnedPosts()`: 同上
- スタンプシート系: 該当画面のみ、リスナー数は少ない
- `currentUserProvider`: 常時必要、削除不可
- `post_detail_screen._postStream`: `StreamBuilder` が購読管理するため問題なし

---

## 4. 実装順序

```
Step 1: 3-1 サークルカード申請バッジの一括化（最大コスト削減）
Step 2: 3-2 通知一覧リスナー統合（アクティブタブのみ）
Step 3: 3-3 管理者バッジのリスナー最適化
Step 4: 3-4 問い合わせ未読バッジの最適化（hasUnreadInquiry非正規化）
Step 5: 3-5 ホーム画面ユーザーデータ統合
```

Step 1-3, 5 は並列実行可能。Step 4 は Cloud Functions 変更を伴うため独立して実施。

---

## 5. 期待される削減効果

| 対策 | 常時リスナー削減 | 画面表示時リスナー削減 | reads削減率（推定） |
|------|---------------|--------------------|--------------------|
| 3-1 サークルカード | 0 | -9〜-29 | 40-50% |
| 3-2 通知一覧統合 | 0 | -2 | 5-10% |
| 3-3 管理者リスナー最適化 | -1 | -3 | 5-10% |
| 3-4 問い合わせ未読最適化 | -1 | 0 | 3-5% |
| 3-5 ホーム画面統合 | 0 | -1 | 2-3% |
| **合計** | **-2** | **-15〜-35** | **55-78%** |

### Before / After 比較

|  | 常時リスナー | ピーク時（全画面） |
|--|------------|-----------------|
| **現行** | 3 | 最大59 |
| **最適化後** | 1 | 10〜20 |
| **削減率** | 67% | 66-83% |

※最適化後の常時リスナーは `currentUserProvider` の1本のみ。
※通知の未読数リスナーはFirestoreクライアントが重複排除するため、見かけ上の本数より実コストは少ない。

---

## 6. リスクと注意点

- **Firestoreリスナーの課金モデル**: リスナーは初回読み込み後、変更ドキュメントのみ課金。ポーリングは毎回全結果セット再読み込み。そのためリスナー→ポーリング変更は原則コスト増になる（3-3で不採用とした理由）
- **バッチクエリの制限**: Firestore `whereIn` は最大30件。サークル数が30を超える場合は分割が必要
- **通知タブ切替のUX**: アクティブタブのみリスナー方式だと、タブ切替時に一瞬ローディングが入る可能性がある。キャッシュ併用で軽減可能
- **問い合わせ未読とS6の違い**: 問い合わせ未読（`hasUnreadReply` on `inquiries`）と通知未読（`unreadNotificationCount` on `users/{uid}`）は別のセマンティクス。混同しないこと
- **Firestoreのリスナー重複排除**: 同じドキュメントへの複数 `snapshots()` はクライアント内部で1リスナーに統合される。見かけ上のリスナー数とFirestore課金リスナー数は異なる場合がある

---

## 7. 関連ドキュメント

- [S6: 通知未読カウントの非正規化](./S6_notification_count.md)
- [S7: サークル関連コスト最適化](./S7_circle_cost_optimization.md)
- [スケーラビリティ調査報告書](../specs/2026-03-11_scalability_investigation.md)
