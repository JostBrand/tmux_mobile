import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/ui/session_screen.dart';

/// Batch D: copy-mode selection -> clipboard.
void main() {
  late StreamController<List<int>> input;
  late ControlModeClient client;
  late List<String> commands;
  final clipboard = <MethodCall>[];

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
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        clipboard.add(call);
        return null;
      },
    );
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
    input.add(utf8.encode('%begin 1 1\n80x24\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n'));
    await tester.pump();
    // 6th introspection command: list-panes (nested-tmux detection).
    input.add(utf8.encode('%begin 1 1\n%0:bash\n%end 1 1\n'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'C-b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Drain commands from the size adoption.
    final adoption = commands
        .where((c) =>
            c.startsWith('capture-pane') || c.startsWith('refresh-client'))
        .length;
    for (var i = 0; i < adoption; i++) {
      input.add(utf8.encode('%begin 1 1\nfiller\n%end 1 1\n'));
    }
    await tester.pump();
  }

  testWidgets('copy selection cancels copy mode and pulls the buffer',
      (tester) async {
    await openModMode(tester);

    // Scroll the sheet list so the 'Copy selection' entry is visible.
    await tester.drag(find.byType(ListView).last, const Offset(0, -150));
    await tester.pump();
    await tester.tap(find.text('Copy selection'));
    await tester.pump();

    expect(commands,
        contains('send-keys -t %0 -X copy-selection-and-cancel'));
    expect(commands, contains('show-buffer'));

    // Two commands are pending: the copy-selection send-keys (answers
    // empty) and show-buffer (answers with the selection text).
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\nselected-text\n%end 1 1\n'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final setData = clipboard
        .where((call) => call.method == 'Clipboard.setData')
        .toList();
    expect(setData, isNotEmpty);
    expect(
      (setData.last.arguments as Map)['text'],
      contains('selected-text'),
    );
  });
}
