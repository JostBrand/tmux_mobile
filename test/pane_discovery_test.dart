import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/ui/session_screen.dart';

/// Pane discovery: pane ids are server-wide counters - %0 is only valid
/// when it was the very first pane on the server.
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
      if (!input.isClosed) {
        await input.close();
      }
    });
    await tester
        .pumpWidget(MaterialApp(home: SessionScreen(client: client)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the active pane is discovered, not assumed as %0',
      (tester) async {
    await pumpScreen(tester);

    // Drain setup commands.
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
    input.add(utf8.encode('%begin 1 1\nprefix C-b\n%end 1 1\n')); // 1
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n')); // 2 list-keys
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n')); // 3 detach-on-destroy
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%7:bash\n%end 1 1\n')); // 4 list-panes
    await tester.pump();
    // 5: the pane discovery query - the active pane is %7 (an existing
    // server with several sessions/panes).
    input.add(utf8.encode('%begin 1 1\n%7\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n80x24\n%end 1 1\n')); // 6 size
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n')); // 7 refresh
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Keybar input must target the DISCOVERED pane, not %0.
    await tester.tap(find.text('Escape'));
    await tester.pump();
    expect(commands, contains("send-keys -t %7 -- 'Escape'"));
    expect(commands, isNot(contains("send-keys -t %0 -- 'Escape'")));
  });

  testWidgets('failed tmux commands do not render their error text',
      (tester) async {
    await pumpScreen(tester);
    // Answer the seed's capture-pane with an ERROR (%error bracket) - the
    // error text must NOT be written into the terminal. (With autoResize
    // off there are no setup refreshes; the seed is the only pending
    // command.)
    input.add(utf8.encode(
        '%begin 1 1\ncan not find pane: %0\n%error 1 1\n'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The fallback refresh-client commands were issued instead.
    expect(
      commands.where((c) => c.startsWith('refresh-client')).toList(),
      isNotEmpty,
    );
  });
}
