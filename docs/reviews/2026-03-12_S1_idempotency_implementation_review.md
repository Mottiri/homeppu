# S1 冪等性実装 コードレビュー結果

**レビュー日**: 2026-03-12
**レビュー対象**: S1 Cloud Functions idempotency key 実装コード
**レビュー方法**: /simplify + Codex CLI (arch + diff 3並列)
**規模**: large（10ファイル、919行追加）
**ステータス**: ❌ blocking 3件 → 修正中

---

## レビュー対象ファイル

| ファイル | 種別 | 変更概要 |
|---------|------|---------|
| `functions/src/helpers/ai-keys.ts` | 新規 | ID生成ヘルパー (`generateAIPostId`, `generateAICommentId`, `generateAIReactionId`, `deterministicShuffle`) |
| `functions/src/helpers/cloud-tasks.ts` | 修正 | taskId オプション追加、`EnqueueResult` 型、ALREADY_EXISTS ハンドリング |
| `functions/src/helpers/notification.ts` | 修正 | create-only パターン、`sourceId` 引数追加、`canonicalIdempotencyKey` |
| `functions/src/http/ai-generation.ts` | 修正 | 決定的ドキュメントID、トランザクションによる冪等書き込み |
| `functions/src/scheduled/ai-posts.ts` | 修正 | 業務キー postId、`scheduleHttpTask` 統一 |
| `functions/src/triggers/notifications.ts` | 修正 | CAS トランザクション、`SendPushResult` 型、`getSkipReason()` |
| `functions/src/triggers/posts.ts` | 修正 | 決定的タスクID、`deterministicShuffle`、`Promise.allSettled` 並列化 |
| `functions/src/callable/ai.ts` | 修正 | `generateAIPostId()` 使用、タスクID追加 |
| `docs/scalability/S1_idempotency.md` | 修正 | 設計書更新（設計承認済み） |
| `docs/reviews/2026-03-11_S1_idempotency_design_review.md` | 新規 | 設計レビュー記録 |

---

## /simplify 結果

### 修正済み
1. **未使用変数削除**: `_totalComments` を `posts.ts` から削除
2. **ID生成ヘルパー抽出**: `generateAICommentId()`, `generateAIReactionId()` を `ai-keys.ts` に集約（posts.ts + ai-generation.ts の3箇所で共通利用）
3. **Cloud Tasks 並列化**: `posts.ts` のコメント・リアクション両ループを `Promise.allSettled()` に変更

### 対象外（既存コード / S1スコープ外）
- circle-ai/posts.ts の非決定的処理 → S1スコープ外
- ペルソナデータのペイロード肥大化 → 既存設計
- ai-posts.ts のデッドコード → 意図的な機能停止
- 定数ハードコード → 既存パターン

---

## Codex レビュー結果

### Arch Phase

| ID | severity | category | 判定 | 概要 |
|----|----------|----------|------|------|
| ARCH-01 | blocking | architecture | **有効** → B-2 | `notification.ts` が `pushStatus: "pending"` を書き込み、トリガー所有権設計に違反 |
| ARCH-02 | blocking | contract | **有効** → B-3 | `EnqueueResult` を返すが呼び出し元がチェックしていない |
| ARCH-03 | blocking | repository_rule | **偽陽性** | mojibake 指摘だがファイルは正常な UTF-8（Codex Windows 環境の日本語エンコーディング問題） |
| ARCH-04 | blocking | documentation | **S1スコープ外** | `cloud_functions_reference.md` 未更新。ドキュメント更新は別タスクで対応 |

### Diff Phase（3並列）

| グループ | 対象 | 結果 |
|---------|------|------|
| Group 1: helpers | ai-keys.ts, cloud-tasks.ts, notification.ts | ❌ blocking 1件 → B-1 |
| Group 2: http/scheduled/callable | ai-generation.ts, ai-posts.ts, ai.ts | ❌ blocking 1件 → B-1（同一問題） |
| Group 3: triggers | posts.ts, notifications.ts | ❌ blocking 1件 → B-1（同一問題） |

3グループすべてが同一の問題（B-1: リアクション衝突）を独立に検出。

---

## Blocking 指摘詳細

### B-1: リアクション衝突（カウンタ二重加算）⚠️ 最優先

**検出元**: Diff Group 1, 2, 3（全グループ一致）
**対象ファイル**: `triggers/posts.ts` + `http/ai-generation.ts`

**問題**:
`onPostCreated` でコメント用ペルソナとリアクション用ペルソナを同じ `deterministicShuffle(AI_PERSONAS, postId)` から選択している。`commentCount` は 1-5、`reactionCount` は 5-10 のため、コメントペルソナは必ずリアクションペルソナに含まれる。

```
deterministicShuffle 結果: [A, B, C, D, E, F, G, H, I, J]
commentCount=3 → コメント: [A, B, C]
reactionCount=7 → リアクション: [A, B, C, D, E, F, G]
                   ↑ A, B, C が重複
```

`generateAICommentV1` はコメント作成時にリアクションも作成する（`ai-reaction-{postId}-{personaId}`）。一方で `generateAIReactionV1` も同じIDでリアクションを作成しようとする。

- リアクションタスクが先に実行 → コメントタスクがリアクションを上書き → カウンタ二重加算
- コメントタスクが先に実行 → リアクションタスクのトランザクションで既存チェック → スキップ（この場合は問題なし）

**ユーザーへの影響**:
- リアクション数が実際より多く表示される（例: 実際5件なのにカウンター「7」）
- **全ての一般投稿で確実に発生**（決定的選択により重複が保証される）

**修正方針**:
1. `onPostCreated` でコメントペルソナをリアクション候補から除外
2. `generateAICommentV1` のトランザクション内で `reactionRef` の存在チェックを追加（防御的）

### B-2: pushStatus 所有権違反

**検出元**: Arch Phase ARCH-01
**対象ファイル**: `helpers/notification.ts:137`

**問題**:
`sendPushNotification` ヘルパーが通知ドキュメント作成時に `pushStatus: "pending"` を書き込んでいる。設計書（S1_idempotency.md）では「pushStatus の所有者はトリガー（`onNotificationCreated`）のみ」と定義。

リトライ時にヘルパーが再度ドキュメントを作成しようとした場合、create-only パターンにより既存ドキュメントは上書きされないため通常は安全。ただし設計書との不整合があり、将来の保守性リスク。

**ユーザーへの影響**:
- 通常運用では問題なし
- 高負荷時のリトライで通知が2回届く可能性（理論上）

**修正方針**:
ヘルパーから `pushStatus` フィールドを削除。トリガーが初回読み取り時に `pushStatus` が未設定であることを初期状態として扱い、CAS で `sending` に遷移する。

### B-3: EnqueueResult 未チェック

**検出元**: Arch Phase ARCH-02
**対象ファイル**: `helpers/cloud-tasks.ts` → 呼び出し元各所

**問題**:
`scheduleHttpTask` が `{ result: "created" | "duplicate_skipped" }` を返すが、呼び出し元が戻り値を確認せず、重複スキップ時もカウンタ加算・成功ログを出力。

**ユーザーへの影響**:
- ユーザーへの直接影響なし
- 運用ログで「タスク投入成功」と記録されるが実際はスキップ → 運用上の混乱
- `ai-posts.ts` の `postedAIIds` に重複IDが入る可能性があるが、`Set` で重複排除済みのため実害軽微

**修正方針**:
呼び出し元で `result` をチェックし、`duplicate_skipped` 時はログレベルを `info`（「duplicate skipped」）に変更。カウンタ加算をスキップ。

---

## 修正優先度

| 優先度 | ID | 理由 |
|-------|-----|------|
| **P0** | B-1 | 全投稿で確実に発生、ユーザーに見える数値不整合 |
| **P1** | B-2 | 設計書との不整合、リトライ時の通知重複リスク |
| **P2** | B-3 | ユーザー影響なし、運用ログの正確性向上 |

---

---

## 反復2: 再レビュー結果

### B-4: sending状態でのスタック（waived）

**検出元**: Codex 再レビュー（反復2）
**対象ファイル**: `triggers/notifications.ts:119`

**問題**:
CASで`sending`に遷移後、FCM送信前にクラッシュすると`sending`のまま永久にスタック。

**判定: 対応不要（waived）**
- S1以前から存在する問題（Firestoreトリガーはデフォルトでリトライ無効、クラッシュ時は通知ロスト）
- S1による劣化ではない
- 通知は「必ず届かないと困る」性質ではない（ユーザー判断）
- 修正にはCloud Tasks方式への移行が必要で、コスト増を伴う
- 必要に応じてS2以降で「通知信頼性改善」として検討

---

## 修正履歴

| 反復 | ID | 対応 |
|------|-----|------|
| 1 | B-1 | 修正済み: コメントペルソナをリアクション候補から除外 + reactionRef存在チェック追加 |
| 1 | B-2 | 修正済み: ヘルパーからpushStatus削除、トリガーで初期化 |
| 1 | B-3 | 修正済み: EnqueueResult チェック追加 |
| 2 | B-4 | waived: S1以前から存在する既存課題、コスト増のため対応不要 |

| 3 | B-4 | waived（再検出）: Codex最終レビューで再度検出、既にwaived済みのため対応不要 |

## 最終ステータス

- **反復**: 3/5
- **blocking**: 0件（3件修正、1件waived×2回検出）
- **ステータス**: ✅ ok
- **機能管理者検収**: ✅ OK（全4対策が設計書通り、考慮漏れなし）
- **全体管理者最終確認**: ✅ OK（CONCEPT.md準拠、他機能影響なし）

## 次のアクション

- **担当**: ユーザー
- **作業**: コミット承認 → デプロイ
