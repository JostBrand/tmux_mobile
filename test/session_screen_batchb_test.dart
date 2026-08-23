import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/ui/session_screen.dart';

/// Batch B: window picker, pane picker, copy-mode entry.
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
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> openModMode(WidgetTester tester) async {
    await pumpScreen(tester);
    final pending = commands
        .where((c) =>
            c.startsWith('capture-pane') || c.startsWith('refresh-client'))
        .length;
    for (var i = 0; i < pending; i++) {
      input.add(utf8.encode('%begin 1 1\nfiller\n%end 1 1\n'));
    }
    await tester.pump();
    input.add(utf8.encode('%session-changed \$1 spike\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\nprefix C-b\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode(
        '%begin 1 1\nbind-key -T prefix c new-window\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%0:bash\n%end 1 1\n')); // 4 list-panes
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%0\n%end 1 1\n')); // 5 pane_id
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n80x24\n%end 1 1\n')); // 6 size
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n')); // 7 refresh
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'C-b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Drain commands triggered by the size adoption (terminal resize ->
    // refresh-client).
    final adoption = commands
        .where((c) =>
            c.startsWith('capture-pane') || c.startsWith('refresh-client'))
        .length;
    for (var i = 0; i < adoption; i++) {
      input.add(utf8.encode('%begin 1 1\nfiller\n%end 1 1\n'));
    }
    await tester.pump();
  }

  testWidgets('window picker lists windows and selects one',
      (tester) async {
    await openModMode(tester);

    await tester.tap(find.text('Windows…'));
    await tester.pump();
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n0:bash\n1:build\n%end 1 1\n'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('build'), findsOneWidget);
    await tester.tap(find.text('build'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(commands, contains('select-window -t @1'));
  });

  testWidgets('pane picker lists panes and switches the displayed pane',
      (tester) async {
    await openModMode(tester);

    await tester.tap(find.text('Panes…'));
    await tester.pump();
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%0:bash\n%1:htop\n%end 1 1\n'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('htop'), findsOneWidget);
    await tester.tap(find.text('htop'));
    await tester.pumpAndSettle();
    expect(commands, contains('select-pane -t %1'));

    // Subsequent input goes to the newly selected pane (wait for the
    // closing animations of picker + prefix sheet first).
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Escape'));
    await tester.pump();
    expect(commands, contains("send-keys -t %1 -- 'Escape'"));
  });

  testWidgets('copy mode entry runs the copy-mode command', (tester) async {
    await openModMode(tester);
    await tester.tap(find.text('Copy mode'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(commands, contains('copy-mode'));
  });
}
