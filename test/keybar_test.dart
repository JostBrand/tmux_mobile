import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/ui/keybar.dart';

void main() {
  testWidgets('emits tmux key names on tap', (tester) async {
    final pressed = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Keybar(onKey: pressed.add)),
    ));

    for (final key in ['Escape', 'Tab', 'C-c', 'PageUp', 'Enter', 'BSpace']) {
      await tester.tap(find.text(key));
      await tester.pump();
    }
    expect(pressed, ['Escape', 'Tab', 'C-c', 'PageUp', 'Enter', 'BSpace']);
  });
}
