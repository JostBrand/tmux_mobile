import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/main.dart';
import 'package:tmux_mobile/src/config/connection_profile.dart';
import 'package:tmux_mobile/src/config/known_hosts.dart';
import 'package:tmux_mobile/src/config/profile_repository.dart';
import 'package:tmux_mobile/src/config/secret_store.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/transport/session_factory.dart';

class FakeSessionFactory implements SessionFactory {
  final List<ConnectionProfile> opened = [];

  @override
  Future<OpenSession> open(
    ConnectionProfile profile, {
    required Future<String?> Function() passwordPrompt,
  }) async {
    opened.add(profile);
    final controller = StreamController<List<int>>.broadcast();
    final client =
        ControlModeClient(input: controller.stream, output: controller.sink);
    return OpenSession(client: client, close: () async => controller.close());
  }
}

void main() {
  testWidgets('empty state renders with no profiles', (tester) async {
    await tester.pumpWidget(TmuxMobileApp(
      profiles: InMemoryProfileRepository(),
      knownHosts: InMemoryKnownHostsStore(),
      secretStore: InMemorySecretStore(),
      sessionFactory: FakeSessionFactory(),
    ));
    await tester.pump();
    expect(find.text('tmux_mobile'), findsOneWidget);
    expect(find.textContaining('No connections yet'), findsOneWidget);
  });

  testWidgets('profile list shows saved profiles', (tester) async {
    await tester.pumpWidget(TmuxMobileApp(
      profiles: InMemoryProfileRepository([
        ConnectionProfile(
          id: 'p1',
          name: 'homelab',
          host: 'nix.local',
          username: 'user',
          sessionName: 'dev',
        ),
      ]),
      knownHosts: InMemoryKnownHostsStore(),
      secretStore: InMemorySecretStore(),
      sessionFactory: FakeSessionFactory(),
    ));
    await tester.pump();
    expect(find.text('homelab'), findsOneWidget);
    expect(find.textContaining('user@nix.local'), findsOneWidget);
  });

  testWidgets('key-auth profile connects directly into the session screen',
      (tester) async {
    final factory = FakeSessionFactory();
    await tester.pumpWidget(TmuxMobileApp(
      profiles: InMemoryProfileRepository([
        ConnectionProfile(
          id: 'p1',
          name: 'homelab',
          host: 'nix.local',
          username: 'user',
          sessionName: 'dev',
          keySecretId: 'key-p1',
        ),
      ]),
      knownHosts: InMemoryKnownHostsStore(),
      secretStore: InMemorySecretStore(),
      sessionFactory: factory,
    ));
    await tester.pump();
    await tester.tap(find.text('homelab'));
    await tester.pumpAndSettle();

    expect(factory.opened, hasLength(1));
    expect(find.byKey(const Key('pane-swipe-area')), findsOneWidget);
  });
}
