import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/config/connection_profile.dart';
import 'package:tmux_mobile/src/config/profile_repository.dart';

void main() {
  final profile = ConnectionProfile(
    id: 'p1',
    name: 'server',
    host: 'example.com',
    port: 2222,
    username: 'user',
    sessionName: 'dev',
  );

  test('in-memory repository saves, loads and deletes', () async {
    final repo = InMemoryProfileRepository();
    expect(await repo.load(), isEmpty);
    await repo.save(profile);
    expect((await repo.load()).single.name, 'server');
    await repo.delete('p1');
    expect(await repo.load(), isEmpty);
  });

  test('in-memory save updates an existing profile', () async {
    final repo = InMemoryProfileRepository([profile]);
    await repo.save(profile.copyWith(port: 2223));
    expect((await repo.load()).single.port, 2223);
    expect(await repo.load(), hasLength(1));
  });

  test('json file repository roundtrips', () async {
    final dir = await Directory.systemTemp.createTemp('profiles-test');
    addTearDown(() => dir.delete(recursive: true));
    final repo = JsonFileProfileRepository(File('${dir.path}/profiles.json'));

    expect(await repo.load(), isEmpty);
    await repo.save(profile);
    final loaded = await repo.load();
    expect(loaded.single.host, 'example.com');
    expect(loaded.single.port, 2222);
    await repo.delete('p1');
    expect(await repo.load(), isEmpty);
  });

  test('profile json roundtrip keeps key reference', () {
    final withKey = profile.copyWith(keySecretId: 'key-p1');
    final decoded = ConnectionProfile.decode(withKey.encode());
    expect(decoded.keySecretId, 'key-p1');
    expect(decoded.usesKeyAuth, isTrue);
    expect(profile.usesKeyAuth, isFalse);
  });
}
