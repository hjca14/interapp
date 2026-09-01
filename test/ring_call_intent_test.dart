import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_call_intent.dart';

void main() {
  final now = DateTime.utc(2026, 8, 31, 12);
  final intent = RingCallIntent(
    eventId: 'evt-${List.filled(32, 'a').join()}',
    callId: 'call-${List.filled(32, 'c').join()}',
    deviceId: 'ib-${List.filled(32, 'b').join()}',
    occurredAt: now,
  );

  test('serializes and restores only minimal validated context', () {
    final encoded = intent.serialize();
    final restored = RingCallIntent.tryRestore(encoded, now: now);
    expect(restored?.eventId, intent.eventId);
    expect(restored?.callId, intent.callId);
    expect(restored?.deviceId, intent.deviceId);
    expect(encoded, isNot(contains('token')));
    expect(encoded, isNot(contains('title')));
    expect(encoded, isNot(contains('body')));
  });

  test('rejects malformed, extra, and expired context', () {
    expect(RingCallIntent.tryRestore('{bad', now: now), isNull);
    expect(
      RingCallIntent.tryRestore(
        '{"v":2,"event_id":"bad","call_id":"bad","device_id":"bad","occurred_at":"2026-08-31T12:00:00.000Z"}',
        now: now,
      ),
      isNull,
    );
    expect(
      RingCallIntent.tryRestore(
        intent.serialize(),
        now: now.add(const Duration(seconds: 61)),
      ),
      isNull,
    );
  });

  test('rejects a v1 (pre-call_id) payload', () {
    expect(
      RingCallIntent.tryRestore(
        '{"v":1,"event_id":"${intent.eventId}","device_id":"${intent.deviceId}",'
        '"occurred_at":"2026-08-31T12:00:00.000Z"}',
        now: now,
      ),
      isNull,
    );
  });

  test('an explicit maxAge overrides the 60s default', () {
    expect(
      RingCallIntent.tryRestore(
        intent.serialize(),
        now: now.add(const Duration(minutes: 10)),
        maxAge: const Duration(minutes: 15),
      ),
      isNotNull,
    );
  });

  test('notification id is stable and non-negative', () {
    expect(
      ringNotificationId(intent.callId),
      ringNotificationId(intent.callId),
    );
    expect(ringNotificationId(intent.callId), isNonNegative);
  });

  test('notification id differs for different call ids', () {
    expect(
      ringNotificationId(intent.callId),
      isNot(ringNotificationId('call-${List.filled(32, 'd').join()}')),
    );
  });
}
