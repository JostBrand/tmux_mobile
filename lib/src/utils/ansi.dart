/// Strips CSI/OSC escape sequences from capture-pane output for display
/// in the history sheet (the live terminal renders them; plain history
/// text should be readable).
final RegExp ansiPattern = RegExp(r'\x1B\[[0-9;?]*[a-zA-Z]|\x1B\][^\x07]*(?:\x07|\x1B\\)');

String stripAnsi(String input) => input.replaceAll(ansiPattern, '');
