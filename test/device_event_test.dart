import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/protocol/protocol_constants.dart';
import 'package:interapp/features/devices/domain/entities/device_event.dart';

void main() {
  group('DeviceEvent.fromJson', () {
    test('parses the protocol\'s example event envelope', () {
      final event = DeviceEvent.fromJson(const {
        'protocol_version': 1,
        'device_id': 'ib-7f3a91c2',
        'event_id': 'evt-12345',
        'event': 'RING_DETECTED',
        'timestamp': '2026-08-11T17:30:25Z',
        'uptime_ms': 123456,
      });

      expect(event.eventId, 'evt-12345');
      expect(event.deviceId, 'ib-7f3a91c2');
      expect(event.type, DeviceEventType.ringDetected);
      expect(event.rawType, 'RING_DETECTED');
      expect(event.timestamp, DateTime.parse('2026-08-11T17:30:25Z'));
      expect(event.uptime, const Duration(milliseconds: 123456));
    });

    test(
      'an unrecognized event name becomes unknown but keeps the raw string',
      () {
        final event = DeviceEvent.fromJson(const {
          'device_id': 'ib-1',
          'event_id': 'evt-1',
          'event': 'SOME_FUTURE_EVENT',
        });

        expect(event.type, DeviceEventType.unknown);
        expect(event.rawType, 'SOME_FUTURE_EVENT');
      },
    );

    test('timestamp and uptime are optional', () {
      final event = DeviceEvent.fromJson(const {
        'device_id': 'ib-1',
        'event_id': 'evt-1',
        'event': 'RING_DETECTED',
      });

      expect(event.timestamp, isNull);
      expect(event.uptime, isNull);
    });

    test('tolerates unknown extra fields', () {
      final event = DeviceEvent.fromJson(const {
        'device_id': 'ib-1',
        'event_id': 'evt-1',
        'event': 'RING_DETECTED',
        'some_future_field': 42,
      });

      expect(event.type, DeviceEventType.ringDetected);
    });

    test(
      'throws UnsupportedProtocolVersionException for a future protocol version',
      () {
        expect(
          () => DeviceEvent.fromJson(const {
            'protocol_version': 2,
            'device_id': 'ib-1',
            'event_id': 'evt-1',
            'event': 'RING_DETECTED',
          }),
          throwsA(isA<UnsupportedProtocolVersionException>()),
        );
      },
    );

    test('does not require protocol_version to be present', () {
      expect(
        () => DeviceEvent.fromJson(const {
          'device_id': 'ib-1',
          'event_id': 'evt-1',
          'event': 'RING_DETECTED',
        }),
        returnsNormally,
      );
    });
  });

  group('dedupeDeviceEvents', () {
    DeviceEvent event(String eventId, DeviceEventType type) {
      return DeviceEvent(
        eventId: eventId,
        deviceId: 'ib-1',
        type: type,
        rawType: type.name,
      );
    }

    test(
      'keeps the first occurrence of each event_id and drops later duplicates',
      () {
        final deduped = dedupeDeviceEvents([
          event('evt-1', DeviceEventType.ringDetected),
          event('evt-2', DeviceEventType.doorOpened),
          event('evt-1', DeviceEventType.ringDetected),
        ]);

        expect(deduped.map((e) => e.eventId), ['evt-1', 'evt-2']);
      },
    );

    test('an empty list stays empty', () {
      expect(dedupeDeviceEvents(const []), isEmpty);
    });
  });
}
