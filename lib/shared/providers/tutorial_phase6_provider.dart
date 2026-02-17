import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import 'auth_provider.dart';

enum TutorialPhase6Step {
  inactive,
  profileOverview,
  virtueGuide,
  favoritesGuide,
}

extension TutorialPhase6StepExt on TutorialPhase6Step {
  String get firestoreValue => name;

  static TutorialPhase6Step fromString(String? value) {
    if (value == null) return TutorialPhase6Step.profileOverview;
    return TutorialPhase6Step.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TutorialPhase6Step.profileOverview,
    );
  }
}

class TutorialPhase6Notifier extends StateNotifier<TutorialPhase6Step> {
  TutorialPhase6Notifier(this._ref) : super(TutorialPhase6Step.inactive);

  final Ref _ref;

  void restoreOrStart(UserModel user) {
    if (user.tutorialPhase6Completed) {
      state = TutorialPhase6Step.inactive;
      return;
    }
    if (state != TutorialPhase6Step.inactive) return;
    state = TutorialPhase6StepExt.fromString(user.tutorialPhase6Step);
  }

  Future<void> advance() async {
    final nextIndex = state.index + 1;
    if (nextIndex >= TutorialPhase6Step.values.length) return;
    final next = TutorialPhase6Step.values[nextIndex];
    state = next;
    await _persistStep(next);
  }

  Future<void> markCompleted() async {
    state = TutorialPhase6Step.inactive;
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final authService = _ref.read(authServiceProvider);
    try {
      await authService.updateUserProfile(
        uid: user.uid,
        extraUpdates: {
          'tutorialPhase6Completed': true,
          'tutorialPhase6Step': null,
        },
      );
    } catch (e) {
      debugPrint('TutorialPhase6: failed to persist completion: $e');
    }
  }

  Future<void> _persistStep(TutorialPhase6Step step) async {
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    try {
      final authService = _ref.read(authServiceProvider);
      await authService.updateUserProfile(
        uid: user.uid,
        extraUpdates: {'tutorialPhase6Step': step.firestoreValue},
      );
    } catch (e) {
      debugPrint('TutorialPhase6: failed to persist step: $e');
    }
  }
}

final tutorialPhase6Provider =
    StateNotifierProvider<TutorialPhase6Notifier, TutorialPhase6Step>(
  (ref) => TutorialPhase6Notifier(ref),
);

