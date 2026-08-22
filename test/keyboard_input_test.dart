import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/utils/keyboard_input.dart';

void main() {
  test('batches literal text', () {
    final text = <String>[];
    translateKeyboardInput(
      'echo hello',
      onText: text.add,
      onEnter: () => fail('unexpected enter'),
      onBackspace: () => fail('unexpected backspace'),
    );
    expect(text, ['echo hello']);
  });

  test('splits on enter and backspace', () {
    final text = <String>[];
    final enters = <String>[];
    translateKeyboardInput(
      'ls\rrm foo\x7f\x7fbar\r',
      onText: text.add,
      onEnter: () => enters.add('E'),
      onBackspace: () => text.add('<BS>'),
    );
    expect(enters, ['E', 'E']);
    expect(text, ['ls', 'rm foo', '<BS>', '<BS>', 'bar']);
  });
}
