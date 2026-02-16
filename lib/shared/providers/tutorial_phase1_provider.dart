import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import 'auth_provider.dart';

// TODO(test): QA用の一時フラグ。
// true の間は、tutorialPhase1Completed=true の既存ユーザーでも
// アプリ起動時に Phase1 チュートリアルを再表示する。
// 本番反映前に false に戻すこと。
const bool kForcePhase1TutorialForDebug = true;

/// チュートリアル Phase1 のステップ
enum TutorialPhase1Step {
  inactive, // チュートリアル非アクティブ
  homeWelcome, // Step 0: ホーム画面 / マイページをピックアップ
  profileSettings, // Step 1: マイページ / 設定アイコンをピックアップ
  settingsScroll, // Step 2: 設定画面 / 公開範囲カードへ自動スクロール
  explainAI, // Step 3: AIモード説明
  explainMix, // Step 4: ミックスモード説明
  explainHuman, // Step 5: 人間モード説明
  finished, // Step 6: 完了メッセージ + モード選択必須
}

/// ステップ名 ↔ enum の変換
extension TutorialPhase1StepExt on TutorialPhase1Step {
  String get firestoreValue => name; // enum name をそのまま格納

  static TutorialPhase1Step fromString(String? value) {
    if (value == null) return TutorialPhase1Step.homeWelcome;
    return TutorialPhase1Step.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TutorialPhase1Step.homeWelcome,
    );
  }
}

/// チュートリアル Phase1 の進行管理
class TutorialPhase1Notifier extends StateNotifier<TutorialPhase1Step> {
  TutorialPhase1Notifier(this._ref) : super(TutorialPhase1Step.inactive);

  final Ref _ref;

  /// ユーザー情報からチュートリアル状態を復元/初期化
  void restoreOrStart(UserModel user) {
    if (user.tutorialPhase1Completed && !kForcePhase1TutorialForDebug) {
      state = TutorialPhase1Step.inactive;
      return;
    }
    // 既にアクティブなら何もしない（重複初期化防止）
    if (state != TutorialPhase1Step.inactive) return;

    state = TutorialPhase1StepExt.fromString(user.tutorialPhase1Step);
  }

  /// 現在のステップがアクティブか
  bool get isActive => state != TutorialPhase1Step.inactive;

  /// 次のステップへ進む
  Future<void> advance() async {
    final nextIndex = state.index + 1;
    if (nextIndex >= TutorialPhase1Step.values.length) return;

    final next = TutorialPhase1Step.values[nextIndex];
    state = next;
    await _persistStep(next);
  }

  /// 強制的に特定のステップへ遷移（復元用）
  void jumpTo(TutorialPhase1Step step) {
    state = step;
  }

  /// チュートリアル完了
  /// [postMode] は必須。未選択時は呼び出し側でガードすること。
  Future<void> complete(String postMode) async {
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    final authService = _ref.read(authServiceProvider);
    await authService.updateUserProfile(
      uid: user.uid,
      postMode: postMode,
      extraUpdates: {
        'tutorialPhase1Completed': true,
        'tutorialPhase1Step': null,
      },
    );

    state = TutorialPhase1Step.inactive;
  }

  /// 現在のステップを Firestore に永続化
  Future<void> _persistStep(TutorialPhase1Step step) async {
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    try {
      final authService = _ref.read(authServiceProvider);
      await authService.updateUserProfile(
        uid: user.uid,
        extraUpdates: {'tutorialPhase1Step': step.firestoreValue},
      );
    } catch (e) {
      debugPrint('TutorialPhase1: failed to persist step: $e');
    }
  }
}

/// チュートリアル Phase1 プロバイダー
final tutorialPhase1Provider =
    StateNotifierProvider<TutorialPhase1Notifier, TutorialPhase1Step>(
      (ref) => TutorialPhase1Notifier(ref),
    );
