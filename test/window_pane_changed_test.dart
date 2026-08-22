import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';

void main() {
  testWidgets('window-pane-changed reports the new active pane',
      (tester) async {
    final input = StreamController<List<int>>.broadcast();
    final client = ControlModeClient(input: input.stream, output: input.sink);
    final got = <String>[];
    client.windowPaneChanged.listen(got.add);
    input.add(utf8.encode('%window-pane-changed @0 %1\n'));
    await tester.pump();
    expect(got, ['%1']);
    client.dispose();
    await input.close();
  });
}
