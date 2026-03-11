# プロフィール画面スクロール開始時ジャンク修正

**作成日**: 2026-03-11
**起源**: 性能改善設計書 #8（DevToolsプロファイリングで確認）
**ステータス**: Phase A 実装完了・実機確認済み、Phase B・C は保留
**次のアクション担当者**: なし（現時点で対応完了）

---

## 背景

プロフィール画面でスクロールを開始した瞬間にカク付き（ジャンク）が発生する。
DevToolsプロファイリングの結果、Build: 31.0ms が主因と判明。

---

## DevToolsプロファイリング結果（修正前）

| 項目 | 値 |
|------|-----|
| Frame | 14412 |
| 判定 | UI Jank Detected |
| Build | 31.0ms（最長フェーズ） |
| Paint | 5.2ms |
| Raster | 10.8ms |
| Total UI | 36.9ms |
| Total Raster | 10.5ms |
| 別フレーム Duration | 58ms |

60FPS 達成には 1フレーム 16.6ms 以内が必要。Build 31ms は約2フレーム分。

---

## Codex評価結果（2026-03-11）

### 主要原因（優先度順）

| # | 原因 | 影響度 | Phase | 対応状況 |
|---|------|--------|-------|---------|
| 1 | `shrinkWrap: true` + `NeverScrollableScrollPhysics` で全カードを一括build/layout | 高 | A | 対応済み |
| 2 | 初期表示時に `_loadFavorites()` も同時実行（非表示タブの先読み） | 高 | B | 保留 |
| 3 | 各投稿カードの `FutureBuilder<DocumentSnapshot>`（circle名取得）がカード数分発火 | 中高 | C | 保留 |

### 副次的原因

| 原因 | 影響度 | 対応状況 |
|------|--------|---------|
| ヘッダー/プロフィール画像の `Image.network` 初回decode | 中 | 未対応 |
| `ProfileStats` の `IntrinsicHeight` レイアウトコスト | 低中 | 未対応 |
| `InfiniteScrollListener` + `NotificationListener` 二重スクロール通知 | 低中 | 未対応 |
| `ref.watch(currentUserProvider)` による画面全体再構築 | 条件付き | 未対応 |
| チュートリアル有効時のoverlay/rect解決 | 条件付き | 未対応 |
| AnimatedAlign アニメーション中のレイアウトコスト（ボトムナビ表示切替） | 低中 | 未対応 |

### Codex結論
> 単独要因ではなく、shrinkWrap構造の重さ + 非表示タブ先読み + カード単位非同期取得が複合的に31msを生んでいる可能性が高い

---

## 対応済みの最適化一覧

### Phase A: shrinkWrap → SliverList.builder 変換（実装済み）

| 対策 | ファイル | 効果 |
|------|---------|------|
| `SliverToBoxAdapter` + `ListView.builder(shrinkWrap: true)` → `SliverMainAxisGroup` + `SliverList.builder` | profile_posts_list.dart | 全30件+の一括build/layoutを解消。画面内のアイテムのみ遅延ビルドに変更 |

**変更前の構造**:
```
ProfilePostsList (StatefulWidget)
  └─ build() → SliverToBoxAdapter
       └─ Column
            ├─ TabBar（タブUI）
            └─ _buildPostList() → ListView.builder(shrinkWrap: true, NeverScrollableScrollPhysics)
                 └─ ProfilePostCard × 30件+（全件build/layout）
```

**変更後の構造**:
```
ProfilePostsList (StatefulWidget)
  └─ build() → SliverMainAxisGroup
       ├─ SliverToBoxAdapter → TabBar（タブUI）
       ├─ SliverToBoxAdapter → SizedBox(height: 12)
       └─ _buildPostSliver() → SliverList.builder
            └─ ProfilePostCard（画面内のみbuild/layout）
```

### 先行最適化（本チケット以前に適用済み）

| 対策 | ファイル | 効果 |
|------|---------|------|
| `_isBottomNavVisible` → `ValueNotifier<bool>` + `ValueListenableBuilder` | main_shell.dart | ボトムナビ表示切替でプロフィール画面全体のrebuildを回避 |
| `_showScrollToTopFab` → `ValueNotifier<bool>` + `ValueListenableBuilder` | profile_screen.dart | FAB表示切替でプロフィール画面全体のrebuildを回避 |
| 水平スクロールフィルタ | main_shell.dart, profile_screen.dart | `notification.metrics.axis != Axis.vertical` で水平スクロール無視 |

---

## 実機確認結果（Phase A 適用後）

- **改善効果**: スクロール開始時のカク付きが大幅に改善
- **残存ジャンク**: 稀にボトムナビの表示/非表示切替タイミングで軽微なカク付きが発生
  - 原因: AnimatedAlign アニメーション中（220ms間）にレイアウトパスが毎フレーム走るため
  - DevToolsで確認: LAYOUT が2段重ねになるフレームが連続するバーストパターン
- **ユーザー判断**: 許容範囲のカク付きであり、現時点で追加対応は不要

---

## 未対応項目と保留理由

### Phase B: お気に入りタブ遅延読み込み — 保留

**内容**: `_loadFavorites()` を `initState()` から削除し、お気に入りタブ選択時のみ実行する。

**保留理由**: Phase A の実装により実機確認でスクロール開始時のジャンクが許容範囲まで改善されたため、追加対応の優先度が下がった。お気に入りタブの先読みは初期表示時の副次的なコストであり、スクロール中のジャンクへの直接的な影響は限定的。将来的にプロフィール画面の初期表示速度が問題になった場合に着手する。

### Phase C: circle名取得のバッチ化 — 保留

**内容**: 各 `ProfilePostCard` の `FutureBuilder<DocumentSnapshot>` を、投稿一覧読み込み時にバッチ取得+キャッシュに変更する。

**保留理由**: Phase A の実装により実機確認でジャンクが許容範囲まで改善されたため、追加対応の優先度が下がった。circle投稿が多いユーザーでは効果が見込めるが、現時点でユーザーから問題報告がないため保留。将来的にcircle機能の利用が増加した場合に着手する。

### 副次的原因群 — 未対応

**保留理由**: いずれも影響度が「低中」〜「条件付き」であり、Phase A 適用後の実機確認で許容範囲のパフォーマンスが得られたため。個別に対応するコスト対効果が低い。性能改善設計書（#1〜#7）の他項目で横断的に対処される可能性もある（例: #1 チュートリアルオーバーレイ最適化、#3 画像読み込み最適化、#5 Provider リビルド最適化）。

### AnimatedAlign アニメーション中のジャンク — 未対応

**内容**: ボトムナビの表示/非表示切替時に AnimatedAlign(heightFactor) がレイアウトパスを毎フレーム発生させる。

**保留理由**: AnimatedAlign を AnimatedSlide のみに置き換える方法は以前試みたが、ボトムナビが非表示の際に空白が残る問題が発生した。AnimatedAlign はレイアウトスペースの確保/解放に必要であり、単純な置き換えは困難。発生頻度が「稀」であり、ユーザーが許容範囲と判断したため現状維持とする。

---

## 変更ファイル一覧

| ファイル | 変更内容 |
|---------|---------|
| `lib/features/profile/presentation/widgets/profile_posts_list.dart` | `shrinkWrap: true` → `SliverMainAxisGroup` + `SliverList.builder` 変換 |
| `lib/features/profile/presentation/screens/profile_screen.dart` | `ValueNotifier<bool>` 化（FAB） |
| `lib/features/home/presentation/screens/main_shell.dart` | `ValueNotifier<bool>` 化（ボトムナビ） |

---

## まとめ

Phase A の `shrinkWrap: true` 撤去により、Build 31ms の主因を解消。実機確認で「稀に軽微なカク付きがある程度」まで改善を確認し、ユーザー判断で現時点の対応完了とした。Phase B・C および副次的原因は、将来的に問題が顕在化した場合に着手する。

**リスクと対策**: Phase A は純粋なパフォーマンス改善で、UI/機能に変化なし
**次のアクション担当者**: なし（将来的にPhase B・Cが必要になった場合は本設計書を参照）
