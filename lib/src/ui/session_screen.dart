import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tmux_mobile/src/config/server_config.dart';
import 'package:tmux_mobile/src/notifications/activity_notifier.dart';
import 'package:tmux_mobile/src/config/settings_store.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/render/pane_output_feeder.dart';
import 'package:tmux_mobile/src/transport/session_factory.dart';
import 'package:tmux_mobile/src/ui/keybar.dart';
import 'package:tmux_mobile/src/ui/pane_history_sheet.dart';
import 'package:tmux_mobile/src/ui/pane_view.dart';
import 'package:tmux_mobile/src/ui/prefix_menu_sheet.dart';
import 'package:tmux_mobile/src/ui/target_picker_sheet.dart';
import 'package:tmux_mobile/src/utils/ansi.dart';
import 'package:tmux_mobile/src/utils/keyboard_input.dart';
import 'package:xterm/xterm.dart';

enum ConnectionStatus { connected, reconnecting, failed }

/// One live tmux session: the current pane rendered by [PaneView], a
/// keybar at the bottom, horizontal swipes to switch the pane, a
/// history sheet (server-side scrollback) and a PREFIX BUTTON.
///
/// Prefix tap = MOD MODE: the prefix menu sheet opens AND the pane area
/// above it becomes gesture-active (terminal input locked):
///   swipe right  -> split-window -h      swipe up   -> new-window
///   swipe down   -> split-window -v      swipe left -> previous-window
///   two-finger right -> break-pane
/// Mod mode ends when the sheet closes or 2.5s after the last action.
///
/// RECONNECT: when the SSH channel dies, [onReconnect] reattaches the
/// same session (up to 5 attempts with 3s backoff); the status dot in
/// the app bar shows connected/reconnecting/failed.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.client,
    this.title,
    this.onDispose,
    this.onReconnect,
    this.settingsStore,
    this.activityNotifier,
    this.activityMonitor,
  });

  final ControlModeClient client;
  final String? title;

  /// Called when the screen is disposed (closes the SSH connection).
  final Future<void> Function()? onDispose;

  /// Reattaches to the same session after a connection loss; returns a
  /// fresh control client (the old one is dead).
  final Future<OpenSession> Function()? onReconnect;

  /// Persists app settings (font size, haptics); nullable in tests.
  final SettingsStore? settingsStore;

  /// System notifications for hidden-pane activity; nullable in tests.
  final ActivityNotifier? activityNotifier;

  /// Injectable for tests (fake clock); defaults to real time.
  final ActivityMonitor? activityMonitor;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late ControlModeClient _client;
  late Future<void> Function() _closeCurrentSession;
  String _currentPane = '%0';
  ServerConfig? _serverConfig;
  AppSettings _settings = const AppSettings();
  String? _windowName;
  ConnectionStatus _status = ConnectionStatus.connected;
  late final ActivityMonitor _activityMonitor;
  bool _introspected = false;
  bool _reconnecting = false;
  final _knownPanes = <String>{'%0'};
  final _terminals = <String, Terminal>{};
  final _feeders = <String, PaneOutputFeeder>{};
  StreamSubscription<PaneOutput>? _subscription;
  StreamSubscription<String>? _windowSubscription;
  StreamSubscription<void>? _exitSubscription;

  // Mod mode (prefix gesture layer).
  bool _modMode = false;
  bool _menuOpen = false;
  Timer? _modTimer;
  int _maxPointers = 1;
  final Map<int, Offset> _pointerStart = {};
  Offset _gestureDelta = Offset.zero;

  @override
  void initState() {
    super.initState();
    _client = widget.client;
    _activityMonitor = widget.activityMonitor ?? ActivityMonitor();
    _closeCurrentSession = widget.onDispose ?? () async {};
    _wireClient();
    _ensurePane(_currentPane);
    final store = widget.settingsStore;
    if (store != null) {
      unawaited(store.load().then((settings) {
        if (mounted) {
          setState(() => _settings = settings);
        }
      }));
    }
  }

  /// (Re)subscribes the client-driven wiring. Called on init and after
  /// every reconnect swap.
  void _wireClient() {
    _subscription?.cancel();
    _windowSubscription?.cancel();
    _exitSubscription?.cancel();
    _subscription = _client.paneOutput.listen((output) {
      if (_knownPanes.add(output.paneId)) {
        _ensurePane(output.paneId);
        setState(() {});
      }
      final notifier = widget.activityNotifier;
      if (notifier != null && output.paneId != _currentPane) {
        // tmux monitor-activity semantics: only after a silent period.
        if (_activityMonitor.onPaneOutput(output.paneId)) {
          unawaited(notifier.notify(
            title: widget.title ?? 'tmux session',
            body: 'Activity in pane ${output.paneId}',
          ));
        }
      }
    });
    _windowSubscription = _client.windowRenamed.listen((name) {
      setState(() => _windowName = name);
    });
    _client.windowPaneChanged.listen((paneId) {
      if (_knownPanes.add(paneId)) {
        _ensurePane(paneId);
        setState(() {});
      }
    });
    _exitSubscription = _client.exited.listen((_) => unawaited(_handleDisconnect()));
    _client.sessionChanged.listen((session) {
      if (!_introspected) {
        _introspected = true;
        unawaited(_introspectServer(session));
      }
    });
  }

  /// Reattaches the same session after the connection died.
  Future<void> _handleDisconnect() async {
    final onReconnect = widget.onReconnect;
    if (onReconnect == null || _reconnecting) {
      return;
    }
    _reconnecting = true;
    setState(() => _status = ConnectionStatus.reconnecting);
    var attempts = 0;
    while (mounted && attempts < 5) {
      attempts++;
      try {
        final session = await onReconnect();
        if (!mounted) {
          await session.close();
          return;
        }
        _swapClient(session);
        setState(() => _status = ConnectionStatus.connected);
        _reconnecting = false;
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    _reconnecting = false;
    if (mounted) {
      setState(() => _status = ConnectionStatus.failed);
    }
  }

  /// Swaps in a fresh client after reconnect and rewires everything
  /// (terminals persist, feeders/seeders are recreated).
  void _swapClient(OpenSession session) {
    final oldClose = _closeCurrentSession;
    unawaited(oldClose());
    _closeCurrentSession = session.close;
    _client.dispose();
    _client = session.client;
    _introspected = false;
    _serverConfig = null;
    for (final paneId in _knownPanes) {
      _feeders[paneId]?.dispose();
      final feeder = PaneOutputFeeder(
        client: _client,
        paneId: paneId,
        terminal: _terminals[paneId]!,
      );
      _feeders[paneId] = feeder;
      unawaited(feeder.seedScreen());
    }
    _wireClient();
  }

  @override
  void dispose() {
    _modTimer?.cancel();
    _windowSubscription?.cancel();
    _exitSubscription?.cancel();
    _subscription?.cancel();
    for (final feeder in _feeders.values) {
      feeder.dispose();
    }
    unawaited(_closeCurrentSession());
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
      client: _client,
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
      onText: (text) => _client.sendKeys(paneId, text),
      onEnter: () => _client.sendEnter(paneId),
      onBackspace: () => _client.sendKeys(paneId, 'BSpace'),
    );
  }

  /// One-shot server introspection + session hygiene on attach.
  Future<void> _introspectServer(String sessionName) async {
    try {
      final prefixOut = await _client.runCommand('show-options -g prefix');
      final keysOut = await _client.runCommand('list-keys');
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
      await _client.runCommand(
          'set-option -t ${_quote(sessionName)} detach-on-destroy off');
    } catch (_) {
      // Non-fatal.
    }
    try {
      // Adopt the window size ONCE: the control client's size influences
      // window-size=smallest servers, so matching the existing window
      // avoids shrinking panes for desktop clients.
      final size = await _client
          .runCommand("display-message -p '#{window_width}x#{window_height}'");
      final match = RegExp(r'(\d+)x(\d+)').firstMatch(size.trim());
      if (match != null) {
        final width = int.parse(match.group(1)!);
        final height = int.parse(match.group(2)!);
        await _client.runCommand('refresh-client -C $width,$height');
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

  // --- Mod mode -----------------------------------------------------------

  void _enterModMode() {
    if (_settings.hapticFeedback) {
      HapticFeedback.selectionClick();
    }
    setState(() => _modMode = true);
    _modTimer?.cancel();
    _modTimer = Timer(const Duration(milliseconds: 2500), _exitModMode);
  }

  void _exitModMode() {
    _modTimer?.cancel();
    if (_modMode && mounted) {
      setState(() => _modMode = false);
    }
  }

  /// Executes a mod command, closes the menu sheet and surfaces errors
  /// (e.g. break-pane in a single-pane window) as a snackbar.
  void _runModCommand(String command) {
    _exitModMode();
    if (_menuOpen && mounted) {
      Navigator.of(context).pop();
      _menuOpen = false;
    }
    unawaited(_client.runCommand(command).then((result) {
      final text = result.trim();
      if (text.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('tmux: $text')),
        );
      }
    }).catchError((_) {}));
  }

  /// Recognizer path (normal mode only): horizontal swipes switch the
  /// displayed pane. Mod-mode gestures are handled by the raw pointer
  /// analysis below (multi-finger drags are unreliable through the
  /// gesture arena).
  void _handleDragEnd({required bool horizontal, required double velocity}) {
    if (_modMode || velocity.abs() < 100) {
      return;
    }
    if (horizontal) {
      _switchPane(velocity < 0 ? 1 : -1);
    }
  }

  // Raw pointer analysis for mod mode: not part of the gesture arena, so
  // multi-finger swipes work reliably. Displacement-based.
  void _onPointerDown(PointerDownEvent event) {
    if (_pointerStart.isEmpty) {
      _gestureDelta = Offset.zero;
      _maxPointers = 1;
    } else {
      _maxPointers = _pointerStart.length + 1;
    }
    _pointerStart[event.pointer] = event.position;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_modMode) {
      _pointerStart.remove(event.pointer);
      return;
    }
    final start = _pointerStart.remove(event.pointer);
    if (start == null) {
      return;
    }
    _gestureDelta += event.position - start;
    if (_pointerStart.isNotEmpty) {
      return;
    }
    final delta = _gestureDelta / _maxPointers.toDouble();
    if (delta.distance < 12) {
      // Tap: cancel mod mode (closes the menu sheet).
      _exitModMode();
      if (_menuOpen && mounted) {
        Navigator.of(context).pop();
        _menuOpen = false;
      }
      return;
    }
    final twoFingers = _maxPointers >= 2;
    String? command;
    if (delta.dx.abs() >= delta.dy.abs()) {
      final right = delta.dx > 0;
      if (twoFingers) {
        if (right) {
          command = 'break-pane';
        }
      } else {
        command = right ? 'split-window -h' : 'previous-window';
      }
    } else {
      command = delta.dy > 0 ? 'split-window -v' : 'new-window';
    }
    if (command != null) {
      _runModCommand(command);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointerStart.remove(event.pointer);
  }

  void _setFontSize(double size) {
    final clamped = size.clamp(10.0, 24.0);
    setState(() => _settings = _settings.copyWith(fontSize: clamped));
    final store = widget.settingsStore;
    if (store != null) {
      unawaited(store.save(_settings));
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    translateKeyboardInput(
      text,
      onText: (chunk) => _client.sendKeys(_currentPane, chunk),
      onEnter: () => _client.sendEnter(_currentPane),
      onBackspace: () => _client.sendKeys(_currentPane, 'BSpace'),
    );
  }

  /// Copies the current selection if any, otherwise the last non-empty
  /// line of the pane (the mobile-friendly default for copying output).
  Future<void> _copy() async {
    final terminal = _ensurePane(_currentPane);
    final lines = [
      for (final line in terminal.buffer.getText().split('\n'))
        line.trimRight(),
    ];
    final last = lines.lastWhere((line) => line.isNotEmpty, orElse: () => '');
    if (last.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: last));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Copied last line'),
              duration: Duration(seconds: 1)),
        );
      }
    }
  }

  void _switchPane(int direction) {
    final panes = _knownPanes.toList()
      ..sort((a, b) => _paneIndex(a).compareTo(_paneIndex(b)));
    if (panes.length < 2) {
      return;
    }
    final current = panes.indexOf(_currentPane);
    final next = panes[(current + direction + panes.length) % panes.length];
    _client.sendCommand('select-pane -t $next');
    setState(() => _currentPane = next);
  }

  static int _paneIndex(String paneId) =>
      int.tryParse(paneId.substring(1)) ?? 0;

  void _openPrefixMenu() {
    final config = _serverConfig;
    if (config == null) {
      return;
    }
    _enterModMode();
    _menuOpen = true;
    // NON-modal sheet: the pane area above stays gesture-active (a modal
    // sheet's barrier would swallow the mod-mode swipes).
    final controller = _scaffoldKey.currentState!.showBottomSheet(
      (context) => PrefixMenuSheet(
        config: config,
        onExecute: (command) {
          _runModCommand(command);
        },
        onSendPrefix: () {
          _runModCommand('send-prefix -t $_currentPane');
        },
        onWindowPicker: _openWindowPicker,
        onPanePicker: _openPanePicker,
        onCopyMode: () => _runModCommand('copy-mode'),
        onCopySelection: _copyTmuxSelection,
      ),
    );
    controller.closed.whenComplete(() {
      _menuOpen = false;
      _exitModMode();
    });
  }

  /// Copies the tmux copy-mode selection: cancels the mode with a copy,
  /// then pulls the paste buffer into the clipboard.
  void _copyTmuxSelection() {
    _runModCommand('send-keys -t $_currentPane -X copy-selection-and-cancel');
    unawaited(() async {
      try {
        final buffer = await _client.runCommand('show-buffer');
        final text = buffer.trimRight();
        if (text.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: text));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Copied selection'),
                  duration: Duration(seconds: 1)),
            );
          }
        }
      } catch (_) {
        // No selection - the snackbar above already covers the common
        // case; keep quiet here.
      }
    }());
  }

  void _openWindowPicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => TargetPickerSheet(
        title: 'Windows',
        fetch: () async {
          final out = await _client.runCommand(
              "list-windows -F '#{window_index}:#{window_name}'");
          return [
            for (final line in out.split('\n'))
              if (line.trim().isNotEmpty)
                () {
                  final parts = line.trim().split(':');
                  final index = parts.first;
                  final name =
                      parts.length > 1 ? parts.sublist(1).join(':') : index;
                  return TargetOption(id: '@$index', label: name);
                }(),
          ];
        },
        onSelected: (option) =>
            _runModCommand('select-window -t ${option.id}'),
      ),
    );
  }

  void _openPanePicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => TargetPickerSheet(
        title: 'Panes',
        fetch: () async {
          final out = await _client.runCommand(
              "list-panes -F '#{pane_id}:#{pane_current_command}'");
          return [
            for (final line in out.split('\n'))
              if (line.trim().isNotEmpty)
                () {
                  final parts = line.trim().split(':');
                  final id = parts.first;
                  final command =
                      parts.length > 1 ? parts.sublist(1).join(':') : id;
                  return TargetOption(id: id, label: command);
                }(),
          ];
        },
        onSelected: (option) {
          _runModCommand('select-pane -t ${option.id}');
          _knownPanes.add(option.id);
          setState(() => _currentPane = option.id);
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
          final content = await _client
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
    final theme = Theme.of(context);
    final prefix = _serverConfig?.displayPrefix;
    final windowSuffix = _windowName == null ? '' : ' · $_windowName';
    final statusColor = switch (_status) {
      ConnectionStatus.connected => Colors.greenAccent,
      ConnectionStatus.reconnecting => Colors.amber,
      ConnectionStatus.failed => theme.colorScheme.error,
    };
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const Key('connection-status-dot'),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${widget.title ?? 'tmux session'}$windowSuffix',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (_status == ConnectionStatus.failed)
            IconButton(
              tooltip: 'Reconnect',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() => _status = ConnectionStatus.reconnecting);
                _reconnecting = false;
                unawaited(_handleDisconnect());
              },
            ),
          IconButton(
            tooltip: 'Smaller text',
            icon: const Icon(Icons.text_decrease, size: 18),
            onPressed: () => _setFontSize(_settings.fontSize - 1),
          ),
          IconButton(
            tooltip: 'Larger text',
            icon: const Icon(Icons.text_increase, size: 18),
            onPressed: () => _setFontSize(_settings.fontSize + 1),
          ),
          FilledButton.tonalIcon(
            onPressed: _serverConfig == null ? null : _openPrefixMenu,
            style: _modMode
                ? FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  )
                : null,
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
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: GestureDetector(
                  key: const Key('pane-swipe-area'),
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: (details) => _handleDragEnd(
                      horizontal: true,
                      velocity: details.primaryVelocity ?? 0),
                  onVerticalDragEnd: (details) => _handleDragEnd(
                      horizontal: false,
                      velocity: details.primaryVelocity ?? 0),
                  child: AbsorbPointer(
                    absorbing: _modMode,
                    child: PaneView(
                      terminal: _ensurePane(_currentPane),
                      textStyle: TerminalStyle(fontSize: _settings.fontSize),
                    ),
                  ),
                ),
              ),
            ),
            Keybar(
              onKey: (key) => _client.sendKeys(_currentPane, key),
              onPaste: _paste,
              onCopy: _copy,
            ),
          ],
        ),
      ),
    );
  }
}
