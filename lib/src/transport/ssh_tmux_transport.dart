import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:tmux_mobile/src/config/known_hosts.dart';
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
/// control-mode client on a PTY session - the same approach iTerm2 uses.
///
/// The remote command is `tmux -CC new-session -A -s <name>`:
/// attach to the session if it exists, CREATE it otherwise (a configured
/// profile name therefore never fails on a missing session).
class SshTmuxTransport {
  SshTmuxTransport({
    required this.host,
    required this.username,
    this.port = 22,
    this.identity,
    this.passwordPrompt,
    this.knownHosts,
  });

  final String host;
  final String username;
  final int port;

  /// Client key for public-key auth (nil = password/keyboard-interactive
  /// via [passwordPrompt]).
  final SSHKeyPair? identity;
  final Future<String?> Function()? passwordPrompt;

  /// Host key verification: TOFU on first connect, reject on mismatch.
  /// Without a store every key is accepted (tests, local sshd).
  final KnownHostsStore? knownHosts;

  /// Keyboard-interactive handler (2FA/TOTP): answers non-echo prompts
  /// with the password/OTP from [passwordPrompt], echo prompts with an
  /// empty string. Users with a second factor can connect through the
  /// same password prompt.
  FutureOr<List<String>?>? _onUserInfoRequest(SSHUserInfoRequest request) {
    final prompt = passwordPrompt;
    if (prompt == null) {
      return null;
    }
    return () async {
      final responses = <String>[];
      for (final entry in request.prompts) {
        if (entry.echo) {
          responses.add('');
        } else {
          responses.add(await prompt() ?? '');
        }
      }
      return responses;
    }();
  }

  Future<SSHClient> _connectClient({Duration timeout = const Duration(seconds: 30)}) async {
    final socket = await SSHSocket.connect(host, port, timeout: timeout);
    final client = SSHClient(
      socket,
      username: username,
      identities: identity == null ? null : [identity!],
      onPasswordRequest: passwordPrompt == null ? null : () => passwordPrompt!(),
      onUserInfoRequest: _onUserInfoRequest,
      onVerifyHostKey: _verifyHostKey,
      keepAliveInterval: const Duration(seconds: 10),
    );
    await client.authenticated;
    return client;
  }

  /// Runs one command over SSH and returns its output (throwing on
  /// connection problems). stderr is included by default (dartssh2 merges
  /// the streams); pass [captureStderr] false for output parsing.
  Future<String> runCommand(String command, {bool captureStderr = true}) async {
    final client = await _connectClient();
    try {
      final output = await client.run(command, stderr: captureStderr);
      return utf8.decode(output);
    } finally {
      await client.close();
    }
  }

  /// Lists the names of all running tmux sessions (empty when no server
  /// or no session exists).
  Future<List<String>> listSessions({String? socketName}) async {
    try {
      final socketArg = socketName == null ? '' : '-L $socketName ';
      // stderr off: "error connecting to ..." would otherwise land in the
      // output and parse as a session name.
      final output = await runCommand(
          "tmux ${socketArg}list-sessions -F '#{session_name}'",
          captureStderr: false);
      return [
        for (final line in output.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<TmuxConnection> connect(
    String sessionName, {
    int width = 80,
    int height = 24,
    Duration timeout = const Duration(seconds: 30),
    String? socketName,
  }) async {
    final client = await _connectClient(timeout: timeout);
    final socketArg = socketName == null ? '' : '-L $socketName ';
    final quoted = _quote(sessionName);
    final session = await client.execute(
      'tmux $socketArg-CC new-session -A -s $quoted',
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

  static String _quote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";

  FutureOr<bool> _verifyHostKey(String type, Uint8List fingerprint) async {
    final store = knownHosts;
    if (store == null) {
      return true;
    }
    final hostPort = '$host:$port';
    final offered = encodeHostFingerprint(fingerprint);
    final known = await store.lookup(hostPort);
    if (!verifyHostKeyDecision(
        knownFingerprint: known, offeredFingerprint: offered)) {
      return false;
    }
    if (known == null) {
      await store.store(hostPort, offered);
    }
    return true;
  }
}
