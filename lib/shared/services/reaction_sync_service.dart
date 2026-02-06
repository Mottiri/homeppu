import 'dart:collection';

import 'package:flutter/foundation.dart';

class _ReactionQueue {
  final Queue<Future<void> Function()> _queue = Queue();
  bool _isProcessing = false;
  bool _disposed = false;

  void enqueue(Future<void> Function() task) {
    if (_disposed) return;
    _queue.add(task);
    _processNext();
  }

  Future<void> _processNext() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;
    while (_queue.isNotEmpty && !_disposed) {
      final task = _queue.removeFirst();
      try {
        await task();
      } catch (e) {
        debugPrint('ReactionQueue task failed: $e');
      }
    }
    _isProcessing = false;
  }

  void dispose() {
    _disposed = true;
    _queue.clear();
  }
}

class ReactionSyncService {
  static final Map<String, _ReactionQueue> _queues = {};
  static final Map<String, Map<String, int>> _pendingByUser = {};

  static String _userKey(String? userId) {
    if (userId == null || userId.isEmpty) {
      return 'anonymous';
    }
    return userId;
  }

  static void enqueue(String? userId, Future<void> Function() task) {
    final key = _userKey(userId);
    final queue = _queues.putIfAbsent(key, () => _ReactionQueue());
    queue.enqueue(task);
  }

  static void incrementPending(String reactionType, {String? userId}) {
    final key = _userKey(userId);
    final pending = _pendingByUser.putIfAbsent(key, () => {});
    pending[reactionType] = (pending[reactionType] ?? 0) + 1;
  }

  static void decrementPending(String reactionType, {String? userId}) {
    final key = _userKey(userId);
    final pending = _pendingByUser[key];
    if (pending == null) return;
    final current = pending[reactionType] ?? 0;
    if (current <= 1) {
      pending.remove(reactionType);
    } else {
      pending[reactionType] = current - 1;
    }
    if (pending.isEmpty) {
      _pendingByUser.remove(key);
    }
  }

  static int getPending(String reactionType, {String? userId}) {
    final key = _userKey(userId);
    final pending = _pendingByUser[key];
    if (pending == null) return 0;
    return pending[reactionType] ?? 0;
  }

  static void clearForUser(String? userId) {
    final key = _userKey(userId);
    _pendingByUser.remove(key);
    final queue = _queues.remove(key);
    queue?.dispose();
  }
}
