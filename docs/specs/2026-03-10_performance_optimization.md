# 性能改善設計書: 低スペック端末向けアプリ全体最適化

**作成日**: 2026-03-10
**起源**: CT-017（チュートリアルのカクつき）調査から派生
**ステータス**: #2・#6 Phase1・#8 Phase A・#9 C1-C5 実装完了、#8 Phase B・C・#9 C4/C6-C9 保留、#1/#3〜#5/#7 設計中
**次のアクション担当者**: ユーザー → 次の着手項目を選定

---

## 背景

CT-017（低速端末でのチュートリアルカクつき）の調査を契機に、アプリ全体のパフォーマンスボトルネックを洗い出した。Codexレビュー（2026-03-10）で調査結果の精度を検証し、技術的に不正確な点を修正した上で本設計書にまとめる。

CT-017自体はチュートリアル起因の症状に限定し、横断的な改善は本設計書で管理する。

**注意**: 本設計書は静的コードレビューに基づく。実機計測や DevTools プロファイリングは未実施のため、「確認済みの問題」はコード上確定している事項、「仮説寄りの事項」（チュートリアル座標計算の体感コスト、Epic演出の低スペック端末への影響度等）は実装時に DevTools で計測の上で対策の最終判断を行うこと。

---

## 改善項目一覧

| # | カテゴリ | 影響度 | 実装コスト | 既存仕様への影響 |
|---|---------|--------|-----------|----------------|
| 1 | チュートリアルオーバーレイ | 高 | 中 | tutorial multi-phase に注意 |
| 2 | build() 内 post-frame callback | 高 | 低 | なし |
| 3 | 画像読み込み（Widget Wrapper） | 高 | 中 | fullscreen の画質維持に注意 |
| 4 | リアクションアニメーション | 高 | 中 | Epic演出の体験に注意 |
| 5 | Provider リビルド最適化 | 中 | 低〜中 | なし |
| 6 | Follow Feed クエリ改善 | 中 | 低（Phase1） | 機能バグ修正を含む |
| 7 | リストスクロール最適化 | 低 | 低 | 固定高リストのみ対象 |
| 8 | プロフィール投稿一覧 shrinkWrap 撤去 | 高 | 低 | なし（DevTools実測: Build 31ms） |
| 9 | スタンプシート Raster Jank 修正 | 高 | 中 | なし（DevTools実測: Raster 81.7ms → 17ms） |

---

## 1. チュートリアルオーバーレイ

**確認済みの問題**:
- `build()` 内で `Path.combine(PathOperation.difference)` を毎フレーム実行（`_MaskWithHoleClipper`）
- `passThroughSpotlight=true` 時に表示レイヤ（`_AnimatedMaskWithHole`）とタップ制御レイヤ（`_PassThroughMaskLayers`）の2系統が同時動作し、座標追従と再描画コストが増加
- `resolveRectWithRetry()` が `Future.delayed` で200ms×最大5回リトライ → dispose後も実行が残るリスク
- チュートリアルメッセージの `_tokenPattern.allMatches` が毎ビルドで実行
- パルスアニメーション中に `Rect.fromCenter()` が毎フレーム再計算

**対策**:
- [ ] `_MaskWithHoleClipper` のホールパスをメモ化（Rect未変更時は再計算スキップ）
- [ ] `resolveRectWithRetry()` をキャンセル可能にし、dispose時に中断
- [ ] チュートリアルメッセージのパース結果をキャッシュ
- [ ] スポットライト位置確定後は不要な再計算を停止

**実装時の注意**:
- `passThroughSpotlight` は表示レイヤ（可視マスク）とタップ制御レイヤ（穴の内側だけタップ透過、外側は遮断）に分離されている。統合はhit-test分離を壊すリスクがあるため、**プロトタイプで手動テスト後に判断**する
- tutorial multi-phase のナビゲーション・ロック動作を壊さないこと

**関連ファイル**:
- `lib/shared/widgets/tutorial_overlay.dart`
- `lib/features/profile/presentation/screens/profile_screen.dart`

---

## 2. build() 内の post-frame callback 整理

**確認済みの問題**:
- `main_shell.dart`: `_resolveBottomNavHeight()` 等が毎ビルドで `addPostFrameCallback` をスケジュール（L251, L269, L282, L351, L366, L395, L423, L437, L446）
- `home_screen.dart`: チュートリアル用 Rect 解決の callback が毎ビルドで登録（L699, L707）
- キャンセル機構がなく、同一処理が蓄積する

**対策**:
- [x] post-frame callback を `build()` から `initState()` / `didUpdateWidget()` に移動
- [x] 実行済みフラグまたはデバウンスで蓄積を防止
- [x] 不要になったコールバックが再登録されないガード条件を追加
- [x] `homeScrollToTopProvider` の scroll-to-top リスナーを整理 — `HomeScreen.build()` の `ref.listen` は outer NestedScrollView（ヘッダー折りたたみ）、`_PostsList.initState()` の `ref.listenManual` は inner リストコントローラ（リスト先頭へスクロール）を操作。異なるコントローラの分担のため意図的に両方保持。
- [x] 画面回転時のスポットライト追従を追加（`WidgetsBindingObserver.didChangeMetrics`）

**実装時の補足**:
- ルート依存の強制ナビゲーション（チュートリアル、サークルアクセス制御）は `GoRouterState.of(context)` に依存するため `build()` 内に残し、`_scheduleNavigation` ガードで蓄積防止
- BANリダイレクトは `_isForcingBanRedirect` で独立管理（チュートリアルナビとの競合防止）
- Rect解決の非同期競合は `_pending` パターンで対処（`_pendingSpotlightKey`、`_pendingFirstPostRectRefresh`）

**関連ファイル**:
- `lib/features/home/presentation/screens/main_shell.dart`
- `lib/features/home/presentation/screens/home_screen.dart`
- `lib/features/profile/presentation/screens/profile_screen.dart`
- `lib/features/profile/presentation/screens/settings_screen.dart`

---

## 3. 画像読み込み最適化（Widget Wrapper 方式）

**方針**: 画像種別ごとにポリシーを定義した共通 `AppImage` Widget を作成

**確認済みの問題**:
- 画像読み込みポリシーが画面ごとに未統一（`Image.network` 11箇所、`CachedNetworkImage` 混在）
- `CachedNetworkImage` 使用箇所にも `memCacheWidth`/`memCacheHeight` 等の縮小デコード指定なし
- フルサイズ画像がそのままメモリに展開され、低スペック端末でメモリ圧迫
- 注: `Image.network()` も Flutter のメモリキャッシュは利用するが、ディスクキャッシュやデコードサイズ制御がない

**画像種別ポリシー**:

| 種別 | memCacheWidth | 用途 | 縮小デコード |
|------|-------------|------|------------|
| avatar | 80〜160px | プロフィールアイコン | する |
| thumbnail | 300〜400px | 投稿カードのメディア | する |
| cover | 画面幅程度 | サークルヘッダー等 | する |
| fullscreen | 制限なし | フルスクリーン表示 | **しない**（InteractiveViewerでのピンチズームがぼけるため） |

**対策**:
- [ ] `lib/shared/widgets/app_image.dart` を新規作成（`AppImage.avatar` / `.thumbnail` / `.cover` / `.fullscreen` ファクトリ）
- [ ] 全 `Image.network()` を `AppImage` の適切な種別に置換
- [ ] 既存 `CachedNetworkImage` 直接使用箇所も `AppImage` に統一

**該当箇所**（`Image.network` 使用箇所）:
1. `lib/shared/widgets/avatar_selector.dart` (L148)
2. `lib/features/profile/presentation/widgets/profile_header.dart` (L46)
3. `lib/features/circle/presentation/widgets/circle_header.dart` (L81, L131)
4. `lib/features/circle/presentation/screens/circles_screen.dart` (L1232)
5. `lib/features/profile/presentation/screens/settings_screen.dart` (L1073, L1139)
6. `lib/features/admin/presentation/screens/admin_inquiry_detail_screen.dart` (L552)
7. `lib/features/settings/presentation/screens/inquiry_detail_screen.dart` (L414)
8. `lib/shared/widgets/full_screen_image_viewer.dart` (L46, L73)

**関連ファイル**:
- 上記該当箇所 + `lib/features/home/presentation/widgets/post_card.dart`

---

## 4. リアクションアニメーション最適化

**確認済みの問題**:
- `_buildEpicSparkles()` がエピックリアクション1件につき20個×2レイヤー=40ウィジェット生成
- epic glow の `blurRadius: 26` が主な描画負荷源
- `Transform` と `Opacity` を含む多段構造が各ウィジェットに適用
- epic burst エフェクト発動時が主なコスト源（定常時は問題小）

**対策**:
- [ ] エピックスパークル widget 数を削減（20→8〜10個）
- [ ] epic glow の `blurRadius: 26` を縮小または簡略化
- [ ] `AnimationController` のクリーンアップ確認（主論点ではないが副次的に対応）

**実装時の注意**:
- Epic演出はユーザー体験の重要な要素。削減しすぎると演出が貧弱になるため、**視覚的な劣化が最小限になるバランス**をDevToolsのGPU使用率を見ながら調整する
- 将来的に低スペック端末検出 → エフェクト品質自動調整も検討可能

**関連ファイル**:
- `lib/features/home/presentation/widgets/reaction_background.dart`

---

## 5. Provider リビルド最適化

**確認済みの問題**:
- `main_shell.dart` (L338-345): `ref.watch(currentUserProvider)` 他6つの Provider を `.select()` なしで監視
- `home_screen.dart` (L62, L70): 同様に全体監視

**対策**:
- [ ] `currentUserProvider` を使用箇所で `.select()` し、必要フィールドのみ監視
- [ ] `main_shell.dart` のチュートリアル Provider 群は、Consumer 境界を分割して監視範囲を局所化（`.select()` 追加よりも効果的）
- [ ] DevTools で不要リビルドが減少したことを確認

**Codexからの指摘**:
tutorial-step Provider は enum 変更時にシェル全体が再構築されるのは意図通りの場合がある。`.select()` 追加よりも、`currentUser` 由来のフィールドとチュートリアルオーバーレイを小さな Consumer サブツリーに分離する方が効果的。

**関連ファイル**:
- `lib/features/home/presentation/screens/main_shell.dart`
- `lib/features/home/presentation/screens/home_screen.dart`

---

## 6. Follow Feed クエリ改善（段階的ロードマップ）

**確認済みの問題**:
- `whereIn` クエリが `followingIds.take(10)` で先頭10件に制限 → **11人以上フォローすると一部の投稿が表示されない（正しさの欠陥）**
- `snapshots()` によるリアルタイム監視自体はイベント駆動であり問題ない（ポーリング化は後退）
- 本質的な問題はクエリの構成とリビルド範囲

**Codexからの補足**:
- `snapshots()` のリアルタイム監視をポーリングに変更するのは後退。維持すべき。
- Firestoreオフラインパーシステンスの有無は未確認事項であり、確定診断ではない。

### Phase 1: Chunked Query ✅ 完了

`whereIn` の10件制限を、クライアント側でクエリ分割して対応。

- [x] `followingIds` を10件ずつチャンクに分割
- [x] 各チャンクで並列クエリを実行
- [x] 結果をクライアント側で `createdAt` 順にマージ
- [x] ページネーションとの整合性を確認
- [x] `_loadGeneration` による stale request guard
- [x] フォロー100超の監視ログ（Phase 2 移行判断用）

**詳細設計書**: `docs/specs/2026-03-10_chunked_follow_feed.md`

### Phase 2: Fan-out on Write（本番後）

投稿時に Cloud Function がフォロワー全員の timeline コレクションに書き込む方式。

- [ ] `users/{userId}/timeline/{postId}` コレクション設計
- [ ] 投稿 trigger で Cloud Tasks を使いバッチ書き込み（500件/バッチ）
- [ ] 投稿削除時の soft delete + 読み取り時フィルタ
- [ ] timeline エントリの TTL 設定（30日等）

### Phase 3: ハイブリッド（数万人規模）

フォロワー数に応じて fan-out / pull を切り替える方式。

- [ ] 閾値（例: フォロワー500人）以上のユーザーは pull 型に切替
- [ ] クライアントで fan-out 済み timeline + 人気ユーザーの最新投稿をマージ

**関連ファイル**:
- `lib/features/home/presentation/screens/home_screen.dart`

---

## 7. リストスクロール最適化

**確認済みの問題**:
- 複数の `ListView.builder` で `itemExtent` 未指定

**Codexからの補足**:
ホームフィード（投稿カード + 広告 + ローディング行の混在）や通知一覧等の可変高リストには `itemExtent` は適用不可。対象は**明確に固定高さのリスト**に限定すること。

**対策**:
- [ ] 固定高さのリスト（水平フォロー一覧等）に `itemExtent` を追加
- [ ] 可変高リストは対象外とする

**関連ファイル**:
- `lib/features/profile/presentation/widgets/profile_following_list.dart`
- その他、固定高さが確認できる `ListView.builder` 使用箇所

---

## 8. プロフィール投稿一覧 shrinkWrap 撤去

**DevTools実測で確認済み（2026-03-11）**:
- Frame 14412: Build 31.0ms / Paint 5.2ms / Raster 10.8ms
- スクロール開始時にのみ発生するジャンク

**確認済みの問題**:
- `ProfilePostsList` が `SliverToBoxAdapter` 内で `ListView.builder(shrinkWrap: true, NeverScrollableScrollPhysics)` を使用
- 全投稿（30件+）を一括でbuild/layoutするため、Build 31msの主因
- Codex評価でも Rank 1（最有力原因）と判定

**対策（3フェーズ）**:
- [x] Phase A: `shrinkWrap: true` → `SliverMainAxisGroup` + `SliverList.builder` 変換（実装完了・実機確認済み）
- [ ] Phase B: `_loadFavorites()` の遅延読み込み化 — 保留（Phase Aで許容範囲まで改善のため）
- [ ] Phase C: 各投稿カードの `FutureBuilder<DocumentSnapshot>` バッチ化 — 保留（同上）

**既に適用済みの関連最適化**:
- `_isBottomNavVisible` → `ValueNotifier<bool>` + `ValueListenableBuilder`（main_shell.dart）
- `_showScrollToTopFab` → `ValueNotifier<bool>` + `ValueListenableBuilder`（profile_screen.dart）
- 水平スクロールフィルタ追加

**関連ファイル**:
- `lib/features/profile/presentation/widgets/profile_posts_list.dart`
- `lib/features/profile/presentation/screens/profile_screen.dart`
- `lib/features/home/presentation/screens/main_shell.dart`

**詳細設計書**: `docs/specs/2026-03-11_profile_scroll_jank_fix.md`

---

## 次点候補（将来対応）

### N+1 読み込み: profile_following_list

`profile_following_list.dart` では、横スクロール項目ごとに `FutureBuilder<DocumentSnapshot>` を発行している。既存の `publicUserDocProvider` を使えばキャッシュ活用が可能。

今回のスコープ外だが、データ取得効率の改善候補として記録する。

**関連ファイル**:
- `lib/features/profile/presentation/widgets/profile_following_list.dart` (L43)
- `lib/shared/providers/public_user_provider.dart`

---

## 未確認事項（要調査）

| 項目 | 詳細 | 調査方法 |
|------|------|---------|
| Firestore オフラインパーシステンス | `main.dart` に明示設定がないが、Flutter Firebase SDK のデフォルト挙動を確認する必要あり | SDK ドキュメント確認 + 実機でオフラインテスト |

---

## リスクと対策

| リスク | 対策 |
|--------|------|
| チュートリアルのタップ透過が壊れる | passThroughSpotlight の単一マスク化はプロトタイプ後に判断 |
| Epic演出の視覚的劣化 | スパークル削減は DevTools GPU 計測しながらバランス調整 |
| フルスクリーン画像がぼける | `AppImage.fullscreen` は縮小デコードしない |
| Follow feed の Phase 1 で Firestore 読み取りコスト増 | フォロー数÷10のクエリが並列発行（30人→3クエリ）。数十人程度なら許容範囲 |
| Follow feed の Phase 2 で Firestore 書き込みコスト増 | 投稿1回×フォロワー数の writes が発生。コスト試算を設計時に実施すること |

---

## 実施順序（推奨）

1. **#2 post-frame callback 整理** — 低コスト・高効果・既存仕様への影響なし
2. **#6 Phase 1 Chunked Query** — 正しさの欠陥修正（フォロー11人以上で投稿欠落）
3. **#3 画像 Widget Wrapper** — メモリ圧迫の根本対策
4. **#1 チュートリアルオーバーレイ** — CT-017 の直接対応
5. **#5 Provider リビルド** — Consumer 境界分割
6. **#4 リアクションアニメーション** — Epic burst 時のみの問題、慎重に調整
7. **#7 リストスクロール** — 固定高リストのみ、低優先度
8. **#8 プロフィール投稿一覧 shrinkWrap 撤去** — DevTools実測済み、Phase A 低コスト高効果
