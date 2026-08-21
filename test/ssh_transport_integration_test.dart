import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/transport/ssh_tmux_transport.dart';

/// End-to-end SSH transport test: connects to the per-workspace sshd
/// (127.0.0.1:2222, started by the workspace startup script) with the
/// mounted workspace key and attaches a control-mode client over a real
/// SSH channel to the local tmux server.
///
/// Skips when sshd is not running (e.g. older dev image).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const port = 2222;

  Future<bool> sshdReachable() async {
    try {
      final socket = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

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
      throw TimeoutException('condition not met');
    }).whenComplete(() => sub.cancel());
  }

  test('connects over SSH and drives tmux control mode', () async {
    if (!await sshdReachable()) {
      markTestSkipped('workspace sshd not running on 127.0.0.1:$port');
      return;
    }

    final socketName = 'spike-ssh-$pid';
    final ready = await Process.run('tmux', ['-L', socketName, '-f', '/dev/null',
      'new-session', '-d', '-x', '80', '-y', '24', '-s', 'spike']);
    expect(ready.exitCode, 0, reason: '${ready.stderr}');

    final keyPem = await File('${Platform.environment['HOME']}/.ssh/id_ed25519')
        .readAsString();
    final identity = SSHKeyPair.fromPem(keyPem).first;

    final transport = SshTmuxTransport(
      host: '127.0.0.1',
      port: port,
      username: 'ubuntu',
      identity: identity,
    );

    TmuxConnection? connection;
    try {
      connection = await transport.connect('spike',
          width: 80, height: 24, socketName: socketName);
      final control = connection.control;

      await waitFor(control.sessionChanged, (s) => s == 'spike',
          timeout: const Duration(seconds: 15));

      // Session auto-detect: listSessions must see the running session.
      final sessions = await transport.listSessions(socketName: socketName);
      expect(sessions, contains('spike'));

      final result = await control
          .runCommand('display-message -p ssh-ok')
          .timeout(const Duration(seconds: 10));
      expect(result, 'ssh-ok');

      control.sendKeys('%0', 'echo via-ssh');
      control.sendEnter('%0');
      await waitFor(
        control.paneOutput,
        (o) => o.paneId == '%0' && o.line.contains('via-ssh'),
        timeout: const Duration(seconds: 10),
      );

      // Scrollback/screen seeding path (what PaneOutputFeeder uses on
      // attach): capture-pane must return the pane content including the
      // command typed above.
      final history = await control
          .captureHistory('%0', lines: 100)
          .timeout(const Duration(seconds: 10));
      expect(history, contains('via-ssh'));
    } finally {
      await connection?.close();
      await Process.run('tmux', ['-L', socketName, 'kill-server']);
    }
  });
}
