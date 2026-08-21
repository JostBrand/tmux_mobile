import 'dart:convert';
import 'dart:io';

import 'package:tmux_mobile/src/config/connection_profile.dart';

/// Persists [ConnectionProfile]s. Implementations: JSON file (device) and
/// in-memory (tests).
abstract class ProfileRepository {
  Future<List<ConnectionProfile>> load();
  Future<void> save(ConnectionProfile profile);
  Future<void> delete(String id);
}

class InMemoryProfileRepository implements ProfileRepository {
  InMemoryProfileRepository([List<ConnectionProfile> seed = const []])
      : _profiles = [...seed];

  final List<ConnectionProfile> _profiles;

  @override
  Future<List<ConnectionProfile>> load() async => List.unmodifiable(_profiles);

  @override
  Future<void> save(ConnectionProfile profile) async {
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      _profiles[index] = profile;
    } else {
      _profiles.add(profile);
    }
  }

  @override
  Future<void> delete(String id) async {
    _profiles.removeWhere((p) => p.id == id);
  }
}

class JsonFileProfileRepository implements ProfileRepository {
  JsonFileProfileRepository(this.file);

  final File file;

  @override
  Future<List<ConnectionProfile>> load() async {
    if (!await file.exists()) {
      return [];
    }
    final decoded = jsonDecode(await file.readAsString());
    return [
      for (final entry in decoded as List)
        ConnectionProfile.fromJson(entry as Map<String, Object?>),
    ];
  }

  @override
  Future<void> save(ConnectionProfile profile) async {
    final profiles = await load();
    final index = profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
    await file.writeAsString(
        jsonEncode([for (final p in profiles) p.toJson()]));
  }

  @override
  Future<void> delete(String id) async {
    final profiles = await load()..removeWhere((p) => p.id == id);
    await file.writeAsString(
        jsonEncode([for (final p in profiles) p.toJson()]));
  }
}
