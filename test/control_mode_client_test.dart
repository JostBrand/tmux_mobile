import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';

/// Unit tests for the control-mode line parsing: feed raw protocol bytes
/// into the client and assert the typed events + command output capture.
void main() {
  late StreamController<List<int>> input;
  late ControlModeClient client;

  setUp(() {
    input = StreamController<List<int>>();
    // The client writes commands back into the same controller: lines
    // without a % prefix are ignored by the parser, so the loop is safe.
    client = ControlModeClient(input: input.stream, output: input.sink);
  });

  tearDown(() async {
    client.dispose();
    await input.close();
  });

  void feed(List<String> lines) {
    input.add(utf8.encode('${lines.join('\n')}\n'));
  }

  test('dispatches notifications and pane output', () async {
    final panes = <PaneOutput>[];
    final sessions = <String>[];
    client.paneOutput.listen(panes.add);
    client.sessionChanged.listen(sessions.add);

    feed([
      '%session-changed %2 spike',
      '%output %0 hello world',
      '%window-add @1',
    ]);

    await Future<void>.delayed(Duration.zero);
    expect(sessions, ['spike']);
    expect(panes.single.paneId, '%0');
    expect(panes.single.line, 'hello world');
  });

  test('captures command output between %begin and %end', () async {
    final future = client.runCommand('display-message -p hello');
    // Emulate what tmux does: %begin, raw output lines, %end.
    feed(['%begin 1710000000 1', 'hello', '%end 1710000000 1']);
    expect(await future, 'hello');
  });

  test('command output is matched to commands in order', () async {
    final first = client.runCommand('display-message -p one');
    final second = client.runCommand('display-message -p two');
    feed(['%begin 1 1', 'one', '%end 1 1']);
    feed(['%begin 1 1', 'two', '%end 1 1']);
    expect(await first, 'one');
    expect(await second, 'two');
  });

  test('auto-subscribes on session-changed', () async {
    feed(['%session-changed %2 spike']);
    await Future<void>.delayed(Duration.zero);
    expect(client.currentSession, 'spike');
  });
}
