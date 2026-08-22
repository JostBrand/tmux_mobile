import 'package:flutter/material.dart';
import 'package:tmux_mobile/src/config/connection_profile.dart';
import 'package:tmux_mobile/src/config/profile_repository.dart';
import 'package:tmux_mobile/src/config/secret_store.dart';
import 'package:tmux_mobile/src/config/settings_store.dart';
import 'package:tmux_mobile/src/integration/session_registry.dart';
import 'package:tmux_mobile/src/notifications/activity_notifier.dart';
import 'package:tmux_mobile/src/transport/session_factory.dart';
import 'package:tmux_mobile/src/ui/connect_screen.dart';
import 'package:tmux_mobile/src/ui/profile_edit_screen.dart';
import 'package:tmux_mobile/src/ui/settings_screen.dart';

/// Landing screen: saved connection profiles.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.profiles,
    required this.secretStore,
    required this.sessionFactory,
    this.settingsStore,
    this.activityNotifier,
    this.registry,
  });

  final ProfileRepository profiles;
  final SecretStore secretStore;
  final SessionFactory sessionFactory;
  final SettingsStore? settingsStore;
  final ActivityNotifier? activityNotifier;
  final SessionRegistry? registry;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<ConnectionProfile>> _profilesFuture;
  AppSettings _settings = const AppSettings();

  @override
  void initState() {
    super.initState();
    _profilesFuture = widget.profiles.load();
    widget.registry?.version.addListener(_onRegistryChanged);
    final store = widget.settingsStore;
    if (store != null) {
      store.load().then((settings) {
        if (mounted) {
          setState(() => _settings = settings);
        }
      });
    }
  }

  void _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          settingsStore: widget.settingsStore ?? InMemorySettingsStore(),
          profiles: widget.profiles,
        ),
      ),
    );
    _reload();
    final store = widget.settingsStore;
    if (store != null) {
      store.load().then((settings) {
        if (mounted) {
          setState(() => _settings = settings);
        }
      });
    }
  }

  @override
  void dispose() {
    widget.registry?.version.removeListener(_onRegistryChanged);
    super.dispose();
  }

  void _onRegistryChanged() {
    if (mounted) {
      setState(() {});
    }
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
          activityNotifier: widget.activityNotifier,
          registry: widget.registry,
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
    final pendingCount = widget.registry?.queue.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('tmux_mobile'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProfile,
        icon: const Icon(Icons.add),
        label: const Text('Add host'),
      ),
      body: Column(
        children: [
          if (pendingCount > 0)
            MaterialBanner(
              leading: const Icon(Icons.input),
              content: Text(
                '$pendingCount text(s) from other apps are waiting - '
                'connect to send them',
              ),
              actions: [
                TextButton(
                  onPressed: () => widget.registry?.queue.clear(),
                  child: const Text('Discard'),
                ),
              ],
            ),
          Expanded(
            child: FutureBuilder<List<ConnectionProfile>>(
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
          final ordered = [...profiles]..sort((a, b) {
              final recent = _settings.recentProfileIds;
              final ia = recent.indexOf(a.id);
              final ib = recent.indexOf(b.id);
              if (ia >= 0 && ib >= 0) {
                return ia.compareTo(ib);
              }
              if (ia >= 0) {
                return -1;
              }
              if (ib >= 0) {
                return 1;
              }
              return a.name.compareTo(b.name);
            });
          return ListView.separated(
            itemCount: ordered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final profile = ordered[index];
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
          ),
        ],
      ),
    );
  }
}
