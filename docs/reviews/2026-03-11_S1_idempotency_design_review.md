# S1 冪等性設計書 Codexレビュー 総合レポート

**レビュー期間**: 2026-03-11 〜 2026-03-12
**対象**: `docs/scalability/S1_idempotency.md`
**レビュワー**: Codex CLI（read-only）+ Claude Code（全体管理者判断）
**ステータス**: 設計承認済み（全9回レビュー完了）

---

## 総合サマリー

S1 Cloud Functions冪等性設計書に対し、Codex CLIによるアーキテクチャレビューを**6回反復実施**。
合計**23件**の指摘が検出され、うち**22件は修正済み**、**1件は対応不要**（ARCH-09: 運用上リスク極低）。

### 統計

| ラウンド | blocking | major | 合計 | 修正済み |
|---------|----------|-------|------|---------|
| 第1回 | 6 | 0 | 6 | 6/6 |
| 第2回 | 3 | 1 | 4 | 4/4 |
| 第3回 | 2 | 1 | 3 | 3/3 |
| 第4回 | 2 | 1 | 3 | 3/3 |
| 第5回 | 1 | 1 | 2 | 2/2 |
| 第6回 | 2 | 3 | 5 | 4/5（1件対応不要）|
| **合計** | **16** | **7** | **23** | **22/23** |

### 設計書の改訂履歴

| 版 | 契機 | 主な変更 |
|---|------|---------|
| 初版 | 作成 | 4層冪等性設計の初期案 |
| 改訂版 | 第1回レビュー後 | deterministic通知ID、統計冪等化、persona重複除外、pushStatus改善 |
| 第2改訂版 | 第2回レビュー後 | sourceIdをイベント固有IDに、AIコメントdeterministic doc ID+トランザクション、スコープ限定 |
| 第3改訂版 | 第3回レビュー後 | 対象スコープセクション新設、通知producer一覧、ALREADY_EXISTSハンドリング契約 |
| 第4改訂版 | 第4回レビュー後 | AIリアクションdeterministic doc ID、CAS導入、Canonical Idempotency Key |
| 第5改訂版 | 第5回+第6回レビュー後 | deterministic persona選択、業務キーベースpostId、全producer統一、pushStatus 5状態、canonical key分離、merge:true |

---

## 第1回レビュー（初版 → 改訂版）

### 指摘一覧

| # | 重要度 | カテゴリ | 指摘概要 | 対応 |
|---|--------|---------|---------|------|
| 1-1 | blocking | correctness | 通知重複防止が不十分 | **修正済み** |
| 1-2 | blocking | correctness | AI投稿の冪等性設計が実コードとずれている | **修正済み** |
| 1-3 | blocking | correctness | 変更対象ファイルが不完全 | **修正済み** |
| 1-4 | blocking | correctness | AIコメント重複の影響範囲を過小評価 | **修正済み** |
| 1-5 | blocking | correctness | AIリアクション重複はリトライなしでも発生 | **修正済み** |
| 1-6 | blocking | correctness | pushStatusが不正確 | **修正済み** |

### 各指摘の詳細と対応

#### 指摘1-1: 通知重複防止が不十分

**問題**: `pushStatus`は同一通知ドキュメント内の再送防止のみ。上流トリガーのリトライで**新しい通知ドキュメントが別IDで作成**されると、`pushStatus`チェックをすり抜けてFCMが重複送信される。

**修正内容**: 通知作成時にdeterministic IDを使用する設計に変更。

#### 指摘1-2: AI投稿の冪等性設計が実コードとずれている

**問題**: `postId`は既にdeterministic。真の問題は`totalPosts`/`totalPraises`統計の再加算。

**修正内容**: 統計更新の冪等性チェックに焦点変更、トランザクション化。

#### 指摘1-3: 変更対象ファイルが不完全

**問題**: `callable/ai.ts`、`scheduled/ai-posts.ts`のenqueue経路が漏れていた。

**修正内容**: 変更ファイル一覧に追加。

#### 指摘1-4: AIコメント重複の影響範囲を過小評価

**問題**: コメント重複→リアクション連鎖→カウンタ→通知の全連鎖が二重実行される。

**修正内容**: 問題の全体像セクションに連鎖影響を詳細に記載。

#### 指摘1-5: AIリアクション重複はリトライなしでも発生

**問題**: persona選択がreplacement（重複許可）でランダム選択されている。

**修正内容**: producer側でのpersona重複除外を対策3として新設。

#### 指摘1-6: pushStatusが不正確

**問題**: `sendPushOnly()`がFCMエラーを握りつぶし、未送信でも`sent`扱い。

**修正内容**: 3状態管理（pending/sent/failed）に変更、`sendPushOnly()`の戻り値変更。

---

## 第2回レビュー（改訂版 → 第2改訂版）

### 指摘一覧

| # | 重要度 | カテゴリ | 指摘概要 | 対応 |
|---|--------|---------|---------|------|
| 2-1 | blocking | correctness | 通知IDのキー設計が正当な複数通知を潰す | **修正** |
| 2-2 | blocking | correctness | AIコメントの冪等性が依然としてレース条件を残している | **修正** |
| 2-3 | blocking | operability | pushStatus='failed'の後に再送する仕組みがない | **修正** |
| 2-4 | major | consistency | 通知レイヤーの冪等化が全producerに適用されていない | **修正** |

### 追加リスク指摘

- `triggers/circles.ts`はCloud Tasks投入元として記載されているが、実コードではCloud Tasks投入を確認できない → 一覧から削除
- Task IDに日時を混ぜると重複排除の強度が下がる → 永続的なidempotency keyを業務キーで持つべき

### 各指摘の詳細と対応

#### 指摘2-1: 通知IDのキー設計が正当な複数通知を潰す

**問題**: 設計書の`${type}-${sourceId}-${recipientId}`で`sourceId=postId`とすると、同一投稿への別コメント・別リアクションの通知が1件に畳み込まれ、正当な通知が失われる。実コードの`sendPushNotification`は`postId`しか保持しておらず、イベント固有IDが渡されていない。

**Codex原文**: "通知IDのキー設計が正当な複数通知を潰す"

**Claude Code判断**: 妥当・修正必要。`sourceId`は`commentId`/`reactionId`等のイベント固有IDにすべき。

**修正内容**: `sourceId`の定義を`postId`ではなく、イベント固有ID（`commentId`/`reactionId`/`systemEventId`）に変更。`sendPushNotification`のAPIに`sourceId`を明示引数として追加する設計に修正。

#### 指摘2-2: AIコメントの冪等性が依然としてレース条件を残している

**問題**: AIコメントの存在チェックがトランザクション外にあり、コメント作成は自動採番ドキュメントへの`batch.commit()`のまま。並行リトライで複数実行が同じ存在チェックを通過し、二重コメント+リアクション+カウンタ更新が起きうる。AIリアクションはトランザクション化したのに、AIコメントはしていない一貫性の問題。

**Codex原文**: "AIコメントの冪等性が依然としてレース条件を残している"

**Claude Code判断**: 妥当・修正必要。AIリアクションと同様のトランザクション化が必要。

**修正内容**: AIコメントにdeterministic document ID（`ai-comment-${postId}-${personaId}`）を導入し、トランザクション内で存在チェック+作成を原子化。

#### 指摘2-3: pushStatus='failed'の後に再送する仕組みがない

**問題**: `onDocumentCreated`は更新では再発火しない。`sendPushOnly()`が`success: false`を返すと関数は正常終了するため、Cloud Functionsのイベントリトライも起きない。設計書の「リトライ時に再度sent/failedに遷移」という記述は実際には発生しない。

**Codex原文**: "pushStatus='failed' の後に再送する仕組みが設計されていない"

**Claude Code判断**: 妥当。通知はbest-effortと割り切り、設計書から「リトライ時」の表現を削除。

**修正内容**: pushStatus状態遷移から「リトライ」の記述を削除。`failed`は記録・監視用のステータスとし、自動再送は要件外と明記。将来的に再送が必要になった場合のスケジューラ追加を「将来検討」に記載。

#### 指摘2-4: 通知レイヤーの冪等化が全producerに適用されていない

**問題**: サークル更新通知は`sendPushNotification`を通らず`notifications.add()`を直接呼んでいる。この経路はdeterministic ID化の対象外になり、冪等化の層として閉じていない。

**Codex原文**: "通知レイヤーの冪等化が全producerに適用されていない"

**Claude Code判断**: 妥当。S1のスコープをAI系・コメント/リアクション通知に限定し、サークル通知の統一は別タスクに分離。

**修正内容**: 設計書に適用範囲を明記（AI系+コメント/リアクション通知のみ）。サークル通知等の全producer統一は「将来対応」として記載。

---

## レビュー経緯

1. ユーザーがS1設計書のCodexレビューを依頼
2. **第1回**: Codex CLIでレビュー → 6件blocking検出
3. Claude Codeがユーザーに報告 → ユーザーが妥当性確認を依頼
4. Claude Codeが6件すべて妥当と判断
5. ユーザーが全件修正を承認 → 設計書を改訂
6. **第2回**: ユーザーが再レビューを依頼 → 3件blocking + 1件major検出
7. Claude Codeがユーザーに報告 → ユーザーがリスク確認
8. Claude Codeがパフォーマンス影響なし（全変更がサーバー側）と説明
9. ユーザーが全件修正を承認 → 設計書を第2改訂
10. **第3回**: Codexレビュー → 2件blocking + 1件major検出
11. Claude Codeがユーザーに報告 → ユーザーがリスク/メリット確認
12. Claude Codeが3件すべて妥当と判断（スコープ明確化+契約定義の問題）
13. ユーザーが全件修正を承認 → 設計書を第3改訂
14. **第4回**: Codexレビュー → 2件blocking + 1件major検出
15. Claude Codeがユーザーに報告（ARCH-03はadvisory扱いも提案）
16. ユーザーがARCH-03含め全件修正を指示
17. Claude Codeが3件修正 → 設計書を第4改訂

---

## 第3回レビュー（第2改訂版 → 第3改訂版）

### 指摘一覧

| # | 重要度 | カテゴリ | 指摘概要 | 対応 |
|---|--------|---------|---------|------|
| A1 | blocking | architecture_scope | Cloud Tasks冪等化のスコープが実コードのenqueue経路と一致していない | **修正** |
| A2 | blocking | architecture_boundary | 通知レイヤーの冪等化がhelper利用経路にしか効かない | **修正** |
| A3 | major | operability | deterministic Task IDの重複時挙動がhelper契約として未定義 | **修正** |

### 各指摘の詳細と対応

#### A1: Cloud Tasksスコープの不一致

**問題**: 設計書が「Cloud Tasksレイヤー」として全体を閉じたように記述しているが、サークル削除・ゴーストチェック・サークルAI投稿のenqueue経路が非対象のまま。さらに`scheduled/ai-posts.ts`が`scheduleHttpTask`を経由せず直呼び。

**修正内容**: 対象スコープセクションを新設し、AI系処理に限定と明記。非対象経路とその理由を列挙。`scheduled/ai-posts.ts`の直呼びをhelper統一する方針を追記。

#### A2: 通知producer境界の未閉鎖

**問題**: `sendPushNotification`を使う経路はcomment/reaction系の一部のみ。15箇所以上が`notifications.add()`を直接呼んでおり、設計書の「通知レイヤー」の表現と実効範囲がずれている。

**修正内容**: S1対象外の通知producer一覧（18箇所）をファイル・関数・パターン付きで設計書に追記。Callable関数からのユーザー操作起因でリトライリスクが低い旨を明記。

#### A3: ALREADY_EXISTSハンドリング未定義

**問題**: `scheduleHttpTask`に同一Task IDで投入した際の`ALREADY_EXISTS`を成功扱いにする契約がない。実装者ごとにcatch方針がバラバラになるリスク。

**修正内容**: `scheduleHttpTask`のAPI設計に`EnqueueResult`型（`created`/`duplicate_skipped`）を追加。ALREADY_EXISTS（gRPC code 6）を想定内重複として正常扱いする契約を明記。

---

## 第4回レビュー（第3改訂版 → 第4改訂版）

### 指摘一覧

| # | 重要度 | カテゴリ | 指摘概要 | 対応 |
|---|--------|---------|---------|------|
| ARCH-01 | blocking | correctness | AIリアクションのdeterministic document IDがない | **修正** |
| ARCH-02 | blocking | correctness | 通知送信の並行実行でFCM二重送信の可能性 | **修正** |
| ARCH-03 | major | operability | エンドツーエンドのcanonical idempotency keyがない | **修正** |

### 各指摘の詳細と対応

#### ARCH-01: AIリアクションのdeterministic doc ID欠如

**問題**: AIコメントは`ai-comment-${postId}-${personaId}`に修正済みだが、AIリアクションはクエリ+トランザクションのまま。auto-IDでは並行実行時に別ドキュメントが作成される。

**修正内容**: `ai-reaction-${postId}-${personaId}`のdeterministic doc IDを導入。AIコメントと同一の冪等性パターンに統一。

#### ARCH-02: 通知送信の並行実行によるFCM二重送信

**問題**: `onNotificationCreated`が並行に2回処理された場合、`pushStatus`チェックを両方が通過してFCM二重送信する。

**修正内容**: CAS（Compare-And-Set）を導入。トランザクションで`pending → sending`に遷移できた1実行のみがFCM送信する設計に変更。pushStatusを4状態（pending/sending/sent/failed）に拡張。

#### ARCH-03: canonical idempotency keyの欠如

**問題**: 各層で別々のキー（Task ID / doc ID / sourceId）を使っており、エンドツーエンドで同一イベントを追跡できない。

**修正内容**: Canonical Idempotency Keyセクションを新設。`{処理種別}-{postId}-{personaId}`形式のキーをpayloadに載せ、Cloud Tasks名・ドキュメントID・通知sourceId・ログすべてで共有する設計を追加。

---

## 第5回レビュー（第4改訂版 → 最終レビュー）

### 指摘一覧

| # | 重要度 | カテゴリ | 指摘概要 | 対応 |
|---|--------|---------|---------|------|
| ARCH-04 | blocking | correctness | Producer側のpersona乱択がリトライ間で非決定的 | **修正済み** |
| ARCH-05 | major | correctness | AI投稿のcanonical keyがランダムpostIdに依存 | **修正済み** |

### 各指摘の詳細

#### ARCH-04: Producer側のpersona乱択がリトライ間で非決定的

**問題**: 対策3でshuffle+sliceによるpersona重複除外を導入したが、`Math.random()`ベースのため**リトライごとに選択されるpersona集合が変わる**。初回で{A,B,C}が選ばれ、リトライで{A,D,E}が選ばれると、A以外の全タスクが新規投入される。deterministic doc IDは「同じpersonaの二重実行」は防げるが、「リトライでpersona集合が変わること」は防げない。

**影響**: 最悪の場合、リトライ回数 × reactionCount のタスクが投入され、全persona分のAIリアクション/コメントが作成される。

**想定される修正方針**:
- postIdをシードとしたdeterministic shuffle（例: postIdからハッシュ値を生成し、それをシードにする）
- または初回選択結果をFirestoreに永続化し、リトライ時に再利用

#### ARCH-05: AI投稿のcanonical keyがランダムpostIdに依存

**問題**: AI投稿のcanonical idempotency keyが`ai-post-{postId}`だが、`postId`は`uuidv4()`で生成されるランダム値。スケジューラがリトライした場合、新しいpostIdが生成されて別のキーになり、冪等性が破綻する。

**影響**: スケジューラリトライで同一personaが同日に複数の投稿を作成する可能性。

**想定される修正方針**:
- 業務キーベースのpostId生成（例: `ai-post-{personaId}-{yyyyMMdd}`）
- スケジューラ側でpostIdを事前生成してペイロードに含める

---

## レビュー経緯（全体タイムライン）

1. ユーザーがS1設計書のCodexレビューを依頼
2. **第1回**: Codex CLIでレビュー → 6件blocking検出
3. Claude Codeがユーザーに報告 → ユーザーが妥当性確認を依頼
4. Claude Codeが6件すべて妥当と判断
5. ユーザーが全件修正を承認 → 設計書を改訂
6. **第2回**: ユーザーが再レビューを依頼 → 3件blocking + 1件major検出
7. Claude Codeがユーザーに報告 → ユーザーがリスク確認
8. Claude Codeがパフォーマンス影響なし（全変更がサーバー側）と説明
9. ユーザーが全件修正を承認 → 設計書を第2改訂
10. **第3回**: Codexレビュー → 2件blocking + 1件major検出
11. Claude Codeがユーザーに報告 → ユーザーがリスク/メリット確認
12. Claude Codeが3件すべて妥当と判断（スコープ明確化+契約定義の問題）
13. ユーザーが全件修正を承認 → 設計書を第3改訂
14. **第4回**: Codexレビュー → 2件blocking + 1件major検出
15. Claude Codeがユーザーに報告（ARCH-03はadvisory扱いも提案）
16. ユーザーがARCH-03含め全件修正を指示
17. Claude Codeが3件修正 → 設計書を第4改訂
18. **第5回**: Codexレビュー → 1件blocking + 1件major検出
19. Claude Codeがユーザーに報告 → ユーザーがレポート作成を指示

---

## 指摘の全体俯瞰（カテゴリ別）

### 冪等性の根本問題（Deterministic ID系）

| 指摘 | 問題 | 修正 |
|------|------|------|
| 1-1 | 通知ドキュメントIDが自動生成 | deterministic通知ID導入 |
| 2-1 | sourceId=postIdで別通知が潰れる | commentId/reactionId等に変更 |
| 2-2 | AIコメントがauto-ID+batch | deterministic doc ID+トランザクション |
| ARCH-01 | AIリアクションがauto-ID | deterministic doc ID導入 |
| ARCH-05 | AI投稿のpostIdがランダム | **未修正** - 業務キーベースに要変更 |

### レース条件・並行実行問題

| 指摘 | 問題 | 修正 |
|------|------|------|
| 2-2 | AIコメントの存在チェックがtx外 | トランザクション内で原子化 |
| ARCH-02 | 通知のFCM並行送信 | CAS（pending→sending）導入 |

### スコープ・境界問題

| 指摘 | 問題 | 修正 |
|------|------|------|
| 1-3 | 変更対象ファイル一覧が不完全 | callable/ai.ts等追加 |
| 2-4 | 通知冪等化が全producerに未適用 | スコープをAI系に限定と明記 |
| A1 | Cloud Tasksスコープが不一致 | 対象スコープセクション新設 |
| A2 | 通知producerの非対象が不明 | 18箇所のdirect writer一覧追記 |

### 契約・設計不備

| 指摘 | 問題 | 修正 |
|------|------|------|
| 1-2 | AI投稿の冪等性設計が実コードとずれ | 統計冪等化に焦点変更 |
| 1-6 | sendPushOnlyがエラーを握りつぶし | 戻り値を{success: boolean}に変更 |
| 2-3 | pushStatus=failedの再送が未設計 | best-effortと明記、リトライ表現削除 |
| A3 | ALREADY_EXISTSハンドリング未定義 | EnqueueResult型+契約定義 |
| ARCH-03 | canonical idempotency keyがない | 全層で共通キー伝搬設計を追加 |

### Producer問題

| 指摘 | 問題 | 修正 |
|------|------|------|
| 1-4 | AIコメント連鎖影響を過小評価 | 連鎖図を詳細記載 |
| 1-5 | persona選択が重複許可ランダム | shuffle+slice導入 |
| ARCH-04 | shuffle結果がリトライ間で非決定的 | **修正済み** - postIdシードのdeterministic shuffle |

---

## アプリへの影響評価

**モバイルアプリ（Flutter）への影響: なし**

全変更はサーバー側（Cloud Functions）のみ。クライアントアプリのコード変更、API仕様変更、追加通信は一切なし。そのため：
- アプリが重くなることはない
- バッテリー消費が増えることはない
- アプリ更新のリリースは不要

**サーバー側の影響**:
- Firestoreトランザクション追加: 書き込み競合時のリトライでレイテンシがわずかに増加する可能性（通常は無視できる範囲）
- Cloud Tasks Task ID: 完了済みタスクと同名のタスクが7日間作成不可（投稿削除→再投稿時の注意）
- CAS導入: 通知処理の並行実行時にスキップされる実行が発生（正常動作）

---

## 次のアクション

- [x] 第1回レビュー指摘6件の修正
- [x] 第2回レビュー指摘4件の修正
- [x] 第3回レビュー指摘3件の修正
- [x] 第4回レビュー指摘3件の修正
- [x] 第5回Codexレビュー実施
- [x] **ARCH-04 修正**: Producer側のdeterministic persona選択
- [x] **ARCH-05 修正**: AI投稿の業務キーベースpostId
- [x] 第6回Codexレビュー実施（arch + diff）
- [x] **ARCH-06 修正**: callable/ai.tsのpostIdも業務キーに統一
- [x] **ARCH-07 修正**: pushStatus 5状態（pending/skipped/sending/sent/failed）に再定義
- [x] **ARCH-08 修正**: canonical keyと通知sourceIdの分離設計
- [x] **ARCH-09**: 対応不要（AI投稿は運営手動削除のみ、一般AI投稿は機能停止中）→ リスク注記のみ
- [x] **ARCH-10 修正**: `set({ merge: true })`でユーザー更新フィールドを保全
- [x] 第7〜9回Codexレビュー実施（ARCH-11〜15修正、advisory 2件文言修正）
- [x] ユーザー承認（2026-03-12）
- [ ] 実行者による実装着手
