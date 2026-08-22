import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tmux_mobile/src/config/server_config.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/render/pane_output_feeder.dart';
import 'package:tmux_mobile/src/ui/keybar.dart';
import 'package:tmux_mobile/src/ui/pane_history_sheet.dart';
import 'package:tmux_mobile/src/ui/pane_view.dart';
import 'package:tmux_mobile/src/ui/prefix_menu_sheet.dart';
import 'package:tmux_mobile/src/utils/ansi.dart';
import 'package:tmux_mobile/src/utils/keyboard_input.dart';
import 'package:xterm/xterm.dart';

/// One live tmux session: the current pane rendered by [PaneView], a
/// keybar at the bottom, horizontal swipes to switch the pane, a
/// swipe-down history sheet (server-side scrollback) and a PREFIX BUTTON
/// opening the server's real prefix bindings as commands (the mobile
/// replacement for the tmux prefix key).
///
/// On attach the app introspects the server (`list-keys`,
/// `show-options -g prefix`) to label the prefix menu with the REAL
/// bindings, applies session-scoped hygiene (`detach-on-destroy off`)
/// and adopts the server's window size once (so a phone connect does not
/// shrink panes for desktop clients).
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.client,
    this.title,
    this.onDispose,
  });

  final ControlModeClient client;
  final String? title;

  /// Called when the screen is disposed (closes the SSH connection).
  final Future<void> Function()? onDispose;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  String _currentPane = '%0';
  ServerConfig? _serverConfig;
  bool _introspected = false;
  final _knownPanes = <String>{'%0'};
  final _terminals = <String, Terminal>{};
  final _feeders = <String, PaneOutputFeeder>{};
  StreamSubscription<PaneOutput>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.client.paneOutput.listen((output) {
      if (_knownPanes.add(output.paneId)) {
        _ensurePane(output.paneId);
        setState(() {});
      }
    });
    widget.client.sessionChanged.listen((session) {
      if (!_introspected) {
        _introspected = true;
        unawaited(_introspectServer(session));
      }
    });
    _ensurePane(_currentPane);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    for (final feeder in _feeders.values) {
      feeder.dispose();
    }
    final onDispose = widget.onDispose;
    if (onDispose != null) {
      unawaited(onDispose());
    }
    super.dispose();
  }

  Terminal _ensurePane(String paneId) {
    var terminal = _terminals[paneId];
    if (terminal != null) {
      return terminal;
    }
    terminal = Terminal(
      maxLines: 10000,
      onOutput: (data) => _handleKeyboardInput(paneId, data),
      onResize: (width, height, pixelWidth, pixelHeight) {
        _feeders[paneId]?.onTerminalResized(width, height);
      },
    );
    _terminals[paneId] = terminal;
    final feeder = PaneOutputFeeder(
      client: widget.client,
      paneId: paneId,
      terminal: terminal,
    );
    _feeders[paneId] = feeder;
    unawaited(feeder.seedScreen());
    return terminal;
  }

  /// Soft-keyboard input: xterm emits typed text via onOutput; forward it
  /// to the pane via send-keys (Enter/Backspace become key names, the
  /// rest is sent as literal text - batched).
  void _handleKeyboardInput(String paneId, String data) {
    translateKeyboardInput(
      data,
      onText: (text) => widget.client.sendKeys(paneId, text),
      onEnter: () => widget.client.sendEnter(paneId),
      onBackspace: () => widget.client.sendKeys(paneId, 'BSpace'),
    );
  }

  /// One-shot server introspection + session hygiene on attach.
  Future<void> _introspectServer(String sessionName) async {
    try {
      final prefixOut =
          await widget.client.runCommand('show-options -g prefix');
      final keysOut = await widget.client.runCommand('list-keys');
      final config = ServerConfig(
        prefix: parsePrefix(prefixOut),
        bindings: parseListKeys(keysOut),
      );
      if (mounted) {
        setState(() => _serverConfig = config);
      }
    } catch (_) {
      // Prefix menu falls back to built-in actions.
    }
    try {
      await widget.client.runCommand(
          'set-option -t ${_quote(sessionName)} detach-on-destroy off');
    } catch (_) {
      // Non-fatal.
    }
    try {
      // Adopt the window size ONCE: the control client's size influences
      // window-size=smallest servers, so matching the existing window
      // avoids shrinking panes for desktop clients.
      final size = await widget.client
          .runCommand("display-message -p '#{window_width}x#{window_height}'");
      final match = RegExp(r'(\d+)x(\d+)').firstMatch(size.trim());
      if (match != null) {
        final width = int.parse(match.group(1)!);
        final height = int.parse(match.group(2)!);
        await widget.client.runCommand('refresh-client -C $width,$height');
        for (final terminal in _terminals.values) {
          terminal.resize(width, height);
        }
      }
    } catch (_) {
      // Keep the default size.
    }
  }

  static String _quote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";

  void _switchPane(int direction) {
    final panes = _knownPanes.toList()
      ..sort((a, b) => _paneIndex(a).compareTo(_paneIndex(b)));
    if (panes.length < 2) {
      return;
    }
    final current = panes.indexOf(_currentPane);
    final next = panes[(current + direction + panes.length) % panes.length];
    widget.client.sendCommand('select-pane -t $next');
    setState(() => _currentPane = next);
  }

  static int _paneIndex(String paneId) =>
      int.tryParse(paneId.substring(1)) ?? 0;

  void _openPrefixMenu() {
    final config = _serverConfig;
    if (config == null) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => PrefixMenuSheet(
        config: config,
        onExecute: (command) {
          unawaited(widget.client.runCommand(command).catchError((_) => ''));
        },
        onSendPrefix: () {
          widget.client.sendCommand('send-prefix -t $_currentPane');
        },
      ),
    );
  }

  void _openHistory() {
    final paneId = _currentPane;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PaneHistorySheet(
        paneId: paneId,
        fetchOlder: (depth) async {
          final content = await widget.client
              .runCommand('capture-pane -p -e -t $paneId -S -$depth')
              .timeout(const Duration(seconds: 10));
          return [
            for (final line in content.split('\n'))
              stripAnsi(line).trimRight(),
          ];
        },
        onCopy: (line) {
          Clipboard.setData(ClipboardData(text: line));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefix = _serverConfig?.displayPrefix;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'tmux session'),
        actions: [
          FilledButton.tonalIcon(
            onPressed: _serverConfig == null ? null : _openPrefixMenu,
            icon: const Icon(Icons.grid_view, size: 18),
            label: Text(prefix ?? '…'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.manage_search),
            onPressed: _openHistory,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                key: const Key('pane-swipe-area'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity < -100) {
                    _switchPane(1);
                  } else if (velocity > 100) {
                    _switchPane(-1);
                  }
                },
                child: PaneView(terminal: _ensurePane(_currentPane)),
              ),
            ),
            Keybar(
              onKey: (key) => widget.client.sendKeys(_currentPane, key),
            ),
          ],
        ),
      ),
    );
  }
}
