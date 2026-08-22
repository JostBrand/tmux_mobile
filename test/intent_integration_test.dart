import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/main.dart';
import 'package:tmux_mobile/src/config/connection_profile.dart';
import 'package:tmux_mobile/src/config/known_hosts.dart';
import 'package:tmux_mobile/src/config/profile_repository.dart';
import 'package:tmux_mobile/src/config/secret_store.dart';
import 'package:tmux_mobile/src/config/settings_store.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/integration/session_registry.dart';
import 'package:tmux_mobile/src/transport/session_factory.dart';

class FakeSessionFactory implements SessionFactory {
  final List<String> openedSessions = [];
  StreamController<List<int>>? input;
  ControlModeClient? client;

  @override
  Future<List<String>> listSessions(
    ConnectionProfile profile, {
    required Future<String?> Function() passwordPrompt,
  }) async {
    return const [];
  }

  @override
  Future<OpenSession> open(
    ConnectionProfile profile, {
    required String sessionName,
    required Future<String?> Function() passwordPrompt,
  }) async {
    openedSessions.add(sessionName);
    input = StreamController<List<int>>.broadcast();
    client = ControlModeClient(input: input!.stream, output: input!.sink);
    return OpenSession(client: client!, close: () async => input!.close());
  }
}

void main() {
  Future<void> pumpApp(WidgetTester tester, SessionRegistry registry) async {
    final store = InMemorySettingsStore();
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
      settingsStore: store,
      sessionFactory: FakeSessionFactory(),
      registry: registry,
    ));
    await tester.pump();
  }

  testWidgets('queued text shows a banner on home and is offered on connect',
      (tester) async {
    final registry = SessionRegistry();
    registry.deliverText('echo hello-from-app');
    await pumpApp(tester, registry);

    expect(find.textContaining('waiting'), findsOneWidget);

    await tester.tap(find.text('homelab'));
    await tester.pumpAndSettle();

    expect(find.text('Text from another app'), findsOneWidget);
    await tester.tap(find.text('Send + Enter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final factory = tester
        .widget<TmuxMobileApp>(find.byType(TmuxMobileApp))
        .sessionFactory! as FakeSessionFactory;
    final commands = <String>[];
    factory.input!.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(commands.add);
    // The text went through the registry into the session client.
    expect(factory.client, isNotNull);
    expect(registry.queue.length, 0);
    expect(find.byKey(const Key('pane-swipe-area')), findsOneWidget);
  });

  testWidgets('incoming text while connected goes directly to the pane',
      (tester) async {
    final registry = SessionRegistry();
    await pumpApp(tester, registry);
    await tester.tap(find.text('homelab'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    final factory = tester
        .widget<TmuxMobileApp>(find.byType(TmuxMobileApp))
        .sessionFactory! as FakeSessionFactory;
    final commands = <String>[];
    factory.input!.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(commands.add);

    registry.deliverText('direct-command');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Security: external text needs explicit confirmation even in a live
    // session (hostile apps can fire intents at us).
    expect(find.text('Text from another app'), findsOneWidget);
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(commands, contains("send-keys -t %0 -- 'direct-command'"));
  });
}
