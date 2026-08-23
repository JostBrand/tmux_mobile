import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Renders one tmux pane: an xterm [TerminalView] bound to a [Terminal]
/// owned by the [SessionScreen] (terminals outlive pane switches, so
/// per-pane scrollback and screen state persist).
///
/// Mouse-wheel forwarding for TUI apps (opencode, vim, ...): xterm 4.0.0
/// does not wire PointerSignalEvents itself, so a Listener feeds scroll
/// events into [Terminal.mouseInput] - the SGR sequence lands in the
/// terminal's onOutput and is forwarded by the session screen as
/// `send-keys -M` (only when the pane enabled mouse reporting).
class PaneView extends StatelessWidget {
  const PaneView({
    super.key,
    required this.terminal,
    this.textStyle,
    this.viewKey,
    this.mouseEnabled = false,
  });

  final Terminal terminal;
  final TerminalStyle? textStyle;
  final GlobalKey<TerminalViewState>? viewKey;
  final bool mouseEnabled;

  void _onPointerSignal(PointerSignalEvent event) {
    if (!mouseEnabled || event is! PointerScrollEvent) {
      return;
    }
    final view = viewKey?.currentState;
    if (view == null) {
      return;
    }
    final render = view.renderTerminal;
    final cell = render.getCellOffset(event.localPosition);
    final button = event.scrollDelta.dy > 0
        ? TerminalMouseButton.wheelDown
        : TerminalMouseButton.wheelUp;
    // Wheel buttons must be reported as "down" (xterm's handler ignores
    // up-state wheel events).
    terminal.mouseInput(button, TerminalMouseButtonState.down, cell);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: TerminalView(
        key: viewKey,
        terminal,
        autofocus: false,
        // autoResize off: the terminal's logical size follows the SERVER
        // (window-size adoption on attach, explicit resizes). With
        // autoResize the viewport constantly fights the adopted size in an
        // endless resize->refresh-client loop.
        autoResize: false,
        textStyle: textStyle ?? const TerminalStyle(),
      ),
    );
  }
}
