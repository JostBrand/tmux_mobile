import 'package:flutter/material.dart';

/// On-screen keybar sending tmux key names via `send-keys`, plus app-side
/// Paste/Copy actions.
///
/// Ctrl/Alt are STICKY modifiers: tap once, then the next key is sent
/// with the tmux `C-`/`M-` prefix. Combo keys (C-c/C-d/...) are dimmed
/// while a modifier is active. Rows scroll horizontally on narrow
/// screens.
class Keybar extends StatefulWidget {
  const Keybar({
    super.key,
    required this.onKey,
    this.onPaste,
    this.onCopy,
    this.innerPrefixKey,
    this.onInnerPrefix,
  });

  final void Function(String tmuxKeyName) onKey;
  final void Function()? onPaste;
  final void Function()? onCopy;

  /// Label + callback for the NESTED-tmux prefix key (phone keyboards
  /// cannot type control combos like C-b).
  final String? innerPrefixKey;
  final void Function()? onInnerPrefix;

  @override
  State<Keybar> createState() => _KeybarState();
}

class _KeybarState extends State<Keybar> {
  String? _modifier;

  static const _rowNavigation = [
    'Ctrl',
    'Alt',
    'Escape',
    'Tab',
    'Home',
    'End',
    'PageUp',
    'PageDown',
    'Left',
    'Up',
    'Down',
    'Right',
    'Enter',
    'BSpace',
  ];

  static const _rowCombos = [
    'C-a',
    'C-e',
    'C-u',
    'C-w',
    'C-r',
    'C-k',
    'C-n',
    'C-p',
    'C-x',
    'C-y',
    'C-c',
    'C-d',
    'C-l',
  ];

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
          _scrollableRow(_rowNavigation, theme),
          _scrollableRow(
            [
              if (widget.innerPrefixKey != null) widget.innerPrefixKey!,
              if (widget.onPaste != null) 'Paste',
              if (widget.onCopy != null) 'Copy',
              ..._rowCombos,
            ],
            theme,
          ),
        ],
      ),
    );
  }

  Widget _scrollableRow(List<String> keys, ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final key in keys)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _keyButton(key, theme),
            ),
        ],
      ),
    );
  }

  Widget _keyButton(String key, ThemeData theme) {
    if (key == widget.innerPrefixKey) {
      return TextButton(
        onPressed: widget.onInnerPrefix,
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: theme.colorScheme.tertiaryContainer,
          foregroundColor: theme.colorScheme.onTertiaryContainer,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Text(key),
      );
    }
    if (key == 'Paste' || key == 'Copy') {
      return TextButton.icon(
        onPressed: key == 'Paste' ? widget.onPaste : widget.onCopy,
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        icon: Icon(
          key == 'Paste' ? Icons.content_paste : Icons.content_copy,
          size: 16,
        ),
        label: Text(key),
      );
    }
    final isModifier = key == 'Ctrl' || key == 'Alt';
    final active = isModifier && _modifier == (key == 'Ctrl' ? 'C-' : 'M-');
    final dimmed = !isModifier && !_comboActive && key.startsWith('C-');
    return TextButton(
      onPressed: dimmed ? null : () => _press(key),
      style: TextButton.styleFrom(
        minimumSize: const Size(40, 38),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        backgroundColor: active ? theme.colorScheme.primaryContainer : null,
        foregroundColor: active ? theme.colorScheme.onPrimaryContainer : null,
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(key),
    );
  }
}
