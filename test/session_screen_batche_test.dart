import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/notifications/activity_notifier.dart';
import 'package:tmux_mobile/src/ui/session_screen.dart';

/// Batch E: hidden-pane activity notifications.
void main() {
  late StreamController<List<int>> input;
  late ControlModeClient client;
  late FakeActivityNotifier notifier;
  var now = DateTime(2026, 1, 1, 12, 0, 0);

  Future<void> pumpScreen(WidgetTester tester) async {
    input = StreamController<List<int>>.broadcast();
    client = ControlModeClient(input: input.stream, output: input.sink);
    notifier = FakeActivityNotifier();
    addTearDown(() async {
      client.dispose();
      if (!input.isClosed) {
        await input.close();
      }
    });
    await tester.pumpWidget(MaterialApp(
      home: SessionScreen(
        client: client,
        title: 'homelab · dev',
        activityNotifier: notifier,
        activityMonitor: ActivityMonitor(now: () => now),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('hidden pane output after a silent period notifies',
      (tester) async {
    await pumpScreen(tester);

    // Pane %1 becomes known and produces its first output (no notify).
    input.add(utf8.encode('%output %1 first\n'));
    await tester.pump();
    expect(notifier.notifications, isEmpty);

    // After >30s of silence a new output triggers the notification.
    now = now.add(const Duration(seconds: 31));
    input.add(utf8.encode('%output %1 second\n'));
    await tester.pump();
    expect(notifier.notifications, hasLength(1));
    expect(notifier.notifications.single.$1, 'homelab · dev');
    expect(notifier.notifications.single.$2, contains('%1'));
  });

  testWidgets('visible pane output never notifies', (tester) async {
    await pumpScreen(tester);
    input.add(utf8.encode('%output %0 visible\n'));
    await tester.pump();
    now = now.add(const Duration(seconds: 60));
    input.add(utf8.encode('%output %0 again\n'));
    await tester.pump();
    expect(notifier.notifications, isEmpty);
  });
}
