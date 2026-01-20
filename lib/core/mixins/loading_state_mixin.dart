import 'package:flutter/widgets.dart';

/// アクション時のローディング状態を管理するMixin
///
/// ボタン押下時などの一時的なローディング状態を管理します。
/// 二重実行防止と`mounted`チェックを内包しています。
///
/// 使用例:
/// ```dart
/// class _MyScreenState extends State<MyScreen> with LoadingStateMixin {
///   Future<void> _submit() async {
///     await runWithLoading(() async {
///       await someAsyncOperation();
///     });
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return ElevatedButton(
///       onPressed: isLoading ? null : _submit,
///       child: isLoading
///           ? CircularProgressIndicator()
///           : Text('送信'),
///     );
///   }
/// }
/// ```
mixin LoadingStateMixin<T extends StatefulWidget> on State<T> {
  bool _isLoading = false;

  /// 現在のローディング状態
  bool get isLoading => _isLoading;

  /// ローディング状態で処理を実行（二重実行防止付き）
  ///
  /// [action]が実行中は`isLoading`が`true`になります。
  /// 既にローディング中の場合は`null`を返して処理をスキップします。
  ///
  /// 例外が発生した場合は呼び出し元で処理してください。
  /// セキュリティルール: UIには一般化メッセージのみ表示し、詳細はログへ。
  Future<R?> runWithLoading<R>(Future<R> Function() action) async {
    if (_isLoading) return null;

    setState(() => _isLoading = true);

    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// ローディング状態を直接設定
  ///
  /// 複雑な制御が必要な場合に使用します。
  /// 通常は[runWithLoading]を使用してください。
  void setLoading(bool value) {
    if (mounted) {
      setState(() => _isLoading = value);
    }
  }
}
