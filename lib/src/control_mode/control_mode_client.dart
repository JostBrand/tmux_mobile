import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// A pane output notification (`%output <pane-id> <line>`).
class PaneOutput {
  const PaneOutput({required this.paneId, required this.line});

  final String paneId;
  final String line;
}

/// A minimal tmux control-mode (`-CC`) client.
///
/// Speaks the tmux control protocol over a byte stream - the stream comes
/// from a local `tmux -CC` subprocess in tests and will come from an SSH
/// session (dartssh2) in the app.
///
/// Protocol (see tmux(1), CONTROL MODE):
/// - Lines from tmux start with `%` followed by a notification name:
///   `%output <pane> <line>`, `%session-changed`, `%layout-change`, ...
/// - Command output is bracketed by `%begin` / `%end` and arrives raw
///   (unprefixed) between them.
/// - The client sends tmux commands as plain lines (`send-keys -t %0 ...`)
///   and control commands prefixed with `%` (`%subscribe`, `%exit`).
class ControlModeClient {
  ControlModeClient({required Stream<List<int>> input, required StreamSink<List<int>> output})
      : _input = input,
        _output = output {
    _spawnLineProcessor();
  }

  final Stream<List<int>> _input;
  final StreamSink<List<int>> _output;

  final StreamController<PaneOutput> _paneOutput =
      StreamController<PaneOutput>.broadcast();
  final StreamController<String> _sessionChanged =
      StreamController<String>.broadcast();
  final StreamController<void> _exit = StreamController<void>.broadcast();

  final List<String> _windows = [];
  String? _currentSession;

  bool _collecting = false;
  final StringBuffer _commandOutput = StringBuffer();
  final Queue<Completer<String>> _pendingCommands = Queue();

  Stream<PaneOutput> get paneOutput => _paneOutput.stream;
  Stream<String> get sessionChanged => _sessionChanged.stream;
  Stream<void> get exited => _exit.stream;
  String? get currentSession => _currentSession;

  /// Attach to a session (or create it) - only needed when the remote
  /// `tmux -CC` was started without an attach/new command.
  Future<void> attach(String sessionName) async {
    sendCommand('attach-session -t $sessionName');
  }

  void _spawnLineProcessor() {
    final decoded = _input
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        // PTY transports (script wrapper, SSH pty) deliver \r\n - strip the
        // carriage return before protocol parsing.
        .map((line) => line.endsWith('\r') ? line.substring(0, line.length - 1) : line);
    decoded.listen(_handleLine, onDone: () {
      // The stream can close after dispose() - guard the closed controller.
      if (!_exit.isClosed) {
        _exit.add(null);
      }
    });
  }

  void _handleLine(String line) {
    if (_collecting) {
      // Command output is bracketed by %begin/%end (success) or
      // %begin/%error (parse/exec failure) - complete on either.
      if (line.startsWith('%end') || line.startsWith('%error')) {
        _collecting = false;
        _completePendingCommand(_commandOutput.toString());
        _commandOutput.clear();
      } else if (!line.startsWith('%')) {
        _commandOutput.writeln(line);
      }
      return;
    }
    if (!line.startsWith('%')) {
      // Unprefixed output outside %begin/%end - ignore.
      return;
    }
    final parts = line.split(' ');
    final name = parts[0].substring(1);
    switch (name) {
      case 'begin':
        _collecting = true;
        _commandOutput.clear();
      case 'output':
        if (parts.length >= 3) {
          _paneOutput.add(PaneOutput(paneId: parts[1], line: parts.sublist(2).join(' ')));
        }
      case 'session-changed':
        if (parts.length >= 3) {
          _currentSession = parts[2];
          _sessionChanged.add(parts[2]);
        }
      case 'exit':
        _exit.add(null);
    }
  }

  void _writeLine(String line) {
    _output.add(utf8.encode('$line\n'));
  }

  void _completePendingCommand(String output) {
    // tmux sends an unsolicited %begin/%end pair right after attach - drop
    // it when no command is pending.
    if (_pendingCommands.isEmpty) {
      return;
    }
    final pending = _pendingCommands.removeFirst();
    pending.complete(output.trimRight());
  }

  /// Send a raw tmux command line (e.g. `send-keys -t %0 ls`).
  void sendCommand(String command) {
    _writeLine(command);
  }

  /// Send keystrokes to a pane (tmux `send-keys`).
  void sendKeys(String paneId, String keys) {
    sendCommand('send-keys -t $paneId -- ${_quoteArg(keys)}');
  }

  /// Send the Enter key to a pane.
  void sendEnter(String paneId) {
    sendCommand('send-keys -t $paneId Enter');
  }

  /// Run a tmux command and return its (unprefixed) output.
  ///
  /// Command output arrives between `%begin`/`%end`. Commands are
  /// serialized: tmux sends the pairs in order, so a FIFO queue of pending
  /// completers matches them up.
  Future<String> runCommand(String command) {
    final completer = Completer<String>();
    _pendingCommands.add(completer);
    _writeLine(command);
    return completer.future;
  }

  /// Fetch pane scrollback via `capture-pane -p -e`.
  Future<String> captureHistory(String paneId, {int lines = 200}) {
    return runCommand('capture-pane -p -e -t $paneId -S -$lines');
  }

  /// Detach cleanly (does NOT kill the session).
  void detach() {
    _writeLine('detach-client');
  }

  void dispose() {
    _paneOutput.close();
    _sessionChanged.close();
    _exit.close();
  }

  static String _quoteArg(String value) => "'${value.replaceAll("'", "'\\''")}'";
}
