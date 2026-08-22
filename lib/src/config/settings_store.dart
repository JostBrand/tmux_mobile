import 'dart:convert';
import 'dart:io';

/// App-wide settings (independent of tmux server config).
class AppSettings {
  const AppSettings({this.fontSize = 14, this.hapticFeedback = true});

  final double fontSize;
  final bool hapticFeedback;

  AppSettings copyWith({double? fontSize, bool? hapticFeedback}) =>
      AppSettings(
        fontSize: fontSize ?? this.fontSize,
        hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      );

  Map<String, Object?> toJson() => {
        'fontSize': fontSize,
        'hapticFeedback': hapticFeedback,
      };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14,
        hapticFeedback: json['hapticFeedback'] as bool? ?? true,
      );

  String encode() => jsonEncode(toJson());
}

abstract class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([this.settings = const AppSettings()]);

  AppSettings settings;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings value) async => settings = value;
}

class JsonFileSettingsStore implements SettingsStore {
  JsonFileSettingsStore(this.file);

  final File file;

  @override
  Future<AppSettings> load() async {
    if (!await file.exists()) {
      return const AppSettings();
    }
    try {
      return AppSettings.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, Object?>);
    } catch (_) {
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    await file.writeAsString(settings.encode());
  }
}
