import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Renders one tmux pane: an xterm [TerminalView] bound to a [Terminal]
/// owned by the [SessionScreen] (terminals outlive pane switches, so
/// per-pane scrollback and screen state persist).
class PaneView extends StatelessWidget {
  const PaneView({super.key, required this.terminal, this.textStyle});

  final Terminal terminal;
  final TerminalStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      terminal,
      autofocus: false,
      // autoResize off: the terminal's logical size follows the SERVER
      // (window-size adoption on attach, explicit resizes). With
      // autoResize the viewport constantly fights the adopted size in an
      // endless resize->refresh-client loop.
      autoResize: false,
      textStyle: textStyle ?? const TerminalStyle(),
    );
  }
}
