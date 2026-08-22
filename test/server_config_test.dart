import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/config/server_config.dart';

void main() {
  test('parses list-keys output', () {
    const output = '''
bind-key    -T prefix C-a        send-prefix
bind-key    -T prefix c          new-window
bind-key -r -T root   C-l        send-keys -l
bind-key    -T prefix "          split-window -h
bind-key    -T copy-mode-vi v    send-keys -X begin-selection
''';
    final bindings = parseListKeys(output);
    expect(bindings, hasLength(5));

    final prefix = bindings.where((b) => b.table == 'prefix').toList();
    expect(prefix, hasLength(3));
    expect(prefix[0].key, 'C-a');
    expect(prefix[0].command, 'send-prefix');
    expect(prefix[1].key, 'c');
    expect(prefix[2].command, 'split-window -h');

    final repeatable = bindings.firstWhere((b) => b.key == 'C-l');
    expect(repeatable.table, 'root');
    expect(repeatable.command, 'send-keys -l');
  });

  test('parses prefix and prefix2 from show-options', () {
    expect(parsePrefix('prefix C-b\n'), 'C-b');
    expect(parsePrefix('prefix C-b\nprefix2 C-a\n'), 'C-a');
    expect(parsePrefix(''), isNull);
  });

  test('server config exposes prefix bindings and display prefix', () {
    final config = ServerConfig(
      prefix: 'C-b',
      bindings: parseListKeys(
          'bind-key -T prefix c new-window\nbind-key -T root x kill-pane\n'),
    );
    expect(config.displayPrefix, 'C-b');
    expect(config.prefixBindings.single.command, 'new-window');
  });
}
