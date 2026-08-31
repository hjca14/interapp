import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/ring_detected_event.dart';
import 'package:interapp/core/push/ring_detected_push_parser.dart';
import 'package:interapp/core/push/ring_push_diagnostic.dart';

RingDetectedEvent _event({
  String eventId = 'evt-0123456789abcdef0123456789abcdef',
  String deviceId = 'ib-fedcba9876543210fedcba9876543210',
  RingPresentationIntent presentationIntent = RingPresentationIntent.ringOnly,
}) => RingDetectedEvent(
  eventId: eventId,
  deviceId: deviceId,
  presentationIntent: presentationIntent,
  occurredAt: DateTime.utc(2026, 8, 30),
);

void main() {
  test('presented() masks the event_id, keeping only the last 4 chars', () {
    final diagnostic = RingPushDiagnostic.presented('foreground', _event());

    expect(diagnostic.maskedEventId, isNot(contains('0123456789abcdef')));
    expect(diagnostic.maskedEventId, endsWith('cdef'));
    expect(diagnostic.presented, isTrue);
    expect(diagnostic.reason, 'presented');
  });

  test('rejected() never carries an event_id, since none was parsed', () {
    final diagnostic = RingPushDiagnostic.rejected(
      'background_handler',
      RingPushRejectionReason.invalidDeviceId,
    );

    expect(diagnostic.maskedEventId, isNull);
    expect(diagnostic.contractValid, isFalse);
    expect(diagnostic.reason, 'invalid_device_id');
  });

  test('toLogLine never includes the device_id at all', () {
    final diagnostic = RingPushDiagnostic.presented('foreground', _event());

    final line = diagnostic.toLogLine();

    expect(line, isNot(contains('fedcba9876543210fedcba9876543210')));
    expect(line, isNot(contains('ib-')));
  });

  test('internalError() is fully sanitized too', () {
    final diagnostic = RingPushDiagnostic.internalError('foreground');

    expect(diagnostic.maskedEventId, isNull);
    expect(diagnostic.contractValid, isFalse);
    expect(diagnostic.presented, isFalse);
    expect(diagnostic.reason, 'internal_error');
  });
}
