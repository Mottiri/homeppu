import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import 'auth_provider.dart';

enum TutorialPhase4Step {
  inactive,
  postButtonGuide,
  moderationDelayGuide,
  aiMisjudgeGuide,
}

extension TutorialPhase4StepExt on TutorialPhase4Step {
  String get firestoreValue => name;

  static TutorialPhase4Step fromString(String? value) {
    if (value == null) return TutorialPhase4Step.postButtonGuide;
    return TutorialPhase4Step.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TutorialPhase4Step.postButtonGuide,
    );
  }
}

class TutorialPhase4Notifier extends StateNotifier<TutorialPhase4Step> {
  TutorialPhase4Notifier(this._ref) : super(TutorialPhase4Step.inactive);

  final Ref _ref;

  void restoreOrStart(UserModel user) {
    if (user.tutorialPhase4Completed) {
      state = TutorialPhase4Step.inactive;
      return;
    }
    if (state != TutorialPhase4Step.inactive) return;
    state = TutorialPhase4StepExt.fromString(user.tutorialPhase4Step);
  }

  Future<void> advance() async {
    final nextIndex = state.index + 1;
    if (nextIndex >= TutorialPhase4Step.values.length) return;
    final next = TutorialPhase4Step.values[nextIndex];
    state = next;
    await _persistStep(next);
  }

  Future<void> markCompleted() async {
    state = TutorialPhase4Step.inactive;

    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final authService = _ref.read(authServiceProvider);
    try {
      await authService.updateUserProfile(
        uid: user.uid,
        extraUpdates: {
          'tutorialPhase4Completed': true,
          'tutorialPhase4Step': null,
        },
      );
    } catch (e) {
      debugPrint('TutorialPhase4: failed to persist completion: $e');
    }
  }

  Future<void> _persistStep(TutorialPhase4Step step) async {
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    try {
      final authService = _ref.read(authServiceProvider);
      await authService.updateUserProfile(
        uid: user.uid,
        extraUpdates: {'tutorialPhase4Step': step.firestoreValue},
      );
    } catch (e) {
      debugPrint('TutorialPhase4: failed to persist step: $e');
    }
  }
}

final tutorialPhase4Provider =
    StateNotifierProvider<TutorialPhase4Notifier, TutorialPhase4Step>(
  (ref) => TutorialPhase4Notifier(ref),
);
