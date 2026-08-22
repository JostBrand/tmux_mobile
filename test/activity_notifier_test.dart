import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/notifications/activity_notifier.dart';

void main() {
  test('first output never notifies (no silence history)', () {
    var now = DateTime(2026, 1, 1, 12, 0, 0);
    final monitor = ActivityMonitor(now: () => now);
    expect(monitor.onPaneOutput('%1'), isFalse);
  });

  test('output after the silent period notifies', () {
    var now = DateTime(2026, 1, 1, 12, 0, 0);
    final monitor = ActivityMonitor(now: () => now);
    monitor.onPaneOutput('%1');
    now = now.add(const Duration(seconds: 31));
    expect(monitor.onPaneOutput('%1'), isTrue);
  });

  test('continuous output does not notify', () {
    var now = DateTime(2026, 1, 1, 12, 0, 0);
    final monitor = ActivityMonitor(now: () => now);
    monitor.onPaneOutput('%1');
    now = now.add(const Duration(seconds: 5));
    expect(monitor.onPaneOutput('%1'), isFalse);
    now = now.add(const Duration(seconds: 5));
    expect(monitor.onPaneOutput('%1'), isFalse);
  });

  test('silent periods are tracked per pane', () {
    var now = DateTime(2026, 1, 1, 12, 0, 0);
    final monitor = ActivityMonitor(now: () => now);
    monitor.onPaneOutput('%1');
    monitor.onPaneOutput('%2');
    now = now.add(const Duration(seconds: 60));
    expect(monitor.onPaneOutput('%2'), isTrue);
  });
}
