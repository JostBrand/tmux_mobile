import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tmux_mobile/src/config/known_hosts.dart';
import 'package:tmux_mobile/src/config/profile_repository.dart';
import 'package:tmux_mobile/src/config/secret_store.dart';
import 'package:tmux_mobile/src/config/settings_store.dart';
import 'package:tmux_mobile/src/integration/intent_receiver.dart';
import 'package:tmux_mobile/src/integration/session_registry.dart';
import 'package:tmux_mobile/src/notifications/activity_notifier.dart';
import 'package:tmux_mobile/src/notifications/system_activity_notifier.dart';
import 'package:tmux_mobile/src/transport/session_factory.dart';
import 'package:tmux_mobile/src/ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final profiles = JsonFileProfileRepository(
      File('${supportDir.path}/profiles.json'));
  final knownHosts = JsonFileKnownHostsStore(
      File('${supportDir.path}/known_hosts.json'));
  final settings = JsonFileSettingsStore(
      File('${supportDir.path}/settings.json'));
  final notifier = SystemActivityNotifier();
  await notifier.initialize();
  final registry = SessionRegistry();
  IntentReceiver.initialize();
  for (final text in await IntentReceiver.drainPending()) {
    registry.deliverText(text);
  }
  IntentReceiver.texts.listen(registry.deliverText);
  runApp(TmuxMobileApp(
    profiles: profiles,
    knownHosts: knownHosts,
    secretStore: SecureStorageSecretStore(),
    settingsStore: settings,
    activityNotifier: notifier,
    registry: registry,
  ));
}

class TmuxMobileApp extends StatelessWidget {
  const TmuxMobileApp({
    super.key,
    required this.profiles,
    required this.knownHosts,
    required this.secretStore,
    this.settingsStore,
    this.activityNotifier,
    this.registry,
    this.sessionFactory,
  });

  final ProfileRepository profiles;
  final KnownHostsStore knownHosts;
  final SecretStore secretStore;

  /// Injectable for tests; defaults to the real SSH factory.
  final SessionFactory? sessionFactory;
  final SettingsStore? settingsStore;
  final ActivityNotifier? activityNotifier;
  final SessionRegistry? registry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tmux_mobile',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: HomeScreen(
        profiles: profiles,
        secretStore: secretStore,
        settingsStore: settingsStore,
        activityNotifier: activityNotifier,
        registry: registry ?? SessionRegistry(),
        sessionFactory:
            sessionFactory ?? SshSessionFactory(secretStore: secretStore, knownHosts: knownHosts),
      ),
    );
  }
}
