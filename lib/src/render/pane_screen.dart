import 'package:flutter/material.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/render/pane_output_feeder.dart';
import 'package:xterm/xterm.dart';

/// Renders a single tmux pane: an xterm [TerminalView] driven by the
/// control-mode client's `%output` notifications.
class PaneScreen extends StatefulWidget {
  const PaneScreen({
    super.key,
    required this.client,
    required this.paneId,
    this.terminal,
  });

  final ControlModeClient client;
  final String paneId;

  /// Injectable for tests (otherwise created in state).
  final Terminal? terminal;

  @override
  State<PaneScreen> createState() => _PaneScreenState();
}

class _PaneScreenState extends State<PaneScreen> {
  late final Terminal _terminal;
  late final PaneOutputFeeder _feeder;

  @override
  void initState() {
    super.initState();
    _terminal = widget.terminal ??
        Terminal(
          maxLines: 10000,
          onResize: (width, height, pixelWidth, pixelHeight) {
            _feeder.onTerminalResized(width, height);
          },
        );
    _feeder = PaneOutputFeeder(
      client: widget.client,
      paneId: widget.paneId,
      terminal: _terminal,
    );
    _feeder.seedScreen();
  }

  @override
  void dispose() {
    _feeder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TerminalView(_terminal, autofocus: false);
  }
}
