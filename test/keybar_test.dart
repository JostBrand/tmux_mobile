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

  testWidgets('Ctrl is sticky: prefixes the next key', (tester) async {
    final pressed = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Keybar(onKey: pressed.add)),
    ));

    await tester.tap(find.text('Ctrl'));
    await tester.pump();
    await tester.tap(find.text('Left'));
    await tester.pump();
    expect(pressed, ['C-Left']);

    // Modifier resets after one key.
    await tester.tap(find.text('Tab'));
    await tester.pump();
    expect(pressed, ['C-Left', 'Tab']);
  });

  testWidgets('Alt is sticky and toggles off', (tester) async {
    final pressed = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Keybar(onKey: pressed.add)),
    ));

    await tester.tap(find.text('Alt'));
    await tester.pump();
    await tester.tap(find.text('Alt'));
    await tester.pump();
    await tester.tap(find.text('Tab'));
    await tester.pump();
    expect(pressed, ['Tab']);
  });

  testWidgets('combo keys are dimmed while a modifier is active',
      (tester) async {
    final pressed = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Keybar(onKey: pressed.add)),
    ));

    await tester.tap(find.text('Ctrl'));
    await tester.pump();
    final button = tester.widget<TextButton>(
      find.ancestor(of: find.text('C-c'), matching: find.byType(TextButton)),
    );
    expect(button.onPressed, isNull);
  });
}
