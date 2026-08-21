import 'package:flutter/material.dart';
import 'package:tmux_mobile/src/ui/keybar.dart';

void main() {
  runApp(const TmuxMobileApp());
}

class TmuxMobileApp extends StatelessWidget {
  const TmuxMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tmux_mobile',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

/// M2 placeholder: connection profiles (host/user/key) arrive with M3.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('tmux_mobile')),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Text(
                'Connection profiles arrive with M3.\n'
                'The control-mode client, SSH transport, pane rendering\n'
                'and keybar are ready (see flutter test).',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
          // Keybar preview until the session screen is wired up.
          Keybar(onKey: (_) {}),
        ],
      ),
    );
  }
}
