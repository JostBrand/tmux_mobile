import 'package:dartssh2/dartssh2.dart';
import 'package:tmux_mobile/src/config/connection_profile.dart';
import 'package:tmux_mobile/src/config/known_hosts.dart';
import 'package:tmux_mobile/src/config/secret_store.dart';
import 'package:tmux_mobile/src/control_mode/control_mode_client.dart';
import 'package:tmux_mobile/src/transport/ssh_tmux_transport.dart';

/// An opened tmux session: the control client plus a close action.
class OpenSession {
  const OpenSession({required this.client, required this.close});

  final ControlModeClient client;
  final Future<void> Function() close;
}

/// Opens tmux sessions for a profile. Abstract so widget tests can
/// inject a fake without any real SSH.
abstract class SessionFactory {
  Future<OpenSession> open(
    ConnectionProfile profile, {
    required Future<String?> Function() passwordPrompt,
  });
}

/// Real SSH-backed factory: loads the key from the secret store, wires
/// known-hosts verification (TOFU/reject) and returns the control client
/// of the tmux connection.
class SshSessionFactory implements SessionFactory {
  SshSessionFactory({required this.secretStore, required this.knownHosts});

  final SecretStore secretStore;
  final KnownHostsStore knownHosts;

  @override
  Future<OpenSession> open(
    ConnectionProfile profile, {
    required Future<String?> Function() passwordPrompt,
  }) async {
    SSHKeyPair? identity;
    if (profile.usesKeyAuth) {
      final pem = await secretStore.read(profile.keySecretId!);
      if (pem == null || pem.isEmpty) {
        throw StateError('SSH key not found in the secret store');
      }
      identity = SSHKeyPair.fromPem(pem).first;
    }
    final transport = SshTmuxTransport(
      host: profile.host,
      port: profile.port,
      username: profile.username,
      identity: identity,
      passwordPrompt: identity == null ? passwordPrompt : null,
      knownHosts: knownHosts,
    );
    final connection = await transport.connect(profile.sessionName);
    return OpenSession(client: connection.control, close: connection.close);
  }
}
