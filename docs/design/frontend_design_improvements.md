# Frontend Design Skill 実装記録

**実装日**: 2026-01-03
**ベース**: Claude Code Frontend Design Skill原則

---

## 実装概要

Frontend Design Skillの設計思考プロセスに基づき、ほめっぷアプリのUIを「一般的なAI美学」から脱却させ、より**記憶に残る独自性のあるデザイン**に改善しました。

---

## 実装した改善

### 1. タイポグラフィの改善 ✅

**変更前**: Noto Sans JP のみ（汎用的）
**変更後**: Zen Maru Gothic（見出し） + Noto Sans JP（本文）

#### 実装内容
- **Display/Headline**: `GoogleFonts.zenMaruGothic()` - 親しみやすさと個性を演出
- **Title/Body**: `GoogleFonts.notoSansJp()` - 読みやすさ重視
- **Letter Spacing**: 見出しに `0.3〜0.5` の文字間隔で視認性向上

#### 対象ファイル
- [lib/core/theme/app_theme.dart](../../lib/core/theme/app_theme.dart:208-247)

#### 効果
- ✅ 一般的なフォントから脱却
- ✅ 「優しさ・温かさ」のコンセプトを強化
- ✅ 見出しと本文の階層が明確に

---

### 2. 背景・視覚的詳細の強化 ✅

**変更前**: 単純な2色グラデーション
**変更後**: 複雑な3色メッシュ風グラデーション + 放射状グラデーション

#### 実装内容
- **warmGradient**: 3色（`#FFF8F2` → `#FFF3E8` → `#FFEFDB`）で深みを演出
- **heroGradient**: 放射状グラデーション（ヒーロー要素用）
- **cardGradient**: 立体的な3色グラデーション
- **Shadow強化**: elevation 2 → 6、複数の影で深さを表現

#### 対象ファイル
- [lib/core/constants/app_colors.dart](../../lib/core/constants/app_colors.dart:50-101)
- [lib/core/theme/app_theme.dart](../../lib/core/theme/app_theme.dart:51-58)

#### 効果
- ✅ ソリッドカラーから脱却
- ✅ グラデーションメッシュで大気感を創出
- ✅ より劇的な影で立体感を強調

---

### 3. アニメーション強化 ✅

**変更前**: ほぼアニメーションなし
**変更後**: ステージ化されたエントランスアニメーション + マイクロインタラクション

#### 実装内容

##### ログイン画面
- **ロゴ**: fadeIn → scale（弾性） → shimmer（繰り返し）
- **見出し**: fadeIn + slideY（200ms遅延）
- **サブテキスト**: fadeIn + slideY（400ms遅延）
- **フォーム**: fadeIn + slideX（600-700ms遅延）
- **ボタン**: fadeIn + scale（800ms遅延）

##### ホーム画面
- **ロゴ**: 繊細なshimmer（3秒周期、無限ループ）
- **背景**: 放射状グラデーションで視覚的変化

#### 対象ファイル
- [lib/features/auth/presentation/screens/login_screen.dart](../../lib/features/auth/presentation/screens/login_screen.dart:87-255)
- [lib/features/home/presentation/screens/home_screen.dart](../../lib/features/home/presentation/screens/home_screen.dart:63-75)

#### 効果
- ✅ ページロード時の「高インパクトな瞬間」を創出
- ✅ animation-delay でステージ化された表示
- ✅ 予測可能な単調さから脱却

---

### 4. 空間構成の改善 ✅

**変更前**: 左右対称の標準カードレイアウト
**変更後**: 非対称マージン + 深い影 + マイクロインタラクション

#### 実装内容
- **EnhancedCard**: 新規共通ウィジェット作成
  - 偶数/奇数で左右マージンを変更（16-24 / 24-16）
  - タップ時の影の変化（マイクロインタラクション）
  - 二重影で深さを強調
- **borderRadius**: 20 → 24（より大胆な丸み）

#### 対象ファイル
- [lib/shared/widgets/enhanced_card.dart](../../lib/shared/widgets/enhanced_card.dart) ★新規作成

#### 効果
- ✅ 予測可能なレイアウトから脱却
- ✅ 非対称性で視覚的な変化を創出
- ✅ マイクロインタラクションで応答性を強化

---

## Frontend Design Skill原則との対応

### ✅ 採用した原則

| 原則 | 実装内容 |
|------|---------|
| **個性的なフォント** | Zen Maru Gothic（丸ゴシック）で親しみやすさ |
| **統一された美学** | 暖色系パステル + コーラルピンクで一貫性 |
| **支配的な色 + 強調色** | コーラルピンク（主）+ 各リアクション色（強調） |
| **ステージ化されたアニメーション** | 200-800ms遅延で順次表示 |
| **グラデーションメッシュ** | 3色グラデーションで深みを演出 |
| **劇的な影** | elevation 6 + 二重影で立体感 |
| **非対称性** | カードの左右マージンを交互に変化 |
| **マイクロインタラクション** | タップ時の影変化 |

### ⚠️ 今後の拡張可能性

| 原則 | 実装案 |
|------|--------|
| **スクロールトリガー** | `ScrollController` + `AnimatedBuilder` で実装可能 |
| **ノイズテクスチャ** | `CustomPaint` でグレインオーバーレイ追加 |
| **装飾的なボーダー** | カード周辺に装飾線を追加 |
| **より大胆な非対称** | `CustomScrollView` + `Sliver` でグリッド破壊 |

---

## 美学的方向性の再定義

### Before（汎用的なAI美学）
- Noto Sans JP のみ
- 単純な2色グラデーション
- elevation 2 の軽い影
- アニメーションなし
- 左右対称の予測可能なレイアウト

### After（ほめっぷ独自の美学）
- **トーン**: ソフト/パステル + 遊び心（Playful）
- **タイポグラフィ**: 丸ゴシック（親しみ）+ 明朝体（読みやすさ）
- **色彩**: 暖色メッシュグラデーション + 層状の透明性
- **動き**: ステージ化されたエントランス + 繊細なshimmer
- **空間**: 非対称マージン + 深い影で立体感

---

## 技術スタック

| 技術 | 用途 |
|------|------|
| `flutter_animate: ^4.5.2` | アニメーション（既存パッケージ） |
| `google_fonts: ^6.2.1` | フォント（Zen Maru Gothic追加） |
| `CustomPaint`（未実装） | ノイズテクスチャ・装飾要素 |

---

## パフォーマンス考慮事項

### ✅ 実装済み対策
- アニメーション duration: 300-800ms（短めで快適）
- shimmer は `onPlay: repeat()` で効率的なループ
- グラデーションは `const` で再構築を最小化
- 影は2層まで（過度な重ね合わせを回避）

### ⚠️ 今後の注意点
- 大量のカード表示時のアニメーション負荷
- 放射状グラデーションのレンダリングコスト
- 画像の多い投稿でのメモリ使用量

---

## 次のステップ

### Phase 2（中期）
1. **PostCard への EnhancedCard 適用**
   - 投稿一覧で非対称レイアウトを実装
   - リスト内での index を渡して交互配置

2. **スクロールトリガーアニメーション**
   - 投稿が画面に入ったタイミングでアニメーション
   - `ScrollController` でスクロール位置を監視

3. **ノイズテクスチャ追加**
   - `CustomPaint` でグレインオーバーレイ
   - 背景に微細なノイズで質感を追加

### Phase 3（長期）
1. **カスタムシェイプ**
   - 投稿カードの一部を斜めにカット
   - 装飾的なボーダーやコーナー

2. **より大胆なレイアウト破壊**
   - サークル詳細画面でオーバーラップレイアウト
   - 対角線フローの実験

3. **インタラクティブ装飾**
   - カーソル追従エフェクト（Web版）
   - 長押し時の波紋エフェクト

---

## 参考資料

- [Frontend Design Skill - GitHub](https://github.com/anthropics/claude-code/blob/main/plugins/frontend-design/skills/frontend-design/SKILL.md)
- [CONCEPT.md](../../CONCEPT.md) - ほめっぷのコンセプト
- [FEATURES.md](../../FEATURES.md) - 機能一覧

---

**実装者**: Claude Sonnet 4.5
**レビュー**: 未実施（実装直後）
