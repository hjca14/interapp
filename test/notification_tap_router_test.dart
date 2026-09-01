import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/core/push/notification_tap_diagnostic.dart';
import 'package:interapp/core/push/notification_tap_router.dart';
import 'package:interapp/core/push/ring_call_intent.dart';

void main() {
  // routeNotificationTap has no injectable clock (it calls
  // RingCallIntent.tryRestore with the real wall clock), so a "valid"
  // fixture here must be fresh relative to DateTime.now(), not a fixed
  // historical timestamp — otherwise it would already be past the 60s
  // ring-timeout window by the time this test runs.
  final validCallPayload = RingCallIntent(
    eventId: 'evt-${List.filled(32, 'a').join()}',
    callId: 'call-${List.filled(32, 'c').join()}',
    deviceId: 'ib-${List.filled(32, 'b').join()}',
    occurredAt: DateTime.now().toUtc(),
  ).serialize();

  final expiredButShapedCallPayload = jsonEncode({
    'v': 2,
    'event_id': 'evt-${List.filled(32, 'a').join()}',
    'call_id': 'call-${List.filled(32, 'c').join()}',
    'device_id': 'ib-${List.filled(32, 'b').join()}',
    'occurred_at': DateTime.utc(2000).toIso8601String(),
  });

  test('a valid payload (RING_ONLY or NOTIFICATION_ONLY — both share the same '
      'RingCallIntent shape) calls onCallTap and reports callAccepted', () {
    String? tapped;
    NotificationTapDiagnostic? diagnostic;
    routeNotificationTap(
      validCallPayload,
      onCallTap: (payload) => tapped = payload,
      onInvalidCallTap: () => fail('must not reach invalid-call recovery'),
      onDiagnostic: (value) => diagnostic = value,
    );

    expect(tapped, validCallPayload);
    expect(diagnostic?.reason, 'call_accepted');
  });

  test('a shaped-but-expired payload calls onInvalidCallTap and reports '
      'callRejected, never onCallTap', () {
    var invalidCallTapCalled = false;
    NotificationTapDiagnostic? diagnostic;
    routeNotificationTap(
      expiredButShapedCallPayload,
      onCallTap: (_) => fail('must not reach onCallTap'),
      onInvalidCallTap: () => invalidCallTapCalled = true,
      onDiagnostic: (value) => diagnostic = value,
    );

    expect(invalidCallTapCalled, isTrue);
    expect(diagnostic?.reason, 'call_rejected');
  });

  test('a payload matching neither shape calls nothing and reports no '
      'diagnostic', () {
    var anyCallbackCalled = false;
    routeNotificationTap(
      '{"unexpected":"shape"}',
      onCallTap: (_) => anyCallbackCalled = true,
      onInvalidCallTap: () => anyCallbackCalled = true,
      onDiagnostic: (_) => anyCallbackCalled = true,
    );

    expect(anyCallbackCalled, isFalse);
  });

  test('a null payload calls nothing', () {
    var anyCallbackCalled = false;
    routeNotificationTap(
      null,
      onCallTap: (_) => anyCallbackCalled = true,
      onInvalidCallTap: () => anyCallbackCalled = true,
      onDiagnostic: (_) => anyCallbackCalled = true,
    );

    expect(anyCallbackCalled, isFalse);
  });

  test('onInvalidCallTap/onDiagnostic are optional — a shaped-but-expired call '
      'payload with neither supplied does not throw', () {
    expect(
      () => routeNotificationTap(
        expiredButShapedCallPayload,
        onCallTap: (_) => fail('must not reach onCallTap'),
      ),
      returnsNormally,
    );
  });

  group('looksLikeRingCallPayload', () {
    test('true for the exact RingCallIntent envelope shape, valid or not', () {
      expect(looksLikeRingCallPayload(validCallPayload), isTrue);
      expect(looksLikeRingCallPayload(expiredButShapedCallPayload), isTrue);
    });

    test('false for malformed JSON, an unrelated shape, or null', () {
      expect(looksLikeRingCallPayload('{"unexpected":"shape"}'), isFalse);
      expect(looksLikeRingCallPayload('{bad'), isFalse);
      expect(looksLikeRingCallPayload(null), isFalse);
    });
  });

  test(
    'diagnostic reasons never contain a device_id, event_id, or call_id',
    () {
      final reasons = [
        NotificationTapDiagnostic.callAccepted().reason,
        NotificationTapDiagnostic.callRejected().reason,
      ];

      for (final reason in reasons) {
        expect(reason, isNot(contains('ib-')));
        expect(reason, isNot(contains('evt-')));
        expect(reason, isNot(contains('call-')));
      }
    },
  );
}
