import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_call_intent.dart';

void main() {
  final now = DateTime.utc(2026, 8, 31, 12);
  final intent = RingCallIntent(
    eventId: 'evt-${List.filled(32, 'a').join()}',
    deviceId: 'ib-${List.filled(32, 'b').join()}',
    occurredAt: now,
  );

  test('serializes and restores only minimal validated context', () {
    final encoded = intent.serialize();
    final restored = RingCallIntent.tryRestore(encoded, now: now);
    expect(restored?.eventId, intent.eventId);
    expect(restored?.deviceId, intent.deviceId);
    expect(encoded, isNot(contains('token')));
    expect(encoded, isNot(contains('title')));
    expect(encoded, isNot(contains('body')));
  });

  test('rejects malformed, extra, and expired context', () {
    expect(RingCallIntent.tryRestore('{bad', now: now), isNull);
    expect(
      RingCallIntent.tryRestore(
        '{"v":1,"event_id":"bad","device_id":"bad","occurred_at":"2026-08-31T12:00:00.000Z"}',
        now: now,
      ),
      isNull,
    );
    expect(
      RingCallIntent.tryRestore(
        intent.serialize(),
        now: now.add(const Duration(minutes: 16)),
      ),
      isNull,
    );
  });

  test('notification id is stable and non-negative', () {
    expect(
      ringNotificationId(intent.eventId),
      ringNotificationId(intent.eventId),
    );
    expect(ringNotificationId(intent.eventId), isNonNegative);
  });
}
