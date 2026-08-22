import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tmux_mobile/src/config/connection_profile.dart';
import 'package:tmux_mobile/src/config/profile_repository.dart';
import 'package:tmux_mobile/src/config/settings_store.dart';

/// Platform channel into MainActivity (FLAG_KEEP_SCREEN_ON) - a native
/// 20-line replacement for the wakelock_plus plugin (whose
/// package_info_plus dependency breaks under AGP9 built-in Kotlin).
class _KeepScreenOn {
  static const _channel = MethodChannel('tmux_mobile/wakelock');

  static void set(bool enabled) {
    _channel.invokeMethod('setKeepScreenOn', enabled);
  }

  static void setSecureScreen(bool enabled) {
    _channel.invokeMethod('setSecureScreen', enabled);
  }
}

/// App settings: font size, haptics, keep-screen-on, profile
/// export/import (JSON via the clipboard - no cloud, no dependencies).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settingsStore,
    this.profiles,
  });

  final SettingsStore settingsStore;
  final ProfileRepository? profiles;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    widget.settingsStore.load().then((settings) {
      if (mounted) {
        setState(() => _settings = settings);
        _applyKeepScreenOn(settings.keepScreenOn);
        _applySecureScreen(settings.secureScreen);
      }
    });
  }

  void _update(AppSettings settings) {
    setState(() => _settings = settings);
    widget.settingsStore.save(settings);
    _applyKeepScreenOn(settings.keepScreenOn);
    _applySecureScreen(settings.secureScreen);
  }

  void _applyKeepScreenOn(bool enabled) {
    _KeepScreenOn.set(enabled);
  }

  void _applySecureScreen(bool enabled) {
    _KeepScreenOn.setSecureScreen(enabled);
  }

  Future<void> _exportProfiles() async {
    final profiles = await widget.profiles?.load() ?? [];
    if (profiles.isEmpty) {
      _snack('No profiles to export');
      return;
    }
    final payload = [
      for (final p in profiles) p.toJson(),
    ];
    await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload)));
    if (mounted) {
      _snack('${profiles.length} profile(s) copied as JSON');
    }
  }

  Future<void> _importProfiles() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      _snack('Clipboard is empty');
      return;
    }
    try {
      final decoded = jsonDecode(text) as List;
      final profiles = [
        for (final entry in decoded)
          ConnectionProfile.fromJson(entry as Map<String, Object?>),
      ];
      for (final profile in profiles) {
        await widget.profiles?.save(profile);
      }
      if (mounted) {
        _snack('Imported ${profiles.length} profile(s)');
      }
    } catch (_) {
      _snack('Clipboard does not contain valid profiles JSON');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  leading: const Icon(Icons.format_size),
                  title: const Text('Terminal font size'),
                  subtitle: Slider(
                    value: settings.fontSize,
                    min: 10,
                    max: 24,
                    divisions: 14,
                    label: settings.fontSize.round().toString(),
                    onChanged: (value) =>
                        _update(settings.copyWith(fontSize: value)),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.vibration),
                  title: const Text('Haptic feedback'),
                  subtitle: const Text('Vibrate when the prefix/mod mode activates'),
                  value: settings.hapticFeedback,
                  onChanged: (value) =>
                      _update(settings.copyWith(hapticFeedback: value)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.screen_lock_portrait),
                  title: const Text('Keep screen on'),
                  subtitle:
                      const Text('Keep the display awake while connected'),
                  value: settings.keepScreenOn,
                  onChanged: (value) =>
                      _update(settings.copyWith(keepScreenOn: value)),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.no_photography),
                  title: const Text('Block screenshots'),
                  subtitle: const Text(
                      'FLAG_SECURE: prevents screenshots and screen '
                      'recording of terminal content'),
                  value: settings.secureScreen,
                  onChanged: (value) =>
                      _update(settings.copyWith(secureScreen: value)),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.upload),
                  title: const Text('Export profiles'),
                  subtitle: const Text('Copy all profiles as JSON'),
                  onTap: _exportProfiles,
                ),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Import profiles'),
                  subtitle:
                      const Text('Read profiles JSON from the clipboard'),
                  onTap: _importProfiles,
                ),
              ],
            ),
    );
  }
}
