import 'package:flutter/material.dart';

/// One selectable target (window or pane).
class TargetOption {
  const TargetOption({required this.id, required this.label});

  final String id;
  final String label;
}

/// Generic picker sheet: fetches a target list (windows/panes) from the
/// server via [fetch] and reports the tapped option.
class TargetPickerSheet extends StatefulWidget {
  const TargetPickerSheet({
    super.key,
    required this.title,
    required this.fetch,
    required this.onSelected,
  });

  final String title;
  final Future<List<TargetOption>> Function() fetch;
  final void Function(TargetOption option) onSelected;

  @override
  State<TargetPickerSheet> createState() => _TargetPickerSheetState();
}

class _TargetPickerSheetState extends State<TargetPickerSheet> {
  late Future<List<TargetOption>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetch();
  }

  void _reload() {
    setState(() => _future = widget.fetch());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        child: SizedBox(
          height: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(widget.title,
                          style: theme.textTheme.titleMedium),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<TargetOption>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Could not load: ${snapshot.error}',
                                style: theme.textTheme.bodySmall),
                            TextButton(
                                onPressed: _reload, child: const Text('Retry')),
                          ],
                        ),
                      );
                    }
                    final options = snapshot.data;
                    if (options == null) {
                      return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    if (options.isEmpty) {
                      return Center(
                        child: Text('Nothing here', style: theme.textTheme.bodyMedium),
                      );
                    }
                    return ListView(
                      children: [
                        for (final option in options)
                          ListTile(
                            dense: true,
                            leading: Text(
                              option.id,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            title: Text(option.label),
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.onSelected(option);
                            },
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
