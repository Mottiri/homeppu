import 'package:flutter_riverpod/flutter_riverpod.dart';

/// MainShellのボトムナビを一時的に非表示にするための共有状態
final mainShellBottomNavHiddenProvider = StateProvider<bool>((ref) => false);

