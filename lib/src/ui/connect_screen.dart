import 'package:flutter/material.dart';
import 'package:tmux_mobile/src/config/connection_profile.dart';
import 'package:tmux_mobile/src/config/secret_store.dart';
import 'package:tmux_mobile/src/transport/session_factory.dart';
import 'package:tmux_mobile/src/ui/session_screen.dart';

/// Connects to a profile and hands over to the [SessionScreen].
///
/// Session selection flow:
/// - configured name set -> attach (or create) that session directly
/// - configured name empty -> list remote sessions:
///   - exactly one -> use it
///   - several -> picker dialog (+ "New session")
///   - none -> "New session" dialog (name pre-filled with 'mobile')
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
  String? _password;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<String?> _promptPassword() async {
    if (_password != null) {
      return _password;
    }
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
            'Password for ${widget.profile.username}@${widget.profile.host}'),
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
    if (password != null) {
      _password = password;
    }
    return password;
  }

  Future<String?> _chooseSession(List<String> sessions) async {
    if (sessions.length == 1) {
      return sessions.single;
    }
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select tmux session'),
        children: [
          for (final name in sessions)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(name),
              child: Text(name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_newSessionMarker),
            child: const Row(
              children: [
                Icon(Icons.add),
                SizedBox(width: 8),
                Text('New session'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _newSessionMarker = '__new__';

  Future<String?> _promptNewSessionName() async {
    final controller = TextEditingController(text: 'mobile');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New tmux session'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Session name'),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      if (!widget.profile.usesKeyAuth) {
        final password = await _promptPassword();
        if (password == null) {
          if (mounted) {
            Navigator.of(context).pop();
          }
          return;
        }
      }
      Future<String?> passwordPrompt() async => _password ?? '';

      final configured = widget.profile.sessionName.trim();
      String? sessionName;
      if (configured.isNotEmpty) {
        sessionName = configured;
      } else {
        // Hide the spinner while dialogs wait for user input.
        if (mounted) {
          setState(() => _connecting = false);
        }
        final sessions =
            await widget.sessionFactory.listSessions(widget.profile,
                passwordPrompt: passwordPrompt);
        if (sessions.isEmpty) {
          sessionName = await _promptNewSessionName();
        } else {
          final choice = await _chooseSession(sessions);
          sessionName = choice == _newSessionMarker
              ? await _promptNewSessionName()
              : choice;
        }
        if (mounted) {
          setState(() => _connecting = true);
        }
      }
      if (sessionName == null || sessionName.isEmpty) {
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      final session = await widget.sessionFactory.open(
        widget.profile,
        sessionName: sessionName,
        passwordPrompt: passwordPrompt,
      );
      if (!mounted) {
        await session.close();
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SessionScreen(
            client: session.client,
            title: '${widget.profile.name} · $sessionName',
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
