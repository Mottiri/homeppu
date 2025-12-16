import 'package:flutter_riverpod/flutter_riverpod.dart';

/// タスク画面で現在選択されている日付を管理するプロバイダー
final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());
