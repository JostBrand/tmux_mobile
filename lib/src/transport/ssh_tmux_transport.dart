import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';

/// An active tmux control-mode connection over SSH.
class TmuxConnection {
  TmuxConnection({
    required this.sshClient,
    required this.session,
    required this.control,
  });

  final SSHClient sshClient;
  final SSHSession session;
  final ControlModeClient control;

  void resize(int width, int height) => session.resizeTerminal(width, height);

  Future<void> close() async {
    control.dispose();
    await sshClient.close();
  }
}

/// Adapts the dartssh2 session stdin (`StreamSink<Uint8List>`) to the
/// `StreamSink<List<int>>` the [ControlModeClient] expects.
class _Uint8ListSinkAdapter implements StreamSink<List<int>> {
  _Uint8ListSinkAdapter(this._inner);

  final StreamSink<Uint8List> _inner;

  @override
  void add(List<int> data) =>
      _inner.add(data is Uint8List ? data : Uint8List.fromList(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      _inner.addStream(stream.map(
          (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk)));

  @override
  Future<void> get done => _inner.done;

  @override
  Future<void> close() => _inner.close();
}

/// SSH transport: connects to a remote host and attaches a tmux
/// control-mode client (`tmux -CC attach-session`) on a PTY session -
/// the same approach iTerm2 uses for its tmux integration.
class SshTmuxTransport {
  SshTmuxTransport({
    required this.host,
    required this.username,
    this.port = 22,
    this.identity,
    this.passwordPrompt,
    this.onVerifyHostKey,
  });

  final String host;
  final String username;
  final int port;

  /// Client key for public-key auth (nil = password/keyboard-interactive
  /// via [passwordPrompt]).
  final SSHKeyPair? identity;
  final Future<String?> Function()? passwordPrompt;

  /// Host key verification callback. Defaults to TOFU (accept anything);
  /// persistent known-hosts handling ships with the profile UI (M3).
  final SSHHostkeyVerifyHandler? onVerifyHostKey;

  Future<TmuxConnection> connect(
    String sessionName, {
    int width = 80,
    int height = 24,
    Duration timeout = const Duration(seconds: 15),
    String? socketName,
  }) async {
    final socket = await SSHSocket.connect(host, port, timeout: timeout);
    final client = SSHClient(
      socket,
      username: username,
      identities: identity == null ? null : [identity!],
      onPasswordRequest: passwordPrompt == null ? null : () => passwordPrompt!(),
      onVerifyHostKey: onVerifyHostKey ?? (type, fingerprint) => true,
      keepAliveInterval: const Duration(seconds: 10),
    );
    await client.authenticated;
    final socketArg = socketName == null ? '' : '-L $socketName ';
    final session = await client.execute(
      'tmux $socketArg-CC attach-session -t $sessionName',
      pty: SSHPtyConfig(type: 'xterm-256color', width: width, height: height),
    );
    return TmuxConnection(
      sshClient: client,
      session: session,
      control: ControlModeClient(
        // Normalize to Stream<List<int>>: the utf8 decoder in the client
        // cannot bind to a raw Stream<Uint8List>.
        input: session.stdout.map<List<int>>((chunk) => chunk),
        output: _Uint8ListSinkAdapter(session.stdin),
      ),
    );
  }
}
