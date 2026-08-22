import 'package:flutter/material.dart';
import 'package:tmux_mobile/src/config/connection_profile.dart';
import 'package:tmux_mobile/src/config/profile_repository.dart';
import 'package:tmux_mobile/src/config/secret_store.dart';
import 'package:tmux_mobile/src/config/settings_store.dart';
import 'package:tmux_mobile/src/transport/session_factory.dart';
import 'package:tmux_mobile/src/ui/connect_screen.dart';
import 'package:tmux_mobile/src/ui/profile_edit_screen.dart';

/// Landing screen: saved connection profiles.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.profiles,
    required this.secretStore,
    required this.sessionFactory,
    this.settingsStore,
  });

  final ProfileRepository profiles;
  final SecretStore secretStore;
  final SessionFactory sessionFactory;
  final SettingsStore? settingsStore;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<ConnectionProfile>> _profilesFuture;

  @override
  void initState() {
    super.initState();
    _profilesFuture = widget.profiles.load();
  }

  void _reload() {
    setState(() {
      _profilesFuture = widget.profiles.load();
    });
  }

  Future<void> _openProfile(ConnectionProfile profile) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConnectScreen(
          profile: profile,
          secretStore: widget.secretStore,
          sessionFactory: widget.sessionFactory,
          settingsStore: widget.settingsStore,
        ),
      ),
    );
    _reload();
  }

  Future<void> _createProfile() async {
    final created = await Navigator.of(context).push<ConnectionProfile>(
      MaterialPageRoute<ConnectionProfile>(
        builder: (_) => ProfileEditScreen(
          secretStore: widget.secretStore,
          onSave: (profile) => widget.profiles.save(profile),
        ),
      ),
    );
    if (created != null) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('tmux_mobile')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProfile,
        icon: const Icon(Icons.add),
        label: const Text('Add host'),
      ),
      body: FutureBuilder<List<ConnectionProfile>>(
        future: _profilesFuture,
        builder: (context, snapshot) {
          final profiles = snapshot.data ?? const <ConnectionProfile>[];
          if (profiles.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.terminal,
                        size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'No connections yet.\nAdd the host running your tmux server.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: profiles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final profile = profiles[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  title: Text(profile.name),
                  subtitle: Text(
                    '${profile.username}@${profile.host}:${profile.port}'
                    ' · ${profile.sessionName}'
                    '${profile.usesKeyAuth ? ' · key' : ''}',
                  ),
                  leading: Icon(
                    profile.usesKeyAuth ? Icons.key : Icons.lock_outline,
                  ),
                  onTap: () => _openProfile(profile),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
