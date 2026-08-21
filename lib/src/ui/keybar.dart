import 'package:flutter/material.dart';

/// On-screen keybar sending tmux key names via `send-keys`.
///
/// Ctrl/Alt are STICKY modifiers: tap once, then the next key is sent
/// with the tmux `C-`/`M-` prefix (C-Left, M-Tab, ...). Combo keys
/// (C-c/C-d/C-l) are dimmed while a modifier is active.
class Keybar extends StatefulWidget {
  const Keybar({super.key, required this.onKey});

  final void Function(String tmuxKeyName) onKey;

  @override
  State<Keybar> createState() => _KeybarState();
}

class _KeybarState extends State<Keybar> {
  String? _modifier;

  void _press(String key) {
    if (key == 'Ctrl' || key == 'Alt') {
      setState(() {
        final prefix = key == 'Ctrl' ? 'C-' : 'M-';
        _modifier = _modifier == prefix ? null : prefix;
      });
      return;
    }
    widget.onKey('${_modifier ?? ''}$key');
    setState(() => _modifier = null);
  }

  bool get _comboActive => _modifier == null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(['Ctrl', 'Alt', 'Escape', 'Tab', 'C-c', 'C-d', 'C-l'], theme),
          _row(['PageUp', 'PageDown', 'Left', 'Up', 'Down', 'Right'], theme),
          _row(['Enter', 'BSpace'], theme),
        ],
      ),
    );
  }

  Widget _row(List<String> keys, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final key in keys)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _keyButton(key, theme),
          ),
      ],
    );
  }

  Widget _keyButton(String key, ThemeData theme) {
    final isModifier = key == 'Ctrl' || key == 'Alt';
    final active = isModifier && _modifier == (key == 'Ctrl' ? 'C-' : 'M-');
    final dimmed = !isModifier && !_comboActive && key.startsWith('C-');
    return TextButton(
      onPressed: dimmed ? null : () => _press(key),
      style: TextButton.styleFrom(
        minimumSize: const Size(40, 38),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        backgroundColor: active
            ? theme.colorScheme.primaryContainer
            : null,
        foregroundColor: active
            ? theme.colorScheme.onPrimaryContainer
            : null,
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(key),
    );
  }
}
