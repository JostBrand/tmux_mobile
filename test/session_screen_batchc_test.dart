import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/transport/session_factory.dart';
import 'package:tmux_mobile/src/ui/session_screen.dart';

/// Batch C: auto-reconnect + status indicator.
void main() {
  late StreamController<List<int>> input;
  late ControlModeClient client;
  late List<String> commands;

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<OpenSession> Function()? onReconnect,
  }) async {
    input = StreamController<List<int>>.broadcast();
    commands = <String>[];
    input.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(commands.add);
    client = ControlModeClient(input: input.stream, output: input.sink);
    addTearDown(() async {
      client.dispose();
      // Double-close of a broadcast controller with an active transform
      // subscription never completes - guard it.
      if (!input.isClosed) {
        await input.close();
      }
    });
    await tester.pumpWidget(MaterialApp(
      home: SessionScreen(client: client, onReconnect: onReconnect),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Color dotColor(WidgetTester tester) {
    final container = tester.widget<Container>(
        find.byKey(const Key('connection-status-dot')));
    return (container.decoration! as BoxDecoration).color!;
  }

  testWidgets('connection loss triggers reconnect and swaps the client',
      (tester) async {
    final input2 = StreamController<List<int>>.broadcast();
    final commands2 = <String>[];
    input2.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(commands2.add);
    final client2 = ControlModeClient(input: input2.stream, output: input2.sink);
    var reconnects = 0;
    addTearDown(() async {
      client2.dispose();
      if (!input2.isClosed) {
        await input2.close();
      }
    });

    await pumpScreen(tester, onReconnect: () async {
      reconnects++;
      return OpenSession(client: client2, close: () async {});
    });

    expect(dotColor(tester), Colors.greenAccent);

    // Kill the connection: the input stream ends. (Do NOT await close()
    // in the fake-async body - the completion microtask needs a pump.)
    unawaited(input.close());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(reconnects, 1);
    expect(dotColor(tester), Colors.greenAccent);

    // Input now flows through the NEW client.
    await tester.tap(find.text('Escape'));
    await tester.pump();
    expect(commands2, contains("send-keys -t %0 -- 'Escape'"));
    expect(commands, isNot(contains("send-keys -t %0 -- 'Escape'")));
  });

  testWidgets('reconnect failure ends in the failed state with retry',
      (tester) async {
    var attempts = 0;
    await pumpScreen(tester, onReconnect: () async {
      attempts++;
      throw StateError('down');
    });

    unawaited(input.close());
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
    await tester.pump();

    expect(attempts, 5);
    expect(dotColor(tester), isNot(Colors.greenAccent));
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('no reconnect callback: connection loss is ignored',
      (tester) async {
    await pumpScreen(tester);
    unawaited(input.close());
    await tester.pump();
    expect(dotColor(tester), Colors.greenAccent);
  });
}
