import 'dart:convert';
import 'dart:io';

/// Known-hosts persistence for SSH host key verification.
///
/// The transport looks up the fingerprint for `host:port`; on first
/// connect (TOFU) the fingerprint is stored, later connects must match.
/// A mismatch means a MITM or a changed server key - the connection is
/// rejected.
abstract class KnownHostsStore {
  Future<String?> lookup(String hostPort);
  Future<void> store(String hostPort, String fingerprint);
  Future<void> forget(String hostPort);
}

class InMemoryKnownHostsStore implements KnownHostsStore {
  final _hosts = <String, String>{};

  @override
  Future<String?> lookup(String hostPort) async => _hosts[hostPort];

  @override
  Future<void> store(String hostPort, String fingerprint) async =>
      _hosts[hostPort] = fingerprint;

  @override
  Future<void> forget(String hostPort) async => _hosts.remove(hostPort);
}

class JsonFileKnownHostsStore implements KnownHostsStore {
  JsonFileKnownHostsStore(this.file);

  final File file;

  Future<Map<String, String>> _load() async {
    if (!await file.exists()) {
      return {};
    }
    final decoded = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    return decoded.map((key, value) => MapEntry(key, value as String));
  }

  @override
  Future<String?> lookup(String hostPort) async => (await _load())[hostPort];

  @override
  Future<void> store(String hostPort, String fingerprint) async {
    final hosts = await _load();
    hosts[hostPort] = fingerprint;
    await file.writeAsString(jsonEncode(hosts));
  }

  @override
  Future<void> forget(String hostPort) async {
    final hosts = await _load()..remove(hostPort);
    await file.writeAsString(jsonEncode(hosts));
  }
}

/// Pure decision logic for host key verification (unit-testable).
/// Returns true when the key is acceptable.
bool verifyHostKeyDecision({
  required String? knownFingerprint,
  required String offeredFingerprint,
}) {
  if (knownFingerprint == null) {
    // TOFU: nothing stored yet - accept and remember.
    return true;
  }
  return knownFingerprint == offeredFingerprint;
}

/// The onVerifyHostKey callback receives a raw Uint8List fingerprint
/// (OpenSSH-style SHA256); store it base64-encoded.
String encodeHostFingerprint(List<int> fingerprint) =>
    base64Encode(fingerprint);
