import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import 'auth_provider.dart';

enum TutorialPhase5Step {
  inactive,
  circleOverview,
  circleFabGuide,
}

extension TutorialPhase5StepExt on TutorialPhase5Step {
  String get firestoreValue => name;

  static TutorialPhase5Step fromString(String? value) {
    if (value == null) return TutorialPhase5Step.circleOverview;
    return TutorialPhase5Step.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TutorialPhase5Step.circleOverview,
    );
  }
}

class TutorialPhase5Notifier extends StateNotifier<TutorialPhase5Step> {
  TutorialPhase5Notifier(this._ref) : super(TutorialPhase5Step.inactive);

  final Ref _ref;

  void restoreOrStart(UserModel user) {
    if (user.tutorialPhase5Completed) {
      state = TutorialPhase5Step.inactive;
      return;
    }
    if (state != TutorialPhase5Step.inactive) return;
    state = TutorialPhase5StepExt.fromString(user.tutorialPhase5Step);
  }

  Future<void> advance() async {
    final nextIndex = state.index + 1;
    if (nextIndex >= TutorialPhase5Step.values.length) return;
    final next = TutorialPhase5Step.values[nextIndex];
    state = next;
    await _persistStep(next);
  }

  Future<void> markCompleted() async {
    state = TutorialPhase5Step.inactive;
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final authService = _ref.read(authServiceProvider);
    try {
      await authService.updateUserProfile(
        uid: user.uid,
        extraUpdates: {
          'tutorialPhase5Completed': true,
          'tutorialPhase5Step': null,
        },
      );
    } catch (e) {
      debugPrint('TutorialPhase5: failed to persist completion: $e');
    }
  }

  Future<void> _persistStep(TutorialPhase5Step step) async {
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    try {
      final authService = _ref.read(authServiceProvider);
      await authService.updateUserProfile(
        uid: user.uid,
        extraUpdates: {'tutorialPhase5Step': step.firestoreValue},
      );
    } catch (e) {
      debugPrint('TutorialPhase5: failed to persist step: $e');
    }
  }
}

final tutorialPhase5Provider =
    StateNotifierProvider<TutorialPhase5Notifier, TutorialPhase5Step>(
  (ref) => TutorialPhase5Notifier(ref),
);

