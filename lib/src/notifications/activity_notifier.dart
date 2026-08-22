/// Reports tmux pane/window activity to the user.
abstract class ActivityNotifier {
  Future<void> notify({required String title, required String body});
}

/// In-memory capture for tests.
class FakeActivityNotifier implements ActivityNotifier {
  final List<(String, String)> notifications = [];

  @override
  Future<void> notify({required String title, required String body}) async {
    notifications.add((title, body));
  }
}

/// tmux-style monitor-activity semantics: a pane triggers a notification
/// only when it produces output AFTER a silent period (default 30s) -
/// this mirrors the server-side monitor-activity and prevents
/// notification spam from chatty background panes.
class ActivityMonitor {
  ActivityMonitor({
    this.silentPeriod = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration silentPeriod;
  final DateTime Function() _now;
  final Map<String, DateTime> _lastOutput = {};

  /// Records output for [paneId]; returns true when a notification
  /// should fire (previous output was at least [silentPeriod] ago).
  bool onPaneOutput(String paneId) {
    final now = _now();
    final last = _lastOutput[paneId];
    _lastOutput[paneId] = now;
    return last != null && now.difference(last) >= silentPeriod;
  }
}
