import 'dart:async';

import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:xterm/xterm.dart';

/// Feeds tmux `%output` lines of one pane into an xterm [Terminal].
///
/// Initial screen state comes from `capture-pane -p -e` (deterministic -
/// `refresh-client -C` only redraws on a size CHANGE and would leave the
/// screen blank when the pane already has the client's size). Resizes use
/// `refresh-client -C` with the new size: tmux then redraws the pane and
/// the redraw arrives via `%output`.
///
/// Plain logic (no widgets) so it is testable without pumping a view.
class PaneOutputFeeder {
  PaneOutputFeeder({
    required this.client,
    required this.paneId,
    required this.terminal,
  }) {
    _subscription = client.paneOutput
        .where((output) => output.paneId == paneId)
        .listen((output) {
      terminal.write('${output.line}\n');
    });
  }

  final ControlModeClient client;
  final String paneId;
  final Terminal terminal;

  StreamSubscription<PaneOutput>? _subscription;
  Timer? _resizeDebounce;

  /// Seed the terminal with the pane's current screen.
  ///
  /// In fake test clients the command never completes - that is fine, the
  /// tests only assert that the command was sent.
  Future<void> seedScreen() async {
    try {
      final content = await client.runCommand('capture-pane -p -e -t $paneId');
      terminal.write(content);
    } catch (_) {
      // Pane lookup failed - request a redraw instead (forces via a size
      // change; same-size refresh is a no-op in tmux).
      final width = terminal.viewWidth;
      final height = terminal.viewHeight;
      unawaited(client
          .runCommand('refresh-client -C ${width - 1},$height')
          .catchError((_) => ''));
      unawaited(client
          .runCommand('refresh-client -C $width,$height')
          .catchError((_) => ''));
    }
  }

  /// Keep the pane size in sync with the terminal (debounced).
  void onTerminalResized(int width, int height) {
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 150), () {
      terminal.resize(width, height);
      unawaited(client
          .runCommand('refresh-client -C $width,$height')
          .catchError((_) => ''));
    });
  }

  void dispose() {
    _resizeDebounce?.cancel();
    _subscription?.cancel();
  }
}
