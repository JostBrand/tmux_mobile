import 'package:flutter/material.dart';

/// Scrollable read-only history of one pane (the "scrollback sheet").
///
/// Data comes from the server: `capture-pane -p -e -S -<depth>` pages,
/// oldest at the top of the sheet. Pages are overlap-deduplicated against
/// the current list (capture output ends with the visible screen, which is
/// already part of the previous page).
///
/// A reverse ListView anchors the viewport at the NEWEST line; loading
/// older pages appends above without shifting the view.
class PaneHistorySheet extends StatefulWidget {
  const PaneHistorySheet({
    super.key,
    required this.paneId,
    required this.fetchOlder,
    this.onCopy,
    this.onShare,
    this.pageSize = 200,
  });

  final String paneId;

  /// Returns the last [depth] lines of pane history (oldest -> newest).
  final Future<List<String>> Function(int depth) fetchOlder;

  /// Called with the text of a tapped line (defaults to clipboard copy).
  final void Function(String line)? onCopy;

  /// Called with the text of a long-pressed line (share to other apps).
  final void Function(String line)? onShare;

  final int pageSize;

  @override
  State<PaneHistorySheet> createState() => _PaneHistorySheetState();
}

class _PaneHistorySheetState extends State<PaneHistorySheet> {
  /// Oldest -> newest.
  final List<String> _lines = <String>[];
  int _depth = 0;
  String _query = '';
  final _searchController = TextEditingController();
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final newDepth = _depth + widget.pageSize;
      final fetched = await widget.fetchOlder(newDepth);
      final overlap = _overlapCount(_lines, fetched);
      final older = fetched.sublist(0, fetched.length - overlap);
      setState(() {
        _lines.insertAll(0, older);
        _depth = newDepth;
        _hasMore = fetched.length >= newDepth;
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// Longest suffix of [fetched] that equals a prefix of [existing].
  static int _overlapCount(List<String> existing, List<String> fetched) {
    final maxOverlap =
        existing.length < fetched.length ? existing.length : fetched.length;
    for (var n = maxOverlap; n > 0; n--) {
      var matches = true;
      for (var i = 0; i < n; i++) {
        if (fetched[fetched.length - n + i] != existing[i]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return n;
      }
    }
    return 0;
  }

  void _copyLine(String line) {
    if (widget.onCopy != null) {
      widget.onCopy!(line);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.3,
      builder: (context, scrollController) {
        return Material(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'History - ${widget.paneId}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Search history',
                  ),
                  onChanged: (value) => setState(() => _query = value.trim()),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  reverse: true,
                  itemCount: _lines.length + (_hasMore || _error != null ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _lines.length) {
                      return _buildFooter(theme);
                    }
                    var line = _lines[_lines.length - 1 - index];
                    if (_query.isNotEmpty && !line.contains(_query)) {
                      return const SizedBox.shrink();
                    }
                    return InkWell(
                      onTap: () => _copyLine(line),
                      onLongPress: widget.onShare == null
                          ? null
                          : () => widget.onShare!(line),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 2),
                        child: Text(
                          line.isEmpty ? ' ' : line,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooter(ThemeData theme) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Could not load more history', style: theme.textTheme.bodySmall),
            TextButton(onPressed: _loadMore, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Center(
          child: TextButton(
            onPressed: _loadMore,
            child: Text('Load older'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Text('End of history', style: theme.textTheme.bodySmall),
      ),
    );
  }
}
