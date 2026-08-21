import 'package:flutter/material.dart';

/// Minimal on-screen keybar sending tmux key names via `send-keys`.
///
/// M2 scope: the raw keys a phone cannot type. Sticky modifiers
/// (Ctrl/Alt combos), macros and per-app layouts come with the M3
/// design pass.
class Keybar extends StatelessWidget {
  const Keybar({super.key, required this.onKey});

  final void Function(String tmuxKeyName) onKey;

  static const _rows = [
    ['Escape', 'Tab', 'C-c', 'C-d', 'C-l', 'PageUp', 'PageDown'],
    ['Left', 'Up', 'Down', 'Right', 'Enter', 'BSpace'],
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in _rows)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final key in row)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: TextButton(
                      onPressed: () => onKey(key),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      child: Text(key),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
