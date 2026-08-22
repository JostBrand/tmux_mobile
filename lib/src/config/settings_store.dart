import 'dart:convert';
import 'dart:io';

/// App-wide settings (independent of tmux server config).
class AppSettings {
  const AppSettings({
    this.fontSize = 14,
    this.hapticFeedback = true,
    this.keepScreenOn = false,
    this.recentProfileIds = const [],
  });

  final double fontSize;
  final bool hapticFeedback;
  final bool keepScreenOn;

  /// Most recently connected profile ids, most recent first.
  final List<String> recentProfileIds;

  AppSettings copyWith({
    double? fontSize,
    bool? hapticFeedback,
    bool? keepScreenOn,
    List<String>? recentProfileIds,
  }) =>
      AppSettings(
        fontSize: fontSize ?? this.fontSize,
        hapticFeedback: hapticFeedback ?? this.hapticFeedback,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        recentProfileIds: recentProfileIds ?? this.recentProfileIds,
      );

  /// Moves [profileId] to the front of the recents list.
  AppSettings withRecent(String profileId) {
    final ids = [
      profileId,
      ...recentProfileIds.where((id) => id != profileId),
    ];
    return copyWith(recentProfileIds: ids.take(10).toList());
  }

  Map<String, Object?> toJson() => {
        'fontSize': fontSize,
        'hapticFeedback': hapticFeedback,
        'keepScreenOn': keepScreenOn,
        'recentProfileIds': recentProfileIds,
      };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14,
        hapticFeedback: json['hapticFeedback'] as bool? ?? true,
        keepScreenOn: json['keepScreenOn'] as bool? ?? false,
        recentProfileIds: [
          for (final id in (json['recentProfileIds'] as List?) ?? const [])
            id as String,
        ],
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
