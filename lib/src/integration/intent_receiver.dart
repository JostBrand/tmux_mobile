import 'dart:async';

import 'package:flutter/services.dart';

/// Receives text from other apps (PROCESS_TEXT / ACTION_SEND) via the
/// tmux_mobile/intents channel. Emits on [texts].
class IntentReceiver {
  static const _channel = MethodChannel('tmux_mobile/intents');
  static final _texts = StreamController<String>.broadcast();

  static Stream<String> get texts => _texts.stream;

  static bool _initialized = false;

  static void initialize() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onText') {
        final text = call.arguments as String? ?? '';
        if (text.trim().isNotEmpty) {
          _texts.add(text);
        }
      } else if (call.method == 'drainPendingTexts') {
        // The native side delivers pending texts via onText after the
        // engine is ready; nothing to do here.
      }
    });
  }

  /// Fetches texts that arrived before the engine was up.
  static Future<List<String>> drainPending() async {
    final texts = await _channel.invokeListMethod<String>('drainPendingTexts');
    return texts ?? const [];
  }
}

/// Queues text from other apps while no session is connected.
class PendingTextQueue {
  final List<String> _items = [];

  int get length => _items.length;
  List<String> get items => List.unmodifiable(_items);

  void add(String text) {
    final trimmed = text.trim();
    if (trimmed.isNotEmpty) {
      _items.add(trimmed);
    }
  }

  String? takeNext() => _items.isEmpty ? null : _items.removeAt(0);

  void clear() => _items.clear();
}

/// Shares text OUT to other apps via the native share sheet.
class ShareOut {
  static const _channel = MethodChannel('tmux_mobile/share');

  static Future<void> shareText(String text) async {
    if (text.trim().isEmpty) {
      return;
    }
    await _channel.invokeMethod('shareText', text);
  }
}
