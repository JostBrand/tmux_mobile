import 'package:flutter/material.dart';
import 'package:tmux_mobile/src/config/connection_profile.dart';
import 'package:tmux_mobile/src/config/secret_store.dart';
import 'package:tmux_mobile/src/transport/session_factory.dart';
import 'package:tmux_mobile/src/ui/session_screen.dart';

/// Connects to a profile and hands over to the [SessionScreen].
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    super.key,
    required this.profile,
    required this.secretStore,
    required this.sessionFactory,
  });

  final ConnectionProfile profile;
  final SecretStore secretStore;
  final SessionFactory sessionFactory;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    String? password;
    try {
      if (!widget.profile.usesKeyAuth) {
        password = await _promptPassword();
        if (password == null) {
          if (mounted) {
            Navigator.of(context).pop();
          }
          return;
        }
      }
      final session = await widget.sessionFactory.open(
        widget.profile,
        passwordPrompt: () async => password ?? '',
      );
      if (!mounted) {
        await session.close();
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SessionScreen(
            client: session.client,
            title: widget.profile.name,
            onDispose: session.close,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = _describeError(error);
        });
      }
    }
  }

  Future<String?> _promptPassword() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Password for ${widget.profile.username}@${widget.profile.host}'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  String _describeError(Object error) {
    final text = error.toString();
    if (text.contains('host key')) {
      return 'Host key verification failed - the server key changed. '
          'This could be a man-in-the-middle attack.';
    }
    if (text.contains('Permission denied') || text.contains('auth')) {
      return 'Authentication failed. Check username, key or password.';
    }
    return 'Connection failed: $text';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.profile.name)),
      body: Center(
        child: _connecting
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(_error ?? 'Connection failed',
                        textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _connect,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
      ),
    );
  }
}
