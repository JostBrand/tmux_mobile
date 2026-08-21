import 'package:flutter_test/flutter_test.dart';
import 'package:tmux_mobile/src/config/known_hosts.dart';

void main() {
  test('TOFU: unknown host key is accepted', () {
    expect(
      verifyHostKeyDecision(knownFingerprint: null, offeredFingerprint: 'a'),
      isTrue,
    );
  });

  test('matching known host key is accepted', () {
    expect(
      verifyHostKeyDecision(knownFingerprint: 'abc', offeredFingerprint: 'abc'),
      isTrue,
    );
  });

  test('mismatching host key is rejected (MITM protection)', () {
    expect(
      verifyHostKeyDecision(knownFingerprint: 'abc', offeredFingerprint: 'xyz'),
      isFalse,
    );
  });

  test('in-memory store roundtrips', () async {
    final store = InMemoryKnownHostsStore();
    expect(await store.lookup('h:22'), isNull);
    await store.store('h:22', 'fp');
    expect(await store.lookup('h:22'), 'fp');
    await store.forget('h:22');
    expect(await store.lookup('h:22'), isNull);
  });
}
