import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/ui/keybar.dart';
import 'package:tmux_mobile/src/ui/session_screen.dart';

/// Nested tmux: inner-prefix key + detection badge.
void main() {
  testWidgets('keybar inner prefix key triggers its callback',
      (tester) async {
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Keybar(
          onKey: (_) {},
          innerPrefixKey: 'C-b',
          onInnerPrefix: () => pressed++,
        ),
      ),
    ));
    await tester.tap(find.text('C-b'));
    expect(pressed, 1);
  });

  testWidgets('nested tmux is detected and the badge sends the inner prefix',
      (tester) async {
    final input = StreamController<List<int>>.broadcast();
    final commands = <String>[];
    input.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(commands.add);
    final client = ControlModeClient(input: input.stream, output: input.sink);
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

    // Drain setup commands, then answer the introspection incl. the
    // list-panes query reporting a tmux pane (nested session).
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
    // Command order in _introspectServer: prefix, list-keys,
    // detach-on-destroy, list-panes, display-message, refresh-client.
    input.add(utf8.encode('%begin 1 1\n%0:tmux\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n80x24\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The badge appears for the tmux pane.
    expect(find.byKey(const Key('nested-tmux-badge')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nested-tmux-badge')));
    await tester.pump();
    expect(commands, contains('send-keys -t %0 C-b'));
  });

  testWidgets('no badge for a plain shell pane', (tester) async {
    final input = StreamController<List<int>>.broadcast();
    final client = ControlModeClient(input: input.stream, output: input.sink);
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

    input.add(utf8.encode('%session-changed \$1 spike\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\nprefix C-b\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%0:bash\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n80x24\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('nested-tmux-badge')), findsNothing);
  });
}
