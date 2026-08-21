import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/render/pane_screen.dart';
import 'package:tmux_mobile/src/ui/keybar.dart';

/// One live tmux session: the current pane rendered by [PaneScreen], a
/// keybar at the bottom, and horizontal swipes to switch the pane.
///
/// Pane switching is app-side: the app issues `select-pane` and keeps its
/// own notion of the current pane (tmux does not notify control clients
/// about active-pane changes). The known pane set grows as panes emit
/// output; full layout tracking arrives with %layout-change parsing (M3).
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.client});

  final ControlModeClient client;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  String _currentPane = '%0';
  final _knownPanes = <String>{'%0'};
  StreamSubscription<PaneOutput>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.client.paneOutput.listen((output) {
      if (_knownPanes.add(output.paneId)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                child: PaneScreen(
                  client: widget.client,
                  paneId: _currentPane,
                ),
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
