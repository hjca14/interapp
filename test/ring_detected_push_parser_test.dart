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
          'call-0123456789abcdef0123456789abcdef',
          reason:
              'derives call-<32 hex> from the event_id suffix when the '
              'backend omits call_id, never the raw evt- prefixed value',
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

    test('accepts an event right at the edge of maxAge — NOTIFICATION_ONLY, '
        'since call-mode has its own much tighter legacy fallback (see the '
        "'expires_at' group below)", () {
      final now = DateTime.parse('2026-08-30T12:10:00Z');
      final result = parseRingDetectedPush(
        _validPayload(
          presentationIntent: 'NOTIFICATION_ONLY',
          occurredAt: '2026-08-30T12:00:00Z',
        ),
        now: now,
        maxAge: const Duration(minutes: 15),
      );
      expect(result, isA<RingPushParsed>());
    });
  });

  group('expires_at (backend PR #27)', () {
    test('a future expires_at is accepted', () {
      final payload = _validPayload()..['expires_at'] = '2026-08-30T12:00:30Z';

      final result = parseRingDetectedPush(payload, now: _fixedNow);

      expect(result, isA<RingPushParsed>());
    });

    test('expires_at equal to now is rejected as expired', () {
      final payload = _validPayload()
        ..['expires_at'] = _fixedNow.toIso8601String();

      final result = parseRingDetectedPush(payload, now: _fixedNow);

      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.expired,
        ),
      );
    });

    test('a past expires_at is rejected as expired', () {
      final payload = _validPayload()..['expires_at'] = '2026-08-30T12:00:01Z';

      final result = parseRingDetectedPush(payload, now: _fixedNow);

      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.expired,
        ),
      );
    });

    test('a malformed expires_at is rejected', () {
      final payload = _validPayload()..['expires_at'] = 'not-a-timestamp';

      final result = parseRingDetectedPush(payload, now: _fixedNow);

      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.invalidExpiresAt,
        ),
      );
    });

    test('an expires_at without an explicit UTC (Z) marker is rejected', () {
      final payload = _validPayload()..['expires_at'] = '2026-08-30T12:00:30';

      final result = parseRingDetectedPush(payload, now: _fixedNow);

      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.invalidExpiresAt,
        ),
      );
    });

    test('expires_at encoded as a non-string value is rejected', () {
      final payload = _validPayload();
      payload['expires_at'] = 1234567890;

      final result = parseRingDetectedPush(payload, now: _fixedNow);

      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.invalidExpiresAt,
        ),
      );
    });

    test('expires_at earlier than occurred_at is rejected as incoherent', () {
      final payload = _validPayload(occurredAt: '2026-08-30T12:00:00Z')
        ..['expires_at'] = '2026-08-30T11:59:59Z';

      final result = parseRingDetectedPush(payload, now: _fixedNow);

      expect(
        result,
        isA<RingPushRejected>().having(
          (r) => r.reason,
          'reason',
          RingPushRejectionReason.invalidExpiresAt,
        ),
      );
    });

    test('expires_at is never enforced for RING_ENDED — a message '
        'announcing a call ended is honored even if its own transport TTL '
        'marker looks stale, rather than leaving a phantom call ringing', () {
      final payload = <String, dynamic>{
        'push_contract_version': '1',
        'event': 'RING_ENDED',
        'event_id': 'evt-abcdef0123456789abcdef0123456789',
        'device_id': 'ib-fedcba9876543210fedcba9876543210',
        'call_id': 'call-0123456789abcdef0123456789abcdef',
        'occurred_at': '2026-08-30T12:00:00Z',
        'expires_at': '2020-01-01T00:00:00Z', // absurdly expired, ignored
      };

      final result = parseRingDetectedPush(payload, now: _fixedNow);

      expect(result, isA<RingPushParsed>());
    });

    group('legacy fallback (no expires_at)', () {
      test('a call-mode RING_DETECTED many minutes old is rejected even '
          'within the generic maxAge window — the legacy fallback for calls '
          'is the ~60s ring-timeout, not the generic delivery-jitter '
          'allowance', () {
        final now = DateTime.parse('2026-08-30T12:05:00Z'); // 5 min later
        final result = parseRingDetectedPush(
          _validPayload(
            presentationIntent: 'RING_ONLY',
            occurredAt: '2026-08-30T12:00:00Z',
          ),
          now: now,
          maxAge: const Duration(minutes: 15),
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

      test('a call-mode RING_DETECTED just inside 60s is still accepted', () {
        final now = DateTime.parse('2026-08-30T12:00:59Z');
        final result = parseRingDetectedPush(
          _validPayload(
            presentationIntent: 'RING_ONLY',
            occurredAt: '2026-08-30T12:00:00Z',
          ),
          now: now,
        );

        expect(result, isA<RingPushParsed>());
      });

      test('RING_AND_NOTIFICATION (legacy call mode) is bound by the same '
          '60s fallback as RING_ONLY', () {
        final now = DateTime.parse('2026-08-30T12:05:00Z');
        final result = parseRingDetectedPush(
          _validPayload(
            presentationIntent: 'RING_AND_NOTIFICATION',
            occurredAt: '2026-08-30T12:00:00Z',
          ),
          now: now,
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

      test('NOTIFICATION_ONLY without expires_at keeps using the generic, '
          'more lenient maxAge — it is not a call, so it is not bound by the '
          'ring-timeout fallback', () {
        final now = DateTime.parse('2026-08-30T12:05:00Z'); // 5 min later
        final result = parseRingDetectedPush(
          _validPayload(
            presentationIntent: 'NOTIFICATION_ONLY',
            occurredAt: '2026-08-30T12:00:00Z',
          ),
          now: now,
          maxAge: const Duration(minutes: 15),
        );

        expect(result, isA<RingPushParsed>());
      });
    });

    test('the exact shape backend PR #27 sends (occurred_at + expires_at + '
        'call_id) is accepted end to end', () {
      final payload = _validPayload(occurredAt: '2026-08-30T12:00:00Z')
        ..['call_id'] = 'call-0123456789abcdef0123456789abcdef'
        ..['expires_at'] = '2026-08-30T12:00:30Z';

      final result = parseRingDetectedPush(payload, now: _fixedNow);

      expect(result, isA<RingPushParsed>());
      final event = (result as RingPushParsed).event as RingDetectedEvent;
      expect(event.callId, 'call-0123456789abcdef0123456789abcdef');
    });
  });
}
