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

/// The mobile replacement for the tmux prefix key: a bottom sheet
/// listing the server's REAL prefix bindings (labels from `list-keys`),
/// each executing its tmux command directly. A "send prefix to pane"
/// entry supports nested tmux (`send-prefix`).
class PrefixMenuSheet extends StatelessWidget {
  const PrefixMenuSheet({
    super.key,
    required this.config,
    required this.onExecute,
    required this.onSendPrefix,
  });

  final ServerConfig config;
  final void Function(String command) onExecute;
  final void Function() onSendPrefix;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Prefix menu (${config.displayPrefix})',
                      style: theme.textTheme.titleMedium,
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
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
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
                      onTap: () {
                        Navigator.of(context).pop();
                        onExecute(binding.command);
                      },
                    ),
                  const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.keyboard_return,
                        color: theme.colorScheme.primary),
                    title: const Text('Send prefix to pane (nested tmux)'),
                    subtitle: const Text('send-prefix'),
                    onTap: () {
                      Navigator.of(context).pop();
                      onSendPrefix();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
