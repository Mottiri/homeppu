# Flutter ヘルパー実装レビュー（SnackBar / Dialog）

## 目的

`SnackBarHelper` / `DialogHelper` / `AppMessages` の実装について、開発運用上・セキュリティ上のリスク有無を確認し、改善提案をまとめる。

> 注: 当初の依頼は「計画ファイルの参照」と「ヘルパー実装の評価」であり、既存コードへの適用（置き換え実装）は依頼範囲外だった。誤って一部適用差分が入っているため、本資料に現状差分の評価と対応案も含める。

## 対象

- `lib/core/utils/snackbar_helper.dart`
- `lib/core/utils/dialog_helper.dart`
- `lib/core/constants/app_messages.dart`（エラーメッセージ設計の観点）
- （今回の誤適用差分）
  - `lib/features/tasks/presentation/screens/tasks_screen.dart`
  - `lib/features/circle/presentation/screens/circle_detail_screen.dart`

## 結論（重要度順）

### 1) セキュリティ/運用上の主要リスク: 例外詳細のユーザー露出

- 画面上の `SnackBar` に `$e` を含む例外内容をそのまま表示している箇所がある。
- 例外文字列には以下が混在し得るため、ユーザー向け表示としては過剰な情報になり、運用上もノイズが多い。
  - 内部実装の断片、Firestore の権限/ルールのヒント、ID、バリデーション詳細、スタック断片、ネットワーク状態等
- 推奨:
  - ユーザー表示は `AppMessages.error.general` など一般化された文言に寄せる
  - 詳細はログ（Crashlytics 等）へ送る/開発ビルドのみ `kDebugMode` で表示する

### 2) 運用上の主要リスク: `context` 前提による例外/表示失敗

- `SnackBarHelper` は `ScaffoldMessenger.of(context)` を前提としているため、Scaffold の外側や別 Navigator 階層の `context` で呼ぶと例外になり得る。
- 推奨:
  - `ScaffoldMessenger.maybeOf(context)` を使い、取得できない場合は no-op または `debugPrint` のみにする
  - もしくは「必ず Scaffold 配下で呼ぶ」運用ルールを明文化する（ただし実装側で防御する方が堅い）

### 3) UX/誤操作リスク: 危険操作のダイアログが外側タップで閉じ得る

- `showDialog` のデフォルト動作では、外側タップ等で閉じられる（戻り値は `null` → `false` 扱い）。
- 重大操作（削除/退会等）で「意図しないキャンセル」や「確認の強制」要件がある場合、要件不一致になり得る。
- 推奨:
  - `DialogHelper.showConfirmDialog` に `barrierDismissible` オプションを追加し、危険操作は `false` を選べるようにする

## 実装レビュー

### SnackBarHelper（`lib/core/utils/snackbar_helper.dart`）

良い点:
- アプリ全体で見た目（色・角丸・floating・余白・アイコン）を統一できる。
- `hideCurrentSnackBar()` により多重表示を抑制し、運用上の視認性が上がる。

改善提案:
- `ScaffoldMessenger.of(context)` 前提を緩める（`maybeOf` 化 + no-op）。
- 色は `AppColors` に寄せられているが、テキストカラーは固定（白）なので、将来テーマ変更時にコントラスト要確認。
- 例外詳細（`$e`）を直接表示する運用を避ける（呼び出し側のルール化/ヘルパー側のAPI設計で誘導）。

今回の差分:
- `showSuccess/showError/showInfo/showWarning` に `duration` 引数を追加。
  - 評価: 妥当（呼び出し側がメッセージ重要度に応じて表示時間を調整できる）。

### DialogHelper（`lib/core/utils/dialog_helper.dart`）

良い点:
- `confirm/delete/input` の頻出パターンが統一され、UIの一貫性と保守性が上がる。
- `TextEditingController` を `dispose()` しておりリソース管理が適切。

改善提案:
- 危険操作の誤タップ/外側タップ対策として `barrierDismissible` を制御可能にする。
- `showInputDialog` は入力値のバリデーション（空文字、最大長、禁止文字など）を呼び出し側に委ねている。必要なら `validator` を受け取る設計も検討。

### AppMessages（`lib/core/constants/app_messages.dart`）

良い点:
- 画面ごとのハードコードを減らし、文言の統一・将来の i18n 対応に寄与する。

改善提案（運用/セキュリティ寄り）:
- `withDetail(String detail)` を UI 表示に使うと情報過多/情報漏えいに繋がり得る。
  - 推奨: UI 表示用の API と、ログ用の API を分ける（例: `error.general` と `error.debugDetail(e)` のような設計）。

## （参考）今回の誤適用差分の評価

### `tasks_screen.dart` の置き換え

良い点:
- 直書き `SnackBar` の統一が進み、体裁が揃う。
- カテゴリ追加/リネーム/削除のダイアログを `DialogHelper` に寄せられる。

注意点（運用/安定性）:
- `await` 後に画面が破棄されている可能性があるため、後続処理の前に `if (!mounted) return;` を入れるとより安全。
- エラー時に `$e` を UI 表示している箇所が残るため、上記「例外詳細のユーザー露出」リスクは継続。

### `circle_detail_screen.dart` の置き換え

良い点:
- join/leave の確認ダイアログが共通化され、保守性が上がる。
- BAN 表示の文言が `AppMessages` に寄せられる。

注意点（UX）:
- 元の UI で `ElevatedButton` だった箇所が `DialogHelper` の `TextButton` に寄るため、CTA の強さが変わり得る（要合意）。
- エラー表示で `withDetail('$e')` を UI に出しており、情報露出リスクあり。

## 対応案（選択肢）

### A. 誤適用差分は全て取り消す（推奨：依頼範囲の厳密遵守）

- 今回の目的（レビュー）に戻し、既存画面への適用は別PR/別タスクで合意してから実施する。

### B. 誤適用差分は残し、最小限の安全対策のみ追加して整える

- 例外詳細のユーザー露出を撤廃（一般メッセージ + ログ）
- `mounted` ガードの追加
- `SnackBarHelper` の `maybeOf` 化
- 危険ダイアログの `barrierDismissible` オプション追加（必要なら）

## 付録: 現状の変更ファイル一覧（未コミット）

- `lib/core/utils/snackbar_helper.dart`（duration 引数追加）
- `lib/features/tasks/presentation/screens/tasks_screen.dart`（SnackBar/Dialog の一部置き換え）
- `lib/features/circle/presentation/screens/circle_detail_screen.dart`（SnackBar/Dialog の一部置き換え）
