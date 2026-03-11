# スタンプシート画面 Raster Jank 修正

**作成日**: 2026-03-11
**起源**: 性能改善設計書 #9（DevToolsプロファイリングで確認）
**ステータス**: C1-C5 実装完了・実機確認済み、C4・C6-C9 は保留（低速端末実機確認で許容範囲と判断、2026-03-11）
**次のアクション担当者**: なし（性能改善全体が保留。再開条件は性能改善設計書を参照）

---

## 背景

スタンプシート画面でスタンプ押下アニメーション中に重度のジャンクが発生する。
DevToolsプロファイリングの結果、Raster: 81.7ms / 24 FPS が主因と判明。
Build時間ではなくGPUコンポジティングコスト（Raster）がボトルネック。

---

## DevToolsプロファイリング結果（修正前）

| 項目 | 値 |
|---------|--------|
| Raster | 81.7ms |
| FPS | 24 |
| Build | 高（StreamBuilder全体リビルド） |

60FPS 達成には 1フレーム 16.6ms 以内が必要。Raster 81.7ms は約5フレーム分。

---

## Codex評価結果（2026-03-11）

### 主要原因（優先度順）

| # | 対策ID | 原因 | 影響度 | 対応状況 |
|---|--------|------|--------|---------|
| 1 | C1 | StreamBuilder が画面全体をリビルド（配置データ更新のたび） | 高 | 対応済み |
| 2 | C3 | Opacity widget が saveLayer（GPUオフスクリーンバッファ）を13個生成 | 高 | 対応済み |
| 3 | C2 | 配置済みスタンプがフレームごとに再ラスタライズ | 中 | 対応済み |
| 4 | C5 | ConfettiWidget が非再生時もレイヤーコストを発生 | 低中 | 対応済み |
| 5 | C4 | BackdropFilter（ぼかし効果）のGPUコスト | 高 | 保留（見た目変更） |
| 6 | C6-C9 | パーティクル数削減、アニメーション簡略化等 | 低 | 保留 |

---

## 対応済みの最適化一覧

### C1: StreamBuilder スコープ縮小（実装済み）

| 対策 | 効果 |
|------|------|
| StreamBuilder のスコープを画面全体 → Column(ヘッダー + キャンバス)のみに縮小 | 配置データ更新時のリビルドがConfetti・StampBar・FAB・チュートリアルオーバーレイに波及しなくなった |
| `state.initialized` 初期化ロジックをStreamBuilder外に移動 | `selected == null`（初回シート未選択）パスでも初期化が確実に実行される |
| `localBySlotSeeded` フラグ追加 | StreamBuilder内での配置データ初回同期を安全に制御 |
| `_mapEquals` → Flutter標準 `mapEquals` | 変更検知ガードに標準ライブラリを使用 |

**変更前の構造**:
```
StreamBuilder(placement stream)
  └─ Stack（画面全体）
       ├─ ヘッダー（クレジット表示 + Undo）
       ├─ _SheetCanvas（スタンプシート）
       ├─ ConfettiWidget
       ├─ StampBar
       ├─ FAB
       └─ TutorialOverlay × 5
```

**変更後の構造**:
```
Stack
  ├─ StreamBuilder(placement stream)  ← スコープ縮小
  │    └─ Column
  │         ├─ ヘッダー（クレジット表示 + Undo）
  │         └─ _SheetCanvas（スタンプシート）
  ├─ if (_confettiPlaying) ConfettiWidget  ← 遅延挿入
  ├─ StampBar
  ├─ FAB
  └─ TutorialOverlay × 5
```

### C3: Opacity → BlendMode.modulate 変換（実装済み）

| 対策 | 効果 |
|------|------|
| スタンプ本体: `Opacity` widget → `Image.asset(color: Color.fromRGBO(255, 255, 255, op), colorBlendMode: BlendMode.modulate)` | saveLayer 排除（GPUオフスクリーンバッファ不要） |
| パーティクル: `Opacity` widget → `TextStyle.color.withValues(alpha: opacity)` | saveLayer 排除（12パーティクル分） |

**実機計測結果**: Raster 81.7ms → 17.5ms（79%削減）、FPS 24 → 34

### C2: RepaintBoundary 追加（実装済み）

| 対策 | 効果 |
|------|------|
| `_SheetCanvas` 内の各配置済みスタンプに `RepaintBoundary` を追加 | 変更のないスタンプのラスタライズ結果をキャッシュ、再描画コスト削減 |

### C5: ConfettiWidget 遅延挿入（実装済み）

| 対策 | 効果 |
|------|------|
| `_confettiPlaying` フラグで `ConfettiWidget` を再生中のみWidgetツリーに挿入 | アイドル時のレイヤーコスト排除 |
| `_confettiController.addListener` で再生状態を監視、`dispose` で解除 | リソースリーク防止 |

---

## 実機確認結果（全最適化適用後）

| 指標 | 修正前 | C1後 | C3後 | C2+C5後 |
|------|--------|------|------|---------|
| Raster | 81.7ms | 60.9ms | 17.5ms | ~17ms |
| FPS | 24 | 21 | 34 | 36（末尾60） |
| Build | 高 | 1.0ms | 1.0ms | 1.0ms |

- **改善効果**: Raster 81.7ms → ~17ms（79%削減）、FPS 24 → 36
- **体感**: ユーザーから「大分改善してきた」との報告
- **残存ジャンク**: アニメーション開始直後の数フレームで軽微なジャンクが残る（初回テクスチャロード等）

---

## 未対応項目と保留理由

### C4: BackdropFilter 除去 — 保留

**内容**: スタンプシートのぼかし効果を除去してGPUコストを削減する。
**保留理由**: 見た目が変わるため、デザイン判断が必要。現状の36 FPSで許容範囲。

### C6-C9: パーティクル・アニメーション簡略化 — 保留

**内容**: パーティクル数削減、アニメーション曲線簡略化等。
**保留理由**: 効果が限定的（各1-2ms程度の改善見込み）。体感改善が既に得られているため優先度低。

---

## 変更ファイル一覧

| ファイル | 変更内容 |
|---------|---------|
| `lib/features/stamps/presentation/screens/stamp_sheet_screen.dart` | C1/C2/C3/C5全最適化、`mapEquals`使用、`creditsLabel`修正、初期化ロジック移動 |

---

## まとめ

Rasterバウンドのジャンク（81.7ms/24FPS）を、saveLayer排除（C3）を主軸に、StreamBuilderスコープ縮小（C1）、RepaintBoundary（C2）、ConfettiWidget遅延挿入（C5）の4施策で17ms/36FPSまで改善。実機確認で「大分改善してきた」とユーザー判断で現時点の対応完了とした。

**リスクと対策**: 全施策はパフォーマンス改善のみで、UI/機能に変化なし。Codex archレビューで指摘された初期化スキップ問題は修正済み。
**次のアクション担当者**: なし（将来的にC4が必要になった場合は本設計書を参照）
