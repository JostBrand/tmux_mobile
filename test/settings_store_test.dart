import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/config/settings_store.dart';

void main() {
  test('defaults', () {
    const settings = AppSettings();
    expect(settings.fontSize, 14);
    expect(settings.hapticFeedback, isTrue);
  });

  test('in-memory store roundtrips', () async {
    final store = InMemorySettingsStore();
    expect((await store.load()).fontSize, 14);
    await store.save(const AppSettings(fontSize: 18, hapticFeedback: false));
    final loaded = await store.load();
    expect(loaded.fontSize, 18);
    expect(loaded.hapticFeedback, isFalse);
  });

  test('json file store roundtrips', () async {
    final dir = await Directory.systemTemp.createTemp('settings-test');
    addTearDown(() => dir.delete(recursive: true));
    final store = JsonFileSettingsStore(File('${dir.path}/settings.json'));

    expect((await store.load()).fontSize, 14);
    await store.save(const AppSettings(fontSize: 20, hapticFeedback: false));
    final loaded = await store.load();
    expect(loaded.fontSize, 20);
    expect(loaded.hapticFeedback, isFalse);
  });

  test('json file store tolerates corrupt files', () async {
    final dir = await Directory.systemTemp.createTemp('settings-test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/settings.json');
    await file.writeAsString('not json');
    final store = JsonFileSettingsStore(file);
    expect((await store.load()).fontSize, 14);
  });
}
