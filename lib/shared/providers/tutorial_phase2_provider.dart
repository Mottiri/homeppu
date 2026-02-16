import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import 'auth_provider.dart';

enum TutorialPhase2Step {
  inactive,
  detailIntro,
  commentLongPress,
}

extension TutorialPhase2StepExt on TutorialPhase2Step {
  String get firestoreValue => name;

  static TutorialPhase2Step fromString(String? value) {
    if (value == null) return TutorialPhase2Step.detailIntro;
    return TutorialPhase2Step.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TutorialPhase2Step.detailIntro,
    );
  }
}

class TutorialPhase2Notifier extends StateNotifier<TutorialPhase2Step> {
  TutorialPhase2Notifier(this._ref) : super(TutorialPhase2Step.inactive);

  final Ref _ref;

  void restoreOrStart(UserModel user) {
    if (user.tutorialPhase2Completed) {
      state = TutorialPhase2Step.inactive;
      return;
    }
    if (state != TutorialPhase2Step.inactive) return;
    state = TutorialPhase2StepExt.fromString(user.tutorialPhase2Step);
  }

  Future<void> advance() async {
    final nextIndex = state.index + 1;
    if (nextIndex >= TutorialPhase2Step.values.length) return;
    final next = TutorialPhase2Step.values[nextIndex];
    state = next;
    await _persistStep(next);
  }

  Future<void> markCompleted() async {
    // End tutorial immediately on local state first.
    state = TutorialPhase2Step.inactive;

    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final authService = _ref.read(authServiceProvider);
    try {
      await authService.updateUserProfile(
        uid: user.uid,
        extraUpdates: {
          'tutorialPhase2Completed': true,
          'tutorialPhase2Step': null,
        },
      );
    } catch (e) {
      debugPrint('TutorialPhase2: failed to persist completion: $e');
    }
  }

  Future<void> _persistStep(TutorialPhase2Step step) async {
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    try {
      final authService = _ref.read(authServiceProvider);
      await authService.updateUserProfile(
        uid: user.uid,
        extraUpdates: {'tutorialPhase2Step': step.firestoreValue},
      );
    } catch (e) {
      debugPrint('TutorialPhase2: failed to persist step: $e');
    }
  }
}

final tutorialPhase2Provider =
    StateNotifierProvider<TutorialPhase2Notifier, TutorialPhase2Step>(
  (ref) => TutorialPhase2Notifier(ref),
);
