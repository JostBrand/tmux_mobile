import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/config/settings_store.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/ui/session_screen.dart';
import 'package:xterm/xterm.dart';

/// Batch A additions: paste, font size buttons, window title.
void main() {
  late StreamController<List<int>> input;
  late ControlModeClient client;
  late List<String> commands;

  Future<void> pumpScreen(
    WidgetTester tester, {
    InMemorySettingsStore? settings,
    List<MethodCall>? clipboardLog,
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
      await input.close();
    });
    if (clipboardLog != null) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          clipboardLog.add(call);
          if (call.method == 'Clipboard.getData') {
            return const {'text': 'pasted-text'};
          }
          return null;
        },
      );
    }
    await tester.pumpWidget(MaterialApp(
      home: SessionScreen(
        client: client,
        settingsStore: settings,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('paste sends the clipboard text to the pane',
      (tester) async {
    final clipboardLog = <MethodCall>[];
    await pumpScreen(tester, clipboardLog: clipboardLog);

    await tester.tap(find.text('Paste'));
    await tester.pump();
    expect(commands, contains("send-keys -t %0 -- 'pasted-text'"));
  });

  testWidgets('font buttons resize the terminal and persist the setting',
      (tester) async {
    final settings = InMemorySettingsStore();
    await pumpScreen(tester, settings: settings);

    await tester.tap(find.byIcon(Icons.text_increase));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(settings.settings.fontSize, 15);
    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.textStyle.fontSize, 15);

    await tester.tap(find.byIcon(Icons.text_decrease));
    await tester.pump();
    expect(settings.settings.fontSize, 14);
  });

  testWidgets('window rename updates the app bar title', (tester) async {
    await pumpScreen(tester);
    input.add(utf8.encode('%window-renamed @0 build-run\n'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('build-run'), findsOneWidget);
  });
}
