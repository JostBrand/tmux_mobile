/// tmux key binding as reported by `list-keys`.
class KeyBinding {
  const KeyBinding({
    required this.table,
    required this.key,
    required this.command,
  });

  final String table;
  final String key;
  final String command;
}

/// Parses `tmux list-keys` output.
///
/// Format (tab or space separated):
///   bind-key    -T prefix C-a    send-prefix
///   bind-key -r -T root   C-l    send-keys -l
///   bind-key    -T copy-mode-vi v    send-keys -X begin-selection
List<KeyBinding> parseListKeys(String output) {
  final bindings = <KeyBinding>[];
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    final parts = line.split(RegExp(r'\s+'));
    if (parts.first != 'bind-key') {
      continue;
    }
    var i = 1;
    if (i < parts.length && parts[i] == '-r') {
      i++;
    }
    var table = 'root';
    if (i + 1 < parts.length && parts[i] == '-T') {
      table = parts[i + 1];
      i += 2;
    }
    if (i >= parts.length) {
      continue;
    }
    bindings.add(KeyBinding(
      table: table,
      key: parts[i],
      command: parts.skip(i + 1).join(' '),
    ));
  }
  return bindings;
}

/// Parses `tmux show-options -g prefix` output into the prefix key
/// (e.g. `prefix C-b` -> `C-b`; `prefix2 C-a` lines yield the second
/// prefix when present).
String? parsePrefix(String showOptionsOutput) {
  String? prefix;
  for (final rawLine in showOptionsOutput.split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith('prefix ')) {
      final value = line.substring('prefix '.length).trim();
      if (value.isNotEmpty) {
        prefix = value;
      }
    } else if (line.startsWith('prefix2 ')) {
      final value = line.substring('prefix2 '.length).trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
  }
  return prefix;
}

/// Everything the app needs from the server's keybinding config.
class ServerConfig {
  const ServerConfig({required this.prefix, required this.bindings});

  final String? prefix;
  final List<KeyBinding> bindings;

  List<KeyBinding> get prefixBindings => [
        for (final binding in bindings)
          if (binding.table == 'prefix') binding,
      ];

  String get displayPrefix => prefix ?? 'prefix';
}
