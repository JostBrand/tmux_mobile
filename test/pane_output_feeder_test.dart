import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/render/pane_output_feeder.dart';
import 'package:xterm/xterm.dart';

void main() {
  late StreamController<List<int>> input;
  late ControlModeClient client;
  late List<String> commands;
  late Terminal terminal;
  late PaneOutputFeeder feeder;

  setUp(() {
    input = StreamController<List<int>>.broadcast();
    commands = <String>[];
    input.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(commands.add);
    client = ControlModeClient(input: input.stream, output: input.sink);
    terminal = Terminal(maxLines: 1000);
    feeder = PaneOutputFeeder(
        client: client, paneId: '%0', terminal: terminal);
  });

  tearDown(() async {
    feeder.dispose();
    client.dispose();
    await input.close();
  });

  test('feeds %output lines of the pane into the terminal', () async {
    input.add(utf8.encode('%output %0 hello-pane\n%output %1 other-pane\n'));
    await Future<void>.delayed(Duration.zero);
    expect(terminal.buffer.getText(), contains('hello-pane'));
    expect(terminal.buffer.getText(), isNot(contains('other-pane')));
  });

  test('interprets escape sequences (colors/cursor) via the xterm parser',
      () async {
    input.add(utf8.encode(
        '%output %0 \x1b[0m\x1b[7mreverse\x1b[0m plain\n'));
    await Future<void>.delayed(Duration.zero);
    expect(terminal.buffer.getText(), contains('reverse'));
    expect(terminal.buffer.getText(), contains('plain'));
  });

  test('seeds the screen from capture-pane on attach', () async {
    feeder.seedScreen();
    await Future<void>.delayed(Duration.zero);
    expect(commands, contains('capture-pane -p -e -t %0'));
  });
}
