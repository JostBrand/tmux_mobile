import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tmux_mobile/src/integration/intent_receiver.dart';

/// A live session that can receive text from other apps.
class LiveSessionHandle {
  const LiveSessionHandle({
    required this.profileName,
    required this.sendText,
  });

  final String profileName;

  /// Sends raw text into the active pane (translateKeyboardInput handles
  /// Enter/Backspace mapping).
  final void Function(String text) sendText;
}

/// Tracks the currently open session + queues incoming text from other
/// apps. SessionScreen registers itself; incoming texts are sent through
/// the session, otherwise queued for the next connect.
class SessionRegistry {
  LiveSessionHandle? _session;
  final PendingTextQueue queue = PendingTextQueue();

  final ValueNotifier<int> _version = ValueNotifier<int>(0);

  /// Bumps whenever the session or the queue changes (UI rebuilds).
  ValueListenable<int> get version => _version;

  /// Deferred: registration happens during widget builds (initState) and
  /// notifying listeners synchronously would call setState mid-build.
  void _bump() {
    scheduleMicrotask(() => _version.value++);
  }

  LiveSessionHandle? get session => _session;
  bool get hasSession => _session != null;

  void register(LiveSessionHandle handle) {
    _session = handle;
    _bump();
  }

  void unregister(LiveSessionHandle handle) {
    if (_session == handle) {
      _session = null;
      _bump();
    }
  }

  /// Routes text from another app: to the live session or the queue.
  /// Returns false when it landed in the queue (no session open).
  bool deliverText(String text) {
    final session = _session;
    if (session != null) {
      session.sendText(text);
      return true;
    }
    queue.add(text);
    _bump();
    return false;
  }
}
