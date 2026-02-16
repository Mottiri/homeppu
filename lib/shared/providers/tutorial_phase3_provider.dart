import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import 'auth_provider.dart';

enum TutorialPhase3Step {
  inactive,
  overview,
  longPressSheet,
  catalog,
  collection,
  undo,
}

extension TutorialPhase3StepExt on TutorialPhase3Step {
  String get firestoreValue => name;

  static TutorialPhase3Step fromString(String? value) {
    if (value == null) return TutorialPhase3Step.overview;
    return TutorialPhase3Step.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TutorialPhase3Step.overview,
    );
  }
}

class TutorialPhase3Notifier extends StateNotifier<TutorialPhase3Step> {
  TutorialPhase3Notifier(this._ref) : super(TutorialPhase3Step.inactive);

  final Ref _ref;

  void restoreOrStart(UserModel user) {
    if (user.tutorialPhase3Completed) {
      state = TutorialPhase3Step.inactive;
      return;
    }
    if (state != TutorialPhase3Step.inactive) return;
    state = TutorialPhase3StepExt.fromString(user.tutorialPhase3Step);
  }

  Future<void> advance() async {
    final nextIndex = state.index + 1;
    if (nextIndex >= TutorialPhase3Step.values.length) return;
    final next = TutorialPhase3Step.values[nextIndex];
    state = next;
    await _persistStep(next);
  }

  Future<void> markCompleted() async {
    // End tutorial immediately in local state.
    state = TutorialPhase3Step.inactive;

    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final authService = _ref.read(authServiceProvider);
    try {
      await authService.updateUserProfile(
        uid: user.uid,
        extraUpdates: {
          'tutorialPhase3Completed': true,
          'tutorialPhase3Step': null,
        },
      );
    } catch (e) {
      debugPrint('TutorialPhase3: failed to persist completion: $e');
    }
  }

  Future<void> _persistStep(TutorialPhase3Step step) async {
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    try {
      final authService = _ref.read(authServiceProvider);
      await authService.updateUserProfile(
        uid: user.uid,
        extraUpdates: {'tutorialPhase3Step': step.firestoreValue},
      );
    } catch (e) {
      debugPrint('TutorialPhase3: failed to persist step: $e');
    }
  }
}

final tutorialPhase3Provider =
    StateNotifierProvider<TutorialPhase3Notifier, TutorialPhase3Step>(
  (ref) => TutorialPhase3Notifier(ref),
);

