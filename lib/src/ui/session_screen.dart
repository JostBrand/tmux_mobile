import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/render/pane_output_feeder.dart';
import 'package:tmux_mobile/src/ui/keybar.dart';
import 'package:tmux_mobile/src/ui/pane_history_sheet.dart';
import 'package:tmux_mobile/src/ui/pane_view.dart';
import 'package:tmux_mobile/src/utils/ansi.dart';
import 'package:xterm/xterm.dart';

/// One live tmux session: the current pane rendered by [PaneView], a
/// keybar at the bottom, horizontal swipes to switch the pane, and a
/// swipe-down history sheet (server-side scrollback).
///
/// Terminals and output feeders are owned here per pane so they survive
/// pane switches (no missed output, persistent scrollback).
///
/// Pane switching is app-side: the app issues `select-pane` and keeps its
/// own notion of the current pane (tmux does not notify control clients
/// about active-pane changes).
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'tmux session'),
        actions: [
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
