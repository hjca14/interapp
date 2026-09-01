import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_call_intent.dart';
import 'package:interapp/core/push/ring_detected_event.dart';
import 'package:interapp/core/push/ring_detected_push_parser.dart';

final _callIdPattern = RegExp(r'^call-[0-9a-f]{32}$');

void main() {
  group('deriveLegacyCallId', () {
    test('strips the evt- prefix and adds call-, keeping the same 32 hex '
        'suffix', () {
      expect(
        deriveLegacyCallId('evt-0123456789abcdef0123456789abcdef'),
        'call-0123456789abcdef0123456789abcdef',
      );
    });

    test('the derived id always matches the canonical ^call-[0-9a-f]{32}\$ '
        'contract', () {
      final derived = deriveLegacyCallId('evt-${List.filled(32, 'f').join()}');
      expect(_callIdPattern.hasMatch(derived), isTrue);
    });

    test('is deterministic — a retried delivery of the same event_id '
        'always derives the same call_id', () {
      const eventId = 'evt-0123456789abcdef0123456789abcdef';
      expect(deriveLegacyCallId(eventId), deriveLegacyCallId(eventId));
    });
  });

  group('legacy RING_DETECTED end to end (no explicit call_id)', () {
    final now = DateTime.utc(2026, 8, 31, 12);
    Map<String, dynamic> legacyPayload({
      String eventId = 'evt-0123456789abcdef0123456789abcdef',
    }) => {
      'push_contract_version': '1',
      'event': 'RING_DETECTED',
      'event_id': eventId,
      'device_id': 'ib-fedcba9876543210fedcba9876543210',
      'presentation_intent': 'RING_ONLY',
      'occurred_at': now.toIso8601String(),
    };

    test('RingCallIntent.fromEvent(...).serialize() carries the derived '
        'call-<32 hex> id, never the raw evt-prefixed event_id', () {
      final result = parseRingDetectedPush(legacyPayload(), now: now);
      final event = (result as RingPushParsed).event as RingDetectedEvent;

      final serialized = RingCallIntent.fromEvent(event).serialize();

      expect(serialized, contains('"call_id":"call-'));
      expect(
        serialized,
        isNot(contains('"call_id":"evt-0123456789abcdef0123456789abcdef"')),
      );
    });

    test('RingCallIntent.tryRestore() restores the normalized legacy call_id '
        'end to end, from a freshly-serialized legacy intent', () {
      final result = parseRingDetectedPush(legacyPayload(), now: now);
      final event = (result as RingPushParsed).event as RingDetectedEvent;
      final serialized = RingCallIntent.fromEvent(event).serialize();

      final restored = RingCallIntent.tryRestore(serialized, now: now);

      expect(restored, isNotNull);
      expect(restored!.callId, 'call-0123456789abcdef0123456789abcdef');
      expect(_callIdPattern.hasMatch(restored.callId), isTrue);
    });

    test('ringNotificationId is stable and computed from the normalized '
        'call_id, not the raw event_id', () {
      final result = parseRingDetectedPush(legacyPayload(), now: now);
      final event = (result as RingPushParsed).event as RingDetectedEvent;

      expect(
        ringNotificationId(event.callId),
        ringNotificationId('call-0123456789abcdef0123456789abcdef'),
      );
    });
  });
}
