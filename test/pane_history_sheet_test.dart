import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/ui/pane_history_sheet.dart';

void main() {
  List<String> page(int depth) => [
        for (var i = 1; i <= depth; i++) 'line-${(i + 1000).toString()}',
      ];

  Future<void> pumpSheet(
    WidgetTester tester, {
    required Future<List<String>> Function(int) fetchOlder,
    void Function(String)? onCopy,
    void Function(String)? onShare,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => PaneHistorySheet(
                  paneId: '%0',
                  fetchOlder: fetchOlder,
                  onCopy: onCopy,
                  onShare: onShare,
                  pageSize: 10,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('loads the first page and shows the newest line at the bottom',
      (tester) async {
    await pumpSheet(tester, fetchOlder: (depth) async => page(depth));

    // Reverse list: newest line is index 0, rendered at the bottom.
    expect(find.text('line-1010'), findsOneWidget);
  });

  testWidgets('loads older pages with overlap dedup', (tester) async {
    var calls = 0;
    await pumpSheet(tester, fetchOlder: (depth) async {
      calls++;
      return [
        for (var i = depth * 2; i > 0; i--) 'line-${i.toString().padLeft(4, '0')}',
      ];
    });

    // The footer sits at the oldest end - scroll toward it, then trigger
    // load-older via the button, a few times.
    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pump();
      await tester.tap(find.text('Load older'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(calls, greaterThan(1));
    // No duplicates: the sheet contains each line exactly once.
    final texts = find.byType(Text).evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .toList();
    expect(texts.length, texts.toSet().length);
  });

  testWidgets('search filters the loaded lines', (tester) async {
    await pumpSheet(tester, fetchOlder: (depth) async => [
          'error: something broke',
          'build finished',
          'another line',
        ]);

    await tester.enterText(find.byType(TextField), 'build');
    await tester.pump();
    expect(find.text('build finished'), findsOneWidget);
    expect(find.text('error: something broke'), findsNothing);
  });

  testWidgets('long-pressing a line shares it', (tester) async {
    final shared = <String>[];
    await pumpSheet(tester,
        fetchOlder: (depth) async => page(depth), onShare: shared.add);

    await tester.longPress(find.text('line-1010'));
    await tester.pump();
    expect(shared, ['line-1010']);
  });

  testWidgets('tapping a line copies it', (tester) async {
    final copied = <String>[];
    await pumpSheet(tester,
        fetchOlder: (depth) async => page(depth), onCopy: copied.add);

    await tester.tap(find.text('line-1010'));
    await tester.pump();
    expect(copied, ['line-1010']);
  });
}
