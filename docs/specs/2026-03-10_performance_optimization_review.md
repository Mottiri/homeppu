# 性能改善設計書レビュー

**作成日**: 2026-03-10
**対象資料**: `docs/specs/2026-03-10_performance_optimization.md`
**目的**: 他AIが設計書の修正、実装優先順位判断、レビュー継続に使うためのコミュニケーションファイル
**ステータス**: レビュー完了、性能改善全体保留（低速端末実機確認で許容範囲と判断、2026-03-11）
**次のアクション担当者**: なし（再開条件は性能改善設計書を参照）

---

## 1. この資料の結論

- 元資料の方向性は概ね妥当
- ただし、そのまま実装根拠として使うには一部の記述精度が不足している
- 特に「確定事項」と「仮説」の切り分けをやり直す必要がある
- 実装優先順位は大筋で維持してよい

### 総合判定

**採用価値は高いが、実装着手前に1回ドキュメント修正が必要**

---

## 2. 全体評価

### 妥当だった点

- `build()` 内 `addPostFrameCallback` の整理を高優先度に置いている点は妥当
- Follow Feed の `whereIn + followingIds.take(10)` を欠陥として扱っている点は妥当
- 画像読み込みの共通化を `AppImage` 方向で整理する方針は妥当
- `itemExtent` を固定高リストに限定する整理は妥当

### 修正が必要な点

- ホームの `scroll-to-top` 重複を「未確認事項」に置いているが、コード上は重複登録が確定している
- チュートリアル `passThroughSpotlight` の説明がやや不正確
- リアクション最適化の根拠に、現行コードとズレる表現がある
- 画像項目の「`Image.network()` はキャッシュなし」という表現が強すぎる
- 「アプリ全体最適化」と言うには、N+1 読み込み系の候補が抜けている

---

## 3. 重要なレビュー指摘

### 指摘1: scroll-to-top は未確認ではなく確定事項

`homeScrollToTopProvider` に対して、以下の2箇所でリスナーが登録されている。

- `HomeScreen.build()` の `ref.listen`
- `_PostsList.initState()` の `ref.listenManual`

このため、資料中の「重複スクロールリスナーの可能性」は弱すぎる。  
**「確認済みの問題」へ昇格**させるべき。

**根拠ファイル**
- `lib/features/home/presentation/screens/home_screen.dart:71`
- `lib/features/home/presentation/screens/home_screen.dart:510`

### 指摘2: チュートリアルの二重マスク説明は書き換えが必要

元資料では `passThroughSpotlight=true` 時に `_AnimatedMaskWithHole` が2重に動作すると書かれているが、現行実装は以下。

- 可視マスク: `_AnimatedMaskWithHole`
- タップ制御用レイヤ: `_PassThroughMaskLayers`

つまり問題は「可視マスクが2枚重なっている」ではなく、  
**アニメーション追従する2系統のレイヤが存在し、座標追従と再描画コストが増える**こと。

**根拠ファイル**
- `lib/shared/widgets/tutorial_overlay.dart:93`
- `lib/shared/widgets/tutorial_overlay.dart:107`

### 指摘3: リアクション最適化の論点を補正すべき

元資料の主張のうち、以下は補正が必要。

- sparkle 側の `blurRadius: 20+` は現行コードと一致しない
- `AnimationController` 蓄積は主問題としては弱い

現行コードで強い負荷候補なのは以下。

- Epic sparkle が `20個 x 2レイヤー = 40 widget`
- epic glow の `blurRadius: 26`
- `Transform` と `Opacity` を含む多段構造

よって、レビュー観点は  
**「widget 数削減」と「epic glow の軽量化」中心**に修正した方がよい。

**根拠ファイル**
- `lib/features/home/presentation/widgets/reaction_background.dart:198`
- `lib/features/home/presentation/widgets/reaction_background.dart:359`

### 指摘4: 画像項目は「no cache」ではなく「ポリシー未統一」

`Image.network()` 使用箇所は確かに存在するが、問題の本質は以下。

- ディスクキャッシュ利用方針が画面ごとに不統一
- `CachedNetworkImage` 使用箇所でも縮小デコード指定がない
- フルスクリーン表示は高画質維持が必要

したがって、元資料の
`Image.network() がキャッシュなし・サイズ指定なし`
という書き方は、  
**「画像読み込みポリシーが未統一で、縮小デコードも未整理」**へ言い換えるのが適切。

**根拠ファイル**
- `lib/shared/widgets/avatar_selector.dart:148`
- `lib/features/home/presentation/widgets/post_card.dart:782`
- `lib/shared/widgets/full_screen_image_viewer.dart:46`

### 指摘5: N+1 読み込み候補が抜けている

元資料は UI レンダリング寄りの改善に寄っているが、  
「アプリ全体最適化」を名乗るならデータ取得の無駄も候補に入れるべき。

特に `profile_following_list.dart` では、横スクロール項目ごとに `FutureBuilder<DocumentSnapshot>` を発行している。  
既存の `publicUserDocProvider` があるため、少なくとも改善余地として列挙する価値がある。

これは今回すぐ実装する項目でなくてもよいが、  
**「次点候補」または「Phase 2 候補」**として設計書に追記した方が他AIに誤解が少ない。

**根拠ファイル**
- `lib/features/profile/presentation/widgets/profile_following_list.dart:43`
- `lib/shared/providers/public_user_provider.dart:6`

---

## 4. 項目別の判定

| 項目 | 判定 | コメント |
|---|---|---|
| #1 チュートリアルオーバーレイ | 条件付きで妥当 | 方向性はよい。説明精度だけ補正が必要 |
| #2 build() 内 post-frame callback | 妥当 | 高優先度のままでよい |
| #3 画像読み込み最適化 | 妥当 | ただし診断文を修正する |
| #4 リアクションアニメーション | 一部修正必要 | 主因の記述を現行コードに合わせる |
| #5 Provider リビルド最適化 | 妥当 | `.select()` より Consumer 分割重視でよい |
| #6 Follow Feed クエリ改善 | 強く妥当 | 性能より先に正しさの欠陥修正でもある |
| #7 リストスクロール最適化 | 妥当 | 低優先度でよい |

---

## 5. 優先順位に関する判断

以下の順は維持して問題ない。

1. `#2 build() 内 post-frame callback 整理`
2. `#6 Phase 1 Chunked Query`
3. `#3 画像読み込み最適化`
4. `#1 チュートリアルオーバーレイ`

補足:

- `#6` は性能改善だけでなく、11人以上フォロー時の投稿欠落を含む
- `#2` は低コストで再描画ノイズを減らせる可能性が高い
- `#1` は CT-017 の直接原因候補だが、仕様破壊リスクがあるため `#2` より先にしない方が安全

---

## 6. 元資料へ反映すべき修正

他AIが元資料を更新する際は、最低限以下を反映すること。

### 必須修正

- 「未確認事項」の `scroll-to-top` を削除し、「確認済みの問題」へ移す
- `passThroughSpotlight` の説明を「2重マスク」から「表示レイヤ + タップ制御レイヤ」に修正する
- リアクション項目の `blurRadius: 20+` 表現を現行コードに合わせて修正する
- `AnimationController` 蓄積を主論点にしすぎない
- 画像項目の「キャッシュなし」を「ポリシー未統一」に修正する

### あると良い追記

- `profile_following_list.dart` の N+1 読み込みを次点候補として追記
- 静的レビュー結果であり、未計測項目は DevTools で確認予定と明記

---

## 7. 実装前の前提共有

このレビューは**静的レビュー**であり、実機計測や DevTools プロファイリングはまだ行っていない。  
したがって、以下の区分で扱うこと。

### 確定事項

- `build()` 内 `addPostFrameCallback` 多用
- Follow Feed の `followingIds.take(10)`
- `scroll-to-top` リスナー重複
- `Image.network()` / `CachedNetworkImage` 方針の不統一

### 仮説寄りの事項

- チュートリアル座標計算の体感コストの大きさ
- Epic 演出が低スペック端末でどの程度支配的か
- N+1 読み込みが体感にどれほど効いているか

---

## 8. 次アクション

### 推奨フロー

1. Feature Spec Owner が `2026-03-10_performance_optimization.md` を本レビューに沿って修正
2. Executor が `#2` と `#6 Phase 1` から着手
3. Reviewer が DevTools 計測前提で `#1` と `#4` の優先度再判定

### Owner

- 次アクション担当者: Feature Spec Owner

---

## 9. 参照ファイル

- `docs/specs/2026-03-10_performance_optimization.md`
- `lib/features/home/presentation/screens/home_screen.dart`
- `lib/features/home/presentation/screens/main_shell.dart`
- `lib/shared/widgets/tutorial_overlay.dart`
- `lib/features/home/presentation/widgets/reaction_background.dart`
- `lib/features/home/presentation/widgets/post_card.dart`
- `lib/shared/widgets/full_screen_image_viewer.dart`
- `lib/features/profile/presentation/widgets/profile_following_list.dart`
- `lib/shared/providers/public_user_provider.dart`

---

## 10. この資料の使い方

他AIはこの資料を以下の用途に使うこと。

- 元設計書の修正文案の根拠
- 実装着手前の優先順位確認
- レビュー時の「確定事項 / 仮説」の切り分け

この資料単体で実装仕様を確定しないこと。  
**正本は `docs/specs/2026-03-10_performance_optimization.md` であり、本資料はそのレビュー補助資料**として扱う。

---

## 11. 再レビュー追記（2026-03-10）

更新後の `docs/specs/2026-03-10_performance_optimization.md` を再確認した。  
結論として、**前回レビューの主要指摘はほぼ反映済みであり、実装判断のベース資料として使用可能**。

### 反映確認できた点

- 静的レビュー前提であることが明記された
- `passThroughSpotlight` の説明が、表示レイヤとタップ制御レイヤの分離として補正された
- リアクション項目の主負荷要因が `40 widget` と `epic glow` 中心に修正された
- 画像項目が「キャッシュなし」ではなく「ポリシー未統一」として補正された
- `profile_following_list` の N+1 読み込みが次点候補として追加された
- `scroll-to-top` 重複が未確認事項から分離された

### まだ整理すると良い点

- `scroll-to-top` 重複は「確認済みだが優先度未定」より、`#2 build() 内 post-frame callback 整理` に寄せて管理した方が実装上は扱いやすい
- ただし、現状の記述でも技術的な誤りではない

### 再レビュー時点の判定

**採用可。実装着手前の設計書として使用してよい。**

### 次アクション担当者

- Feature Spec Owner
- Executor
