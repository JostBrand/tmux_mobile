import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/ui/session_screen.dart';
import 'package:xterm/xterm.dart';

/// Mouse-wheel forwarding for TUI apps (opencode etc.).
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

  Future<void> scrollPane(WidgetTester tester, double dy) async {
    final center = tester.getCenter(find.byType(TerminalView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  testWidgets('scroll forwards mouse events only when the pane enables them',
      (tester) async {
    await pumpScreen(tester);

    // Without mouse reporting: scroll is NOT forwarded.
    await scrollPane(tester, -100);
    expect(commands.where((c) => c.contains('-M')).toList(), isEmpty);

    // The pane (an SGR-mouse TUI like opencode) enables mouse reporting.
    input.add(utf8.encode('%output %0 \x1b[?1006h\n'));
    await tester.pump();
    await tester.pump();

    await scrollPane(tester, -100);
    await scrollPane(tester, 120);
    await tester.pump(const Duration(milliseconds: 50));

    final mouseCommands =
        commands.where((c) => c.startsWith('send-keys -t %0 -M ')).toList();
    expect(mouseCommands, isNotEmpty);
    // Wheel-up SGR id 68, wheel-down 69 (64+4 / 64+5 in xterm's encoding).
    expect(mouseCommands.first, contains('68'));
  });

  testWidgets('scroll events are not sent as keyboard text', (tester) async {
    await pumpScreen(tester);
    input.add(utf8.encode('%output %0 \x1b[?1006h\n'));
    await tester.pump();
    await scrollPane(tester, -100);
    await tester.pump(const Duration(milliseconds: 50));

    // No plain send-keys text from the scroll gesture.
    expect(
      commands.where((c) => c.startsWith('send-keys -t %0 -- ')).toList(),
      isEmpty,
    );
  });
}
