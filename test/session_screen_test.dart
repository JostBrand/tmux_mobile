import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/ui/session_screen.dart';

/// Widget tests for the session screen with a loopback fake client.
///
/// NOTE: the StreamController and client are created INSIDE the test body
/// (not in setUp) - setUp runs in the real zone while the testWidgets body
/// runs under FakeAsync, and events delivered through cross-zone
/// microtasks never get flushed by tester.pump().
void main() {
  late StreamController<List<int>> input;
  late ControlModeClient client;
  late List<String> commands;

  Future<void> pumpScreen(WidgetTester tester) async {
    input = StreamController<List<int>>.broadcast();
    commands = <String>[];
    input.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(commands.add);
    client = ControlModeClient(input: input.stream, output: input.sink);
    addTearDown(() async {
      client.dispose();
      await input.close();
    });
    await tester
        .pumpWidget(MaterialApp(home: SessionScreen(client: client)));
    await tester.pump();
    // Let the resize debounce of the pane feeder settle.
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('swipe left selects the next known pane', (tester) async {
    await pumpScreen(tester);
    // A second pane becomes known once it emits output.
    input.add(utf8.encode('%output %1 echo-from-pane-one\n'));
    await tester.pump();

    await tester.fling(
        find.byKey(const Key('pane-swipe-area')), const Offset(-250, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(commands, contains('select-pane -t %1'));
  });

  testWidgets('keybar sends keys to the currently displayed pane',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Escape'));
    await tester.pump();
    expect(commands, contains("send-keys -t %0 -- 'Escape'"));

    input.add(utf8.encode('%output %1 echo\n'));
    await tester.pump();
    await tester.fling(
        find.byKey(const Key('pane-swipe-area')), const Offset(-250, 0), 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Tab'));
    await tester.pump();
    expect(commands, contains("send-keys -t %1 -- 'Tab'"));
  });

  testWidgets('history button fetches scrollback for the current pane',
      (tester) async {
    await pumpScreen(tester);

    // Drain all commands pending from setup (pane seed + resize refreshes)
    // so the sheet's fetch is the only pending command afterwards.
    final pending = commands
        .where((c) =>
            c.startsWith('capture-pane') || c.startsWith('refresh-client'))
        .length;
    for (var i = 0; i < pending; i++) {
      input.add(utf8.encode('%begin 1 1\nfiller\n%end 1 1\n'));
    }
    await tester.pump();

    await tester.tap(find.byIcon(Icons.manage_search));
    await tester.pump();
    await tester.pump();

    input.add(
        utf8.encode('%begin 1 1\nold-line-1\nold-line-2\n%end 1 1\n'));
    await tester.pumpAndSettle();

    expect(find.text('History - %0'), findsOneWidget);
    expect(find.text('old-line-2'), findsOneWidget);
    expect(commands, contains('capture-pane -p -e -t %0 -S -200'));
  });

  testWidgets('renders a terminal and the keybar', (tester) async {
    await pumpScreen(tester);
    expect(find.byType(SessionScreen), findsOneWidget);
    expect(find.text('Escape'), findsOneWidget);
    expect(find.text('Enter'), findsOneWidget);
  });

  testWidgets('prefix button shows the server bindings and executes them',
      (tester) async {
    await pumpScreen(tester);

    // Drain commands pending from setup (seed + resize refreshes).
    final pending = commands
        .where((c) =>
            c.startsWith('capture-pane') || c.startsWith('refresh-client'))
        .length;
    for (var i = 0; i < pending; i++) {
      input.add(utf8.encode('%begin 1 1\nfiller\n%end 1 1\n'));
    }
    await tester.pump();

    // Attach triggers the one-shot introspection + hygiene commands.
    input.add(utf8.encode('%session-changed \$1 spike\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\nprefix C-b\n%end 1 1\n')); // 1
    await tester.pump();
    input.add(utf8.encode(
        '%begin 1 1\nbind-key -T prefix c new-window\n'
        'bind-key -T prefix n next-window\n%end 1 1\n')); // 2
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n')); // 3 set-option
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n120x30\n%end 1 1\n')); // 4 size
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n')); // 5 refresh
    await tester.pump();
    // 6th introspection command: list-panes (nested-tmux detection).
    input.add(utf8.encode('%begin 1 1\n%0:bash\n%end 1 1\n'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(commands, contains("set-option -t 'spike' detach-on-destroy off"));

    // The prefix button is labeled with the server's real prefix.
    await tester.tap(find.widgetWithText(FilledButton, 'C-b'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Prefix (C-b)'), findsOneWidget);

    // The app entries push the bindings down - scroll the sheet list.
    await tester.drag(find.byType(ListView).last, const Offset(0, -250));
    await tester.pump();
    await tester.tap(find.text('new-window'));
    await tester.pumpAndSettle();
    expect(commands, contains('new-window'));

    // Send-prefix entry forwards the prefix to the pane (it sits at the
    // bottom of the sheet - scroll the sheet list first).
    await tester.tap(find.widgetWithText(FilledButton, 'C-b'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(ListView).last, const Offset(0, -400));
    await tester.pump();
    await tester.tap(find.textContaining('nested tmux'));
    await tester.pump();
    expect(commands, contains('send-prefix -t %0'));
  });

  Future<void> openModMode(WidgetTester tester) async {
    await pumpScreen(tester);
    // Drain setup commands.
    final pending = commands
        .where((c) =>
            c.startsWith('capture-pane') || c.startsWith('refresh-client'))
        .length;
    for (var i = 0; i < pending; i++) {
      input.add(utf8.encode('%begin 1 1\nfiller\n%end 1 1\n'));
    }
    await tester.pump();
    // Introspection so the prefix button is enabled.
    input.add(utf8.encode('%session-changed \$1 spike\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\nprefix C-b\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode(
        '%begin 1 1\nbind-key -T prefix c new-window\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n80x24\n%end 1 1\n'));
    await tester.pump();
    input.add(utf8.encode('%begin 1 1\n%end 1 1\n'));
    await tester.pump();
    // 6th introspection command: list-panes (nested-tmux detection).
    input.add(utf8.encode('%begin 1 1\n%0:bash\n%end 1 1\n'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Enter mod mode (opens the menu sheet).
    await tester.tap(find.widgetWithText(FilledButton, 'C-b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> flingPanes(WidgetTester tester, Offset offset) async {
    // Fling in the UPPER part of the pane area: with the prefix sheet
    // open, the center is covered by the modal barrier.
    final origin = tester
            .getTopLeft(find.byKey(const Key('pane-swipe-area'))) +
        const Offset(100, 60);
    await tester.flingFrom(origin, offset, 900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('mod mode: swipe right splits horizontally', (tester) async {
    await openModMode(tester);
    await flingPanes(tester, const Offset(250, 0));
    expect(commands, contains('split-window -h'));
  });

  testWidgets('mod mode: swipe down splits vertically', (tester) async {
    await openModMode(tester);
    await flingPanes(tester, const Offset(0, 250));
    expect(commands, contains('split-window -v'));
  });

  testWidgets('mod mode: swipe up opens a new window', (tester) async {
    await openModMode(tester);
    await flingPanes(tester, const Offset(0, -250));
    expect(commands, contains('new-window'));
  });

  testWidgets('mod mode: swipe left goes to the previous window',
      (tester) async {
    await openModMode(tester);
    await flingPanes(tester, const Offset(-250, 0));
    expect(commands, contains('previous-window'));
  });

  testWidgets('mod mode: two-finger swipe right breaks the pane',
      (tester) async {
    await openModMode(tester);
    final center = tester.getTopLeft(
            find.byKey(const Key('pane-swipe-area'))) +
        const Offset(100, 60);
    final g1 = await tester.startGesture(center);
    final g2 =
        await tester.startGesture(center + const Offset(0, 120));
    for (var i = 0; i < 3; i++) {
      await g1.moveBy(const Offset(60, 0));
      await g2.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(commands, contains('break-pane'));
  });

  testWidgets('mod mode locks the terminal and times out',
      (tester) async {
    await openModMode(tester);
    AbsorbPointer paneAbsorber() => tester.widget<AbsorbPointer>(
          find.descendant(
            of: find.byKey(const Key('pane-swipe-area')),
            matching: find.byType(AbsorbPointer),
          ),
        );
    expect(paneAbsorber().absorbing, isTrue);
    // After the 2.5s timeout the terminal is interactive again.
    await tester.pump(const Duration(milliseconds: 2600));
    expect(paneAbsorber().absorbing, isFalse);
  });
}
