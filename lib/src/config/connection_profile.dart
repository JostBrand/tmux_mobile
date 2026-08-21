import 'dart:convert';

/// One saved SSH/tmux connection target.
///
/// Passwords are NEVER stored - they are prompted at connect time. SSH
/// private keys are stored via a [SecretStore] (secure storage on the
/// device) and referenced by [keySecretId].
class ConnectionProfile {
  const ConnectionProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    required this.sessionName,
    this.keySecretId,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String sessionName;

  /// SecretStore entry holding the private key (null = password auth).
  final String? keySecretId;

  bool get usesKeyAuth => keySecretId != null;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'sessionName': sessionName,
        'keySecretId': keySecretId,
      };

  factory ConnectionProfile.fromJson(Map<String, Object?> json) {
    return ConnectionProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int? ?? 22,
      username: json['username'] as String,
      sessionName: json['sessionName'] as String,
      keySecretId: json['keySecretId'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());

  factory ConnectionProfile.decode(String source) =>
      ConnectionProfile.fromJson(jsonDecode(source) as Map<String, Object?>);

  ConnectionProfile copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    String? sessionName,
    String? keySecretId,
  }) {
    return ConnectionProfile(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      sessionName: sessionName ?? this.sessionName,
      keySecretId: keySecretId ?? this.keySecretId,
    );
  }
}
