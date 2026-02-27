# CT-001: チュートリアル自動スクロール 詳細設計書

## スコープ
- **対象**: Phase2チュートリアル `commentLongPress` ステップのデッドロック解消
- **非対象**: 長文投稿カードの占有問題自体は CT-002 として別件対応

## 問題
投稿内容が長い場合、Phase2チュートリアルの`commentLongPress`ステップで
ターゲットコメントが画面外にあり、`NeverScrollableScrollPhysics`でスクロールも
無効化されているためチュートリアルが詰む。

## 技術的制約
`SliverList`は画面外のアイテムをbuildしない（遅延構築）。
そのため画面外コメントの`GlobalKey.currentContext`は常に`null`となり、
`Scrollable.ensureVisible`を呼ぶ前段で失敗する。

## 方針

### 根本解決: コメントリストのeager build化

チュートリアル`commentLongPress`ステップ中のみ、コメントリストを
`SliverList`（遅延構築）から`SliverToBoxAdapter` + `Column`（eager構築）に切り替える。

- コメント数は通常10〜30件程度で、eager buildのパフォーマンス影響は無視できる
- これにより全コメントが即座にbuildされ、`currentContext`が常に取得可能になる
- チュートリアル以外のステップでは既存の`SliverList`を維持（パフォーマンス担保）
- **eager buildの安全閾値**: コメント数が200件を超える場合はeager buildを行わず、
  `SliverList`を維持したまま`_tutorialScrollFallback = true`（スクロール禁止解除）で
  フォールバックモードに移行する。200件は通常運用の10倍以上のマージンであり、
  Phase2チュートリアルは初期ユーザー体験のため実際にこの閾値に達する可能性は極めて低い

eager build化により`currentContext`が確実に取得できるため、
`settings_screen.dart`の`_maybeAutoScrollToPrivacyCard()`と同じパターンで
`Scrollable.ensureVisible`による自動スクロールが可能になる。

> `NeverScrollableScrollPhysics`はユーザージェスチャーのみを制限し、
> プログラム的スクロール(`Scrollable.ensureVisible`, `ScrollController.animateTo`)には影響しない。

## 修正対象ファイル

### `lib/features/post/presentation/screens/post_detail_screen.dart`（唯一の修正対象）

> **設計原則**: `tutorial_phase2_provider.dart` は変更しない。
> 現行providerは状態遷移と永続化のみを担当しており、
> 画面レイアウト・スクロール・ターゲット到達可否の判断は画面側の責務として維持する。

#### 変更内容

**a) 状態変数の追加**
- `bool _didAutoScrollToComment = false` — 自動スクロール済み & in-flight guard
- `int _commentScrollRetryCount = 0` — ターゲットコンテキスト取得のリトライカウンター
- `String? _tutorialTargetCommentId` — ステップ開始時に固定したターゲットコメントID
- `bool _tutorialScrollFallback = false` — フォールバック発動フラグ（スクロール禁止解除用）

**b) ターゲットコメントIDの固定**
- `commentLongPress`ステップ開始時、最初のターゲット検出で`_tutorialTargetCommentId`にIDを保存
- 以降のビルドではこのIDでターゲットを特定（indexではなくID基準）
- ストリーム更新によるフレーム間のターゲットずれを防止
- **ターゲットID消失時の対応**: 固定IDのコメントがストリーム更新で`isVisibleNow`フィルタから
  消えた場合（非表示化・削除）、以下の順で対応:
  1. 別の非オーナーコメントが存在すれば、ターゲットIDを再選定してリセット
  2. 非オーナーコメントが一つもなければ、`_tutorialTargetCommentId = null`にして
     overlay非表示のまま継続（ターゲットなし状態と同等。既存動作と同じ）

**c) コメントリストのeager build切り替え**
- `commentLongPress`ステップ中かつ`hasTutorialTarget`の場合:
  `SliverList` → `SliverToBoxAdapter` + `Column`（全コメントをeager build）
- それ以外: 既存の`SliverList`を維持
- これにより画面外のターゲットコメントも`currentContext`が取得可能になる

**d) 自動スクロールメソッドの追加: `_maybeAutoScrollToComment()`**
- `settings_screen.dart`の`_maybeAutoScrollToPrivacyCard()`と同パターン
- **in-flight guard**: `_didAutoScrollToComment`フラグで多重実行を防止。
  buildのたびに呼ばれても、`_didAutoScrollToComment == true`なら即return。
  自動スクロール処理は状態遷移時に1回だけ実行される
- `_tutorialTargetCommentKey.currentContext`でターゲットの`BuildContext`を取得
  （eager buildにより画面外でも取得可能）
- 取得できなければリトライ（最大12回、120ms間隔）— eager buildのフレーム待ち用
- 取得できたら`Scrollable.ensureVisible`でスクロール（380ms）
- **スクロール完了を`await`してから**`_resolveTutorialCommentRect()`で位置を再取得
- スクロール中はoverlayを表示しない（`_tutorialCommentRect`がnullのまま）

**e) 処理順序の制御**
- 既存の位置取得処理（415-421行目）を自動スクロールメソッド内に統合
- `_didAutoScrollToComment == false`の場合: スクロール → rect解決 → overlay表示
- `_didAutoScrollToComment == true`の場合: 既存のrect解決のみ（現行動作と同等）

**f) フォールバック（画面ローカル） — スクロール禁止の条件分離**
- 現行: `physics: tutorialStep == commentLongPress ? NeverScrollableScrollPhysics() : null`
- 改修後: `physics: (tutorialStep == commentLongPress && !_tutorialScrollFallback) ? NeverScrollableScrollPhysics() : null`
- `_tutorialScrollFallback`は画面ローカルのboolフラグ
- eager buildにより`currentContext`取得失敗はほぼ起きないが、
  万一リトライ上限到達時:
  1. `_tutorialScrollFallback = true`にセット → スクロール禁止が解除される
  2. overlayは非表示のまま`commentLongPress`ステップを継続
  3. ユーザーは手動スクロールしてターゲットコメントを長押しできる
- `markCompleted()`は呼ばない（未体験のチュートリアルを恒久完了にしない）
- デバッグログにフォールバック発動を記録
- **フォールバック時のチュートリアル完了**: フォールバックモード（`_tutorialScrollFallback == true`）では、
  `onThanksCompleted`コールバックを固定ターゲットだけでなく**全ての非オーナーコメント**に付与する。
  これにより、ユーザーが手動スクロールしてどの非オーナーコメントを長押ししても
  チュートリアルを完了できる。通常モードでは従来通り固定ターゲットのみに付与。

**g) ステップ変更時のリセット**
- `commentLongPress`以外のステップになったら`_didAutoScrollToComment`、
  `_commentScrollRetryCount`、`_tutorialTargetCommentId`、`_tutorialScrollFallback`をリセット

## 処理フロー

```
commentLongPressステップ開始（provider状態変化を検知）
  ↓
コメントリストを SliverList → Column に切り替え（eager build化）
  ↓
ターゲットコメントあり?
  ↓ No → overlay表示せず（既存動作）
  ↓ Yes
_tutorialTargetCommentId にIDを固定（未固定時のみ）
  ↓
_maybeAutoScrollToComment() 実行
  ↓ _didAutoScrollToComment == true → 即return（in-flight guard）
  ↓ _didAutoScrollToComment == false → 処理開始、フラグをtrueに
  ↓
[Phase 1: positioning]
ターゲットのBuildContext取得できる?（eager buildにより通常は即取得可能）
  ↓ No → リトライ（最大12回、120ms間隔）
  │        → 取得不能なら _tutorialScrollFallback = true（スクロール禁止解除）
  │          ユーザー手動スクロールで対応可能に
  ↓ Yes
Scrollable.ensureVisible() でスクロール（380ms、await完了待ち）
  ↓
_resolveTutorialCommentRect() で位置取得
  ↓
[Phase 2: interacting]
_tutorialCommentRect にセット → overlay表示
（NeverScrollableScrollPhysicsによるスクロール禁止は _tutorialScrollFallback == false の場合のみ適用）
  ↓
ユーザーが長押し → markCompleted() → チュートリアル完了
```

### ターゲットID消失時のサブフロー
```
ストリーム更新でコメントリスト再構築
  ↓
固定した _tutorialTargetCommentId がリスト内に存在する?
  ↓ Yes → 通常処理続行
  ↓ No
別の非オーナーコメントが存在する?
  ↓ Yes → ターゲットIDを再選定、全状態をリセットして再実行
  │        リセット対象: _didAutoScrollToComment, _commentScrollRetryCount,
  │                      _tutorialCommentRect, _tutorialScrollFallback
  ↓ No → _tutorialTargetCommentId = null、overlay非表示で待機（ターゲットなし状態）
```

## エッジケース

| ケース | 対応 |
|--------|------|
| コメントが既に画面内にある | `ensureVisible`はスクロール不要と判断し即完了、rect解決へ進む |
| ターゲットコメントが無い | 既存ロジックでスキップ（`hasTutorialTarget=false`） |
| ターゲットのContext取得不能（万一） | `_tutorialScrollFallback=true`でスクロール禁止解除、手動操作可能 |
| 画面遷移中にスクロール完了 | `mounted`チェックで安全にガード |
| スクロール中にストリーム更新 | `_tutorialTargetCommentId`でIDを固定済みのため影響なし |
| 固定IDのコメントが消失 | 別の非オーナーコメントで再選定、なければターゲットなし状態 |
| コメント数が多い場合のeager build | 200件以下: eager build。200件超: SliverList維持+フォールバックモード |
| フォールバック時のチュートリアル完了 | 全非オーナーコメントに`onThanksCompleted`を付与、どれでも完了可能 |
| ターゲット再選定時の状態整合性 | 全関連フラグ（rect, retry, fallback, didScroll）をリセットして再実行 |
| buildからの多重実行 | `_didAutoScrollToComment`フラグで1回だけ実行（in-flight guard） |

## テスト観点
- 長い投稿（テキスト長文 + メディア付き）でコメントが画面外 → 自動スクロール発動確認
- 短い投稿でコメントが画面内 → 既存動作と同じ（スクロール不要）
- コメントがない投稿 → チュートリアルターゲットなし、スキップ
- 自分以外のコメントがない投稿 → チュートリアルターゲットなし
- スクロール中にコメントストリーム更新 → ターゲットIDが固定されずれない
- ターゲットコメントが非表示化 → 別コメントに再選定されること
- チュートリアル終了後、コメントリストがSliverListに戻ることを確認
- eager build時のパフォーマンス（コメント30件程度で問題ないこと）
- フォールバック時にスクロール禁止が解除され手動操作可能なこと
- 自動スクロールが1回だけ実行されること（多重実行しないこと）
- フォールバック時に任意の非オーナーコメント長押しでチュートリアル完了すること
- ターゲット再選定時に全状態がリセットされ、新ターゲットへ自動スクロールすること
- コメント200件超の場合にeager buildせずフォールバックモードになること
