import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_detected_event.dart';
import 'package:interapp/core/push/ring_detected_push_parser.dart';

Map<String, dynamic> _validPayload({
  String pushContractVersion = '1',
  String event = 'RING_DETECTED',
  String eventId = 'evt-0123456789abcdef0123456789abcdef',
  String deviceId = 'ib-fedcba9876543210fedcba9876543210',
  String presentationIntent = 'RING_ONLY',
  String occurredAt = '2026-08-30T12:00:00Z',
}) => {
  'push_contract_version': pushContractVersion,
  'event': event,
  'event_id': eventId,
  'device_id': deviceId,
  'presentation_intent': presentationIntent,
  'occurred_at': occurredAt,
};

final _fixedNow = DateTime.parse('2026-08-30T12:00:05Z');

void main() {
  group('valid payloads', () {
    for (final intent in [
      ('RING_ONLY', RingPresentationIntent.ringOnly),
      ('NOTIFICATION_ONLY', RingPresentationIntent.notificationOnly),
      ('RING_AND_NOTIFICATION', RingPresentationIntent.ringAndNotification),
    ]) {
      test('parses ${intent.$1}', () {
        final result = parseRingDetectedPush(
          _validPayload(presentationIntent: intent.$1),
          now: _fixedNow,
        );

        expect(result, isA<RingPushParsed>());
        final event = (result as RingPushParsed).event as RingDetectedEvent;
        expect(event.presentationIntent, intent.$2);
        expect(event.eventId, 'evt-0123456789abcdef0123456789abcdef');
        expect(event.deviceId, 'ib-fedcba9876543210fedcba9876543210');
        expect(event.occurredAt, DateTime.parse('2026-08-30T12:00:00Z'));
        expect(
          event.callId,
          'evt-0123456789abcdef0123456789abcdef',
          reason: 'defaults call_id to event_id when the backend omits it',
        );
      });
    }

    test('extra fields never influence the parsed event', () {
      final payload = _validPayload()
        ..['device_name'] = 'Portaria da Casa'
        ..['user_id'] = 'user-123'
        ..['unexpected'] = 'anything';

      final result = parseRingDetectedPush(payload, now: _fixedNow);

      expect(result, isA<RingPushParsed>());
      final event = (result as RingPushParsed).event as RingDetectedEvent;
      expect(event.eventId, 'evt-0123456789abcdef0123456789abcdef');
      expect(event.deviceId, 'ib-fedcba9876543210fedcba9876543210');
      expect(event.presentationIntent, RingPresentationIntent.ringOnly);
    });

    test('a present call_id is used verbatim instead of defaulting to '
        'event_id', () {
      final payload = _validPayload()
        ..['call_id'] = 'call-0123456789abcdef0123456789abcdef';

      final result = parseRingDetectedPush(payload, now: _fixedNow);

      expect(result, isA<RingPushParsed>());
      final event = (result as RingPushParsed).event as RingDetectedEvent;
      expect(event.callId, 'call-0123456789abcdef0123456789abcdef');
    });

    test('rejects a malformed call_id', () {
      final payload = _validPayload()..['call_id'] = 'not-a-call-id';

      final result = parseRingDetectedPush(payload, now: _fixedNow);

      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.invalidCallId,
        ),
      );
    });
  });

  group('RING_ENDED', () {
    Map<String, dynamic> validEnded({
      String eventId = 'evt-abcdef0123456789abcdef0123456789',
      String callId = 'call-0123456789abcdef0123456789abcdef',
    }) => {
      'push_contract_version': '1',
      'event': 'RING_ENDED',
      'event_id': eventId,
      'device_id': 'ib-fedcba9876543210fedcba9876543210',
      'call_id': callId,
      'occurred_at': '2026-08-30T12:00:00Z',
    };

    test('parses a valid RING_ENDED', () {
      final result = parseRingDetectedPush(validEnded(), now: _fixedNow);

      expect(result, isA<RingPushParsed>());
      final event = (result as RingPushParsed).event as RingEndedEvent;
      expect(event.eventId, 'evt-abcdef0123456789abcdef0123456789');
      expect(event.callId, 'call-0123456789abcdef0123456789abcdef');
      expect(event.deviceId, 'ib-fedcba9876543210fedcba9876543210');
    });

    test('rejects a RING_ENDED missing call_id', () {
      final payload = validEnded()..remove('call_id');

      final result = parseRingDetectedPush(payload, now: _fixedNow);

      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.missingField,
        ),
      );
    });

    test('rejects a RING_ENDED with a malformed call_id', () {
      final result = parseRingDetectedPush(
        validEnded(callId: 'not-a-call-id'),
        now: _fixedNow,
      );

      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.invalidCallId,
        ),
      );
    });

    test('does not require presentation_intent', () {
      final payload = validEnded();
      expect(payload.containsKey('presentation_intent'), isFalse);

      final result = parseRingDetectedPush(payload, now: _fixedNow);

      expect(result, isA<RingPushParsed>());
    });

    test('an old RING_ENDED is still rejected as too old', () {
      final result = parseRingDetectedPush({
        ...validEnded(),
        'occurred_at': '2020-01-01T00:00:00Z',
      }, now: _fixedNow);

      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.timestampTooOld,
        ),
      );
    });
  });

  group('rejections', () {
    test('rejects an unknown contract version', () {
      final result = parseRingDetectedPush(
        _validPayload(pushContractVersion: '2'),
        now: _fixedNow,
      );
      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.unsupportedContractVersion,
        ),
      );
    });

    test('rejects an event other than RING_DETECTED', () {
      final result = parseRingDetectedPush(
        _validPayload(event: 'SOMETHING_ELSE'),
        now: _fixedNow,
      );
      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.unsupportedEvent,
        ),
      );
    });

    for (final missing in [
      'push_contract_version',
      'event',
      'event_id',
      'device_id',
      'presentation_intent',
      'occurred_at',
    ]) {
      test('rejects a payload missing $missing', () {
        final payload = _validPayload()..remove(missing);
        final result = parseRingDetectedPush(payload, now: _fixedNow);
        expect(
          result,
          isA<RingPushRejected>().having(
            (r) => r.reason,
            'reason',
            RingPushRejectionReason.missingField,
          ),
        );
      });
    }

    test('rejects a non-string field value', () {
      final payload = _validPayload();
      payload['event_id'] = 42;
      final result = parseRingDetectedPush(payload, now: _fixedNow);
      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.missingField,
        ),
      );
    });

    test('rejects a malformed event_id', () {
      final result = parseRingDetectedPush(
        _validPayload(eventId: 'not-a-valid-id'),
        now: _fixedNow,
      );
      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.invalidEventId,
        ),
      );
    });

    test('rejects an event_id with uppercase hex', () {
      final result = parseRingDetectedPush(
        _validPayload(eventId: 'evt-0123456789ABCDEF0123456789ABCDEF'),
        now: _fixedNow,
      );
      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.invalidEventId,
        ),
      );
    });

    test('rejects a malformed device_id', () {
      final result = parseRingDetectedPush(
        _validPayload(deviceId: 'device-123'),
        now: _fixedNow,
      );
      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.invalidDeviceId,
        ),
      );
    });

    test('rejects an unsupported presentation_intent', () {
      final result = parseRingDetectedPush(
        _validPayload(presentationIntent: 'RING_LOUDLY'),
        now: _fixedNow,
      );
      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.invalidPresentationIntent,
        ),
      );
    });

    test('rejects a non-ISO-8601 timestamp', () {
      final result = parseRingDetectedPush(
        _validPayload(occurredAt: 'yesterday'),
        now: _fixedNow,
      );
      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.invalidTimestamp,
        ),
      );
    });

    test('rejects a timestamp without an explicit UTC (Z) marker', () {
      final result = parseRingDetectedPush(
        _validPayload(occurredAt: '2026-08-30T12:00:00'),
        now: _fixedNow,
      );
      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.invalidTimestamp,
        ),
      );
    });

    test('rejects an excessively old event', () {
      final result = parseRingDetectedPush(
        _validPayload(occurredAt: '2020-01-01T00:00:00Z'),
        now: _fixedNow,
      );
      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.timestampTooOld,
        ),
      );
    });

    test('accepts an event right at the edge of maxAge', () {
      final now = DateTime.parse('2026-08-30T12:10:00Z');
      final result = parseRingDetectedPush(
        _validPayload(occurredAt: '2026-08-30T12:00:00Z'),
        now: now,
        maxAge: const Duration(minutes: 15),
      );
      expect(result, isA<RingPushParsed>());
    });
  });
}
