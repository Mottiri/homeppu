import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Non-subscriber one-time circle browse session (client runtime only).
/// Server-side one-time eligibility is judged by callable.
final circleTrialSessionProvider = StateProvider<bool>((ref) => false);
