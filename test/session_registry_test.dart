import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/integration/intent_receiver.dart';
import 'package:tmux_mobile/src/integration/session_registry.dart';

void main() {
  test('queue trims, dedupes not, and pops in order', () {
    final queue = PendingTextQueue();
    queue.add('  hello  ');
    queue.add('');
    queue.add('world');
    expect(queue.length, 2);
    expect(queue.takeNext(), 'hello');
    expect(queue.takeNext(), 'world');
    expect(queue.takeNext(), isNull);
    queue.add('x');
    queue.clear();
    expect(queue.length, 0);
  });

  test('registry offers text to the live session', () {
    final registry = SessionRegistry();
    final offered = <String>[];
    registry.register(LiveSessionHandle(
      profileName: 'dev',
      offerText: offered.add,
    ));
    expect(registry.deliverText('hello'), isTrue);
    expect(offered, ['hello']);
    expect(registry.queue.length, 0);
  });

  test('registry queues when no session is open', () {
    final registry = SessionRegistry();
    expect(registry.deliverText('hello'), isFalse);
    expect(registry.queue.items, ['hello']);

    final offered = <String>[];
    registry.register(LiveSessionHandle(
      profileName: 'dev',
      offerText: offered.add,
    ));
    // Delivered texts are offered to the session now.
    expect(registry.deliverText('direct'), isTrue);
    expect(offered, ['direct']);
  });

  test('unregister stops delivery', () {
    final registry = SessionRegistry();
    final offered = <String>[];
    final handle = LiveSessionHandle(
      profileName: 'dev',
      offerText: offered.add,
    );
    registry.register(handle);
    registry.unregister(handle);
    expect(registry.deliverText('queued'), isFalse);
    expect(offered, isEmpty);
  });
}
