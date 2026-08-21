import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/main.dart';

void main() {
  testWidgets('home screen renders title and keybar preview',
      (tester) async {
    await tester.pumpWidget(const TmuxMobileApp());
    expect(find.text('tmux_mobile'), findsOneWidget);
    expect(find.text('Escape'), findsOneWidget);
  });
}
