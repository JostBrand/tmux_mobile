import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';

/// Integration test against a REAL local tmux server: spawns a fresh tmux
/// on a private socket, attaches a control-mode client and drives it.
///
/// This is the core risk of the whole app - if this test passes, the CC
/// protocol plumbing works. Run: flutter test test/control_mode_integration_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String socket;
  late Process ccProcess;
  late ControlModeClient client;

  Future<T> waitFor<T>(Stream<T> stream, bool Function(T) predicate,
      {Duration timeout = const Duration(seconds: 10)}) async {
    final sub = stream.listen(null);
    final completer = Completer<T>();
    sub.onData((T value) {
      if (predicate(value) && !completer.isCompleted) {
        completer.complete(value);
      }
    });
    return completer.future.timeout(timeout, onTimeout: () async {
      await sub.cancel();
      throw TimeoutException('condition not met on $stream');
    }).whenComplete(() => sub.cancel());
  }

  setUp(() async {
    socket = 'spike-$pid';
    final ready = await Process.run('tmux', ['-L', socket, '-f', '/dev/null',
      'new-session', '-d', '-x', '80', '-y', '24', '-s', 'spike']);
    expect(ready.exitCode, 0, reason: '${ready.stderr}');

    // tmux control mode requires a PTY (tcgetattr fails on a plain pipe) -
    // the `script` wrapper allocates one. Over SSH the app gets a PTY from
    // the ssh channel instead (same as iTerm2).
    ccProcess = await Process.start('script', [
      '-qefc',
      'tmux -L $socket -f /dev/null -CC attach-session -t spike',
      '/dev/null',
    ]);
    client = ControlModeClient(
      input: ccProcess.stdout,
      output: ccProcess.stdin,
    );
  });

  tearDown(() async {
    client.dispose();
    ccProcess.kill(ProcessSignal.sigterm);
    await Process.run('tmux', ['-L', socket, 'kill-server']);
  });

  test('attaches, receives session-changed and runs commands', () async {
    final session = await waitFor(
        client.sessionChanged, (s) => s == 'spike',
        timeout: const Duration(seconds: 15));
    expect(session, 'spike');

    final result = await client.runCommand('display-message -p spike-ok')
        .timeout(const Duration(seconds: 10));
    expect(result, 'spike-ok');
  });

  test('send-keys reaches the pane and output arrives', () async {
    await waitFor(client.sessionChanged, (s) => s == 'spike',
        timeout: const Duration(seconds: 15));

    // Wait until the shell in the pane is ready: send a harmless echo and
    // expect its echo back.
    client.sendKeys('%0', 'echo from-keys');
    client.sendEnter('%0');

    await waitFor(
      client.paneOutput,
      (o) => o.paneId == '%0' && o.line.contains('from-keys'),
      timeout: const Duration(seconds: 10),
    );
  });

  test('capture-pane returns scrollback', () async {
    await waitFor(client.sessionChanged, (s) => s == 'spike',
        timeout: const Duration(seconds: 15));

    client.sendKeys('%0', 'echo history-marker');
    client.sendEnter('%0');
    await waitFor(
      client.paneOutput,
      (o) => o.line.contains('history-marker'),
      timeout: const Duration(seconds: 10),
    );

    final history = await client.captureHistory('%0', lines: 50)
        .timeout(const Duration(seconds: 10));
    expect(history, contains('history-marker'));
  });
}
