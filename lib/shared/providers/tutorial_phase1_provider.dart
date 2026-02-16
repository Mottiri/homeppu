import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import 'auth_provider.dart';

// QA/debug flag. Keep false in normal builds.
const bool kForcePhase1TutorialForDebug = false;

/// Tutorial phase 1 steps.
enum TutorialPhase1Step {
  inactive,
  homeWelcome,
  profileSettings,
  settingsScroll,
  explainAI,
  explainMix,
  explainHuman,
  finished,
  homeOverview,
  homeLongPress,
}

extension TutorialPhase1StepExt on TutorialPhase1Step {
  String get firestoreValue => name;

  static TutorialPhase1Step fromString(String? value) {
    if (value == null) return TutorialPhase1Step.homeWelcome;
    return TutorialPhase1Step.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TutorialPhase1Step.homeWelcome,
    );
  }
}

class TutorialPhase1Notifier extends StateNotifier<TutorialPhase1Step> {
  TutorialPhase1Notifier(this._ref) : super(TutorialPhase1Step.inactive);

  final Ref _ref;

  void restoreOrStart(UserModel user) {
    if (user.tutorialPhase1Completed && !kForcePhase1TutorialForDebug) {
      state = TutorialPhase1Step.inactive;
      return;
    }
    if (state != TutorialPhase1Step.inactive) return;

    state = TutorialPhase1StepExt.fromString(user.tutorialPhase1Step);
  }

  bool get isActive => state != TutorialPhase1Step.inactive;

  Future<void> advance() async {
    final nextIndex = state.index + 1;
    if (nextIndex >= TutorialPhase1Step.values.length) return;

    final next = TutorialPhase1Step.values[nextIndex];
    state = next;
    await _persistStep(next);
  }

  void jumpTo(TutorialPhase1Step step) {
    state = step;
  }

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

  Future<void> markCompleted() async {
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    final authService = _ref.read(authServiceProvider);
    await authService.updateUserProfile(
      uid: user.uid,
      extraUpdates: {
        'tutorialPhase1Completed': true,
        'tutorialPhase1Step': null,
      },
    );
    state = TutorialPhase1Step.inactive;
  }

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

final tutorialPhase1Provider =
    StateNotifierProvider<TutorialPhase1Notifier, TutorialPhase1Step>(
  (ref) => TutorialPhase1Notifier(ref),
);
