import 'package:flutter/material.dart';
import 'package:tmux_mobile/src/config/server_config.dart';

/// Fallback actions when the server's bindings are unavailable - always
/// work because they are tmux commands, not key bindings.
const List<KeyBinding> fallbackPrefixActions = [
  KeyBinding(table: 'prefix', key: 'c', command: 'new-window'),
  KeyBinding(table: 'prefix', key: '"', command: 'split-window -h'),
  KeyBinding(table: 'prefix', key: '%', command: 'split-window -v'),
  KeyBinding(table: 'prefix', key: 'n', command: 'next-window'),
  KeyBinding(table: 'prefix', key: 'p', command: 'previous-window'),
  KeyBinding(table: 'prefix', key: 'x', command: 'kill-pane'),
  KeyBinding(table: 'prefix', key: '&', command: 'kill-window'),
  KeyBinding(table: 'prefix', key: 'd', command: 'detach-client'),
];

/// Gesture hints for well-known commands (shown in the sheet; the same
/// gestures work on the pane area above the open sheet).
const Map<String, String> gestureHints = {
  'new-window': 'swipe up',
  'split-window -h': 'swipe right',
  'split-window -v': 'swipe down',
  'previous-window': 'swipe left',
  'break-pane': '2-finger right',
};

/// The mobile replacement for the tmux prefix key: a compact bottom
/// sheet listing the server's REAL prefix bindings (labels from
/// `list-keys`), each executing its tmux command directly. While the
/// sheet is open the pane area above it stays gesture-active (mod mode):
/// swipe right/down = split, up = new window, left = previous window,
/// two-finger right = break-pane.
class PrefixMenuSheet extends StatelessWidget {
  const PrefixMenuSheet({
    super.key,
    required this.config,
    required this.onExecute,
    required this.onSendPrefix,
    this.onWindowPicker,
    this.onPanePicker,
    this.onCopyMode,
  });

  final ServerConfig config;
  final void Function(String command) onExecute;
  final void Function() onSendPrefix;

  /// Picker callbacks (app-side sheets); null hides the entry.
  final void Function()? onWindowPicker;
  final void Function()? onPanePicker;
  final void Function()? onCopyMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bindings = config.prefixBindings.isEmpty
        ? fallbackPrefixActions
        : config.prefixBindings;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        child: SizedBox(
          height: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Prefix (${config.displayPrefix}) · swipe on the pane: '
                        '→ split right · ↓ split down · ↑ window · ← previous',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (onWindowPicker != null)
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.tab,
                            color: theme.colorScheme.primary),
                        title: const Text('Windows…'),
                        subtitle: const Text('Pick a window'),
                        onTap: onWindowPicker,
                      ),
                    if (onPanePicker != null)
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.grid_on,
                            color: theme.colorScheme.primary),
                        title: const Text('Panes…'),
                        subtitle: const Text('Pick a pane'),
                        onTap: onPanePicker,
                      ),
                    if (onCopyMode != null)
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.select_all,
                            color: theme.colorScheme.primary),
                        title: const Text('Copy mode'),
                        subtitle: const Text('tmux copy-mode on the pane'),
                        onTap: onCopyMode,
                      ),
                    for (final binding in bindings)
                      ListTile(
                        dense: true,
                        leading: SizedBox(
                          width: 48,
                          child: Text(
                            binding.key,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        title: Text(binding.command),
                        trailing: _hint(theme, binding.command),
                        onTap: () => onExecute(binding.command),
                      ),
                    const Divider(height: 1),
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.keyboard_return,
                          color: theme.colorScheme.primary),
                      title: const Text('Send prefix to pane (nested tmux)'),
                      subtitle: const Text('send-prefix'),
                      onTap: onSendPrefix,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _hint(ThemeData theme, String command) {
    final hint = gestureHints[command];
    if (hint == null) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Text(
        hint,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.tertiary,
        ),
      ),
    );
  }
}
