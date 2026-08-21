import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tmux_mobile/src/config/known_hosts.dart';
import 'package:tmux_mobile/src/config/profile_repository.dart';
import 'package:tmux_mobile/src/config/secret_store.dart';
import 'package:tmux_mobile/src/transport/session_factory.dart';
import 'package:tmux_mobile/src/ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final profiles = JsonFileProfileRepository(
      File('${supportDir.path}/profiles.json'));
  final knownHosts = JsonFileKnownHostsStore(
      File('${supportDir.path}/known_hosts.json'));
  runApp(TmuxMobileApp(
    profiles: profiles,
    knownHosts: knownHosts,
    secretStore: SecureStorageSecretStore(),
  ));
}

class TmuxMobileApp extends StatelessWidget {
  const TmuxMobileApp({
    super.key,
    required this.profiles,
    required this.knownHosts,
    required this.secretStore,
    this.sessionFactory,
  });

  final ProfileRepository profiles;
  final KnownHostsStore knownHosts;
  final SecretStore secretStore;

  /// Injectable for tests; defaults to the real SSH factory.
  final SessionFactory? sessionFactory;

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
        sessionFactory:
            sessionFactory ?? SshSessionFactory(secretStore: secretStore, knownHosts: knownHosts),
      ),
    );
  }
}
