import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/config/connection_profile.dart';
import 'package:tmux_mobile/src/config/profile_repository.dart';
import 'package:tmux_mobile/src/config/settings_store.dart';
import 'package:tmux_mobile/src/ui/settings_screen.dart';

void main() {
  testWidgets('settings controls update and persist', (tester) async {
    final store = InMemorySettingsStore();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        settingsStore: store,
        profiles: InMemoryProfileRepository(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Haptic feedback'));
    await tester.pump();
    expect(store.settings.hapticFeedback, isFalse);

    await tester.tap(find.text('Keep screen on'));
    await tester.pump();
    expect(store.settings.keepScreenOn, isTrue);

    await tester.tap(find.text('Export profiles'));
    await tester.pump();
    expect(find.textContaining('No profiles'), findsOneWidget);
  });

  testWidgets('export writes profiles JSON to the clipboard', (tester) async {
    final store = InMemorySettingsStore();
    final profiles = InMemoryProfileRepository([
      ConnectionProfile(
        id: 'p1',
        name: 'homelab',
        host: 'nix.local',
        username: 'user',
        sessionName: 'dev',
      ),
    ]);
    final clipboard = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        clipboard.add(call);
        return null;
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(settingsStore: store, profiles: profiles),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Export profiles'));
    await tester.pump();

    final setData =
        clipboard.where((c) => c.method == 'Clipboard.setData').toList();
    expect(setData, isNotEmpty);
    expect((setData.last.arguments as Map)['text'], contains('nix.local'));
  });

  testWidgets('import reads profiles JSON from the clipboard', (tester) async {
    final store = InMemorySettingsStore();
    final profiles = InMemoryProfileRepository();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return {
            'text':
                '[{"id":"p9","name":"imported","host":"h","port":22,'
                    '"username":"u","sessionName":"s","keySecretId":null}]',
          };
        }
        return null;
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(settingsStore: store, profiles: profiles),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Import profiles'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final loaded = await profiles.load();
    expect(loaded.single.name, 'imported');
    expect(loaded.single.id, 'p9');
  });

  test('recent profile ids are capped and deduplicated', () {
    var settings = const AppSettings();
    for (var i = 0; i < 15; i++) {
      settings = settings.withRecent('p${i % 3}');
    }
    expect(settings.recentProfileIds.length, 3);
    expect(settings.recentProfileIds.first, 'p2');
  });
}
