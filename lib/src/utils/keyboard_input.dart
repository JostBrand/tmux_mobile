/// Translates xterm onOutput data (soft keyboard) into pane input
/// actions: Enter/Backspace become tmux key names, everything else is
/// batched literal text for `send-keys`.
void translateKeyboardInput(
  String data, {
  required void Function(String text) onText,
  required void Function() onEnter,
  required void Function() onBackspace,
}) {
  final buffer = StringBuffer();
  void flush() {
    if (buffer.isNotEmpty) {
      onText(buffer.toString());
      buffer.clear();
    }
  }

  for (final rune in data.runes) {
    final char = String.fromCharCode(rune);
    if (char == '\r' || char == '\n') {
      flush();
      onEnter();
    } else if (char == '\x7f' || char == '\b') {
      flush();
      onBackspace();
    } else {
      buffer.write(char);
    }
  }
  flush();
}
