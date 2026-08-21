import 'package:flutter/material.dart';
import 'package:tmux_mobile/src/config/connection_profile.dart';
import 'package:tmux_mobile/src/config/secret_store.dart';

/// Create/edit form for a [ConnectionProfile].
///
/// Auth: either an SSH private key (pasted here once, stored via the
/// secret store - never in the profile file) or password auth (prompted
/// at connect time, never stored).
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({
    super.key,
    this.initial,
    required this.secretStore,
    required this.onSave,
  });

  final ConnectionProfile? initial;
  final SecretStore secretStore;
  final Future<void> Function(ConnectionProfile profile) onSave;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _session;
  late final TextEditingController _key;
  late bool _useKey;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _host = TextEditingController(text: initial?.host ?? '');
    _port = TextEditingController(text: (initial?.port ?? 22).toString());
    _username = TextEditingController(text: initial?.username ?? '');
    _session = TextEditingController(text: initial?.sessionName ?? '');
    _key = TextEditingController();
    _useKey = initial?.usesKeyAuth ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _session.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final id = widget.initial?.id ??
        'profile-${DateTime.now().microsecondsSinceEpoch}';
    String? keySecretId = widget.initial?.keySecretId;
    if (_useKey) {
      keySecretId ??= 'key-$id';
      final keyText = _key.text.trim();
      if (keyText.isNotEmpty) {
        await widget.secretStore.write(keySecretId, keyText);
      } else {
        final stored = await widget.secretStore.read(keySecretId);
        if (stored == null) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Paste an SSH private key first')),
          );
          return;
        }
      }
    }
    final profile = ConnectionProfile(
      id: id,
      name: _name.text.trim(),
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 22,
      username: _username.text.trim(),
      sessionName: _session.text.trim(),
      keySecretId: _useKey ? keySecretId : null,
    );
    await widget.onSave(profile);
    if (mounted) {
      Navigator.of(context).pop(profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Add host' : 'Edit host'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _host,
              decoration: const InputDecoration(labelText: 'Host'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _port,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _session,
              decoration: const InputDecoration(
                labelText: 'tmux session name',
                helperText: 'Attached with attach-session -t <name>',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            SwitchListTile(
              title: const Text('SSH key auth'),
              subtitle: const Text(
                  'Password auth prompts at connect time and is never stored'),
              value: _useKey,
              onChanged: (value) => setState(() => _useKey = value),
            ),
            if (_useKey)
              TextFormField(
                controller: _key,
                minLines: 3,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'SSH private key (paste, stored securely)',
                  hintText:
                      '-----BEGIN OPENSSH PRIVATE KEY-----\n...\n(leave empty to keep the stored key)',
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
