import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/ui/session_screen.dart';

/// Widget tests for the session screen with a loopback fake client.
///
/// NOTE: the StreamController and client are created INSIDE the test body
/// (not in setUp) - setUp runs in the real zone while the testWidgets body
/// runs under FakeAsync, and events delivered through cross-zone
/// microtasks never get flushed by tester.pump().
void main() {
  late StreamController<List<int>> input;
  late ControlModeClient client;
  late List<String> commands;

  Future<void> pumpScreen(WidgetTester tester) async {
    input = StreamController<List<int>>.broadcast();
    commands = <String>[];
    input.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(commands.add);
    client = ControlModeClient(input: input.stream, output: input.sink);
    addTearDown(() async {
      client.dispose();
      await input.close();
    });
    await tester
        .pumpWidget(MaterialApp(home: SessionScreen(client: client)));
    await tester.pump();
    // Let the resize debounce of the pane feeder settle.
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('swipe left selects the next known pane', (tester) async {
    await pumpScreen(tester);
    // A second pane becomes known once it emits output.
    input.add(utf8.encode('%output %1 echo-from-pane-one\n'));
    await tester.pump();

    await tester.fling(
        find.byKey(const Key('pane-swipe-area')), const Offset(-250, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(commands, contains('select-pane -t %1'));
  });

  testWidgets('keybar sends keys to the currently displayed pane',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Escape'));
    await tester.pump();
    expect(commands, contains("send-keys -t %0 -- 'Escape'"));

    input.add(utf8.encode('%output %1 echo\n'));
    await tester.pump();
    await tester.fling(
        find.byKey(const Key('pane-swipe-area')), const Offset(-250, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Tab'));
    await tester.pump();
    expect(commands, contains("send-keys -t %1 -- 'Tab'"));
  });

  testWidgets('history button fetches scrollback for the current pane',
      (tester) async {
    await pumpScreen(tester);

    // Drain all commands pending from setup (pane seed + resize refreshes)
    // so the sheet's fetch is the only pending command afterwards.
    final pending = commands
        .where((c) =>
            c.startsWith('capture-pane') || c.startsWith('refresh-client'))
        .length;
    for (var i = 0; i < pending; i++) {
      input.add(utf8.encode('%begin 1 1\nfiller\n%end 1 1\n'));
    }
    await tester.pump();

    await tester.tap(find.byIcon(Icons.manage_search));
    await tester.pump();
    await tester.pump();

    input.add(
        utf8.encode('%begin 1 1\nold-line-1\nold-line-2\n%end 1 1\n'));
    await tester.pumpAndSettle();

    expect(find.text('History - %0'), findsOneWidget);
    expect(find.text('old-line-2'), findsOneWidget);
    expect(commands, contains('capture-pane -p -e -t %0 -S -200'));
  });

  testWidgets('renders a terminal and the keybar', (tester) async {
    await pumpScreen(tester);
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(find.text('Escape'), findsOneWidget);
    expect(find.text('Enter'), findsOneWidget);
  });
}
