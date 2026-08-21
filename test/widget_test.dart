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
  FakeSessionFactory({this.sessions = const []});

  final List<String> sessions;
  final List<ConnectionProfile> opened = [];
  final List<String> openedSessions = [];

  @override
  Future<List<String>> listSessions(
    ConnectionProfile profile, {
    required Future<String?> Function() passwordPrompt,
  }) async {
    return sessions;
  }

  @override
  Future<OpenSession> open(
    ConnectionProfile profile, {
    required String sessionName,
    required Future<String?> Function() passwordPrompt,
  }) async {
    opened.add(profile);
    openedSessions.add(sessionName);
    final controller = StreamController<List<int>>.broadcast();
    final client =
        ControlModeClient(input: controller.stream, output: controller.sink);
    return OpenSession(client: client, close: () async => controller.close());
  }
}

ConnectionProfile keyProfile({String sessionName = ''}) => ConnectionProfile(
      id: 'p1',
      name: 'homelab',
      host: 'nix.local',
      username: 'user',
      sessionName: sessionName,
      keySecretId: 'key-p1',
    );

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
      profiles: InMemoryProfileRepository([keyProfile()]),
      knownHosts: InMemoryKnownHostsStore(),
      secretStore: InMemorySecretStore(),
      sessionFactory: FakeSessionFactory(),
    ));
    await tester.pump();
    expect(find.text('homelab'), findsOneWidget);
    expect(find.textContaining('user@nix.local'), findsOneWidget);
  });

  testWidgets('configured session name attaches directly', (tester) async {
    final factory = FakeSessionFactory();
    await tester.pumpWidget(TmuxMobileApp(
      profiles: InMemoryProfileRepository([keyProfile(sessionName: 'dev')]),
      knownHosts: InMemoryKnownHostsStore(),
      secretStore: InMemorySecretStore(),
      sessionFactory: factory,
    ));
    await tester.pump();
    await tester.tap(find.text('homelab'));
    await tester.pumpAndSettle();

    expect(factory.openedSessions, ['dev']);
    expect(factory.opened, hasLength(1));
    expect(find.byKey(const Key('pane-swipe-area')), findsOneWidget);
  });

  testWidgets('empty session name + single remote session uses it directly',
      (tester) async {
    final factory = FakeSessionFactory(sessions: ['main']);
    await tester.pumpWidget(TmuxMobileApp(
      profiles: InMemoryProfileRepository([keyProfile()]),
      knownHosts: InMemoryKnownHostsStore(),
      secretStore: InMemorySecretStore(),
      sessionFactory: factory,
    ));
    await tester.pump();
    await tester.tap(find.text('homelab'));
    await tester.pumpAndSettle();

    expect(factory.openedSessions, ['main']);
    expect(find.byKey(const Key('pane-swipe-area')), findsOneWidget);
  });

  testWidgets('multiple remote sessions show a picker', (tester) async {
    final factory = FakeSessionFactory(sessions: ['dev', 'main']);
    await tester.pumpWidget(TmuxMobileApp(
      profiles: InMemoryProfileRepository([keyProfile()]),
      knownHosts: InMemoryKnownHostsStore(),
      secretStore: InMemorySecretStore(),
      sessionFactory: factory,
    ));
    await tester.pump();
    await tester.tap(find.text('homelab'));
    await tester.pumpAndSettle();

    expect(find.text('Select tmux session'), findsOneWidget);
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();

    expect(factory.openedSessions, ['main']);
    expect(find.byKey(const Key('pane-swipe-area')), findsOneWidget);
  });

  testWidgets('no remote session offers to create one', (tester) async {
    final factory = FakeSessionFactory(sessions: []);
    await tester.pumpWidget(TmuxMobileApp(
      profiles: InMemoryProfileRepository([keyProfile()]),
      knownHosts: InMemoryKnownHostsStore(),
      secretStore: InMemorySecretStore(),
      sessionFactory: factory,
    ));
    await tester.pump();
    await tester.tap(find.text('homelab'));
    await tester.pumpAndSettle();

    expect(find.text('New tmux session'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'work');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(factory.openedSessions, ['work']);
    expect(find.byKey(const Key('pane-swipe-area')), findsOneWidget);
  });
}
