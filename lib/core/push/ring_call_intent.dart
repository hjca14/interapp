import 'dart:convert';

import 'ring_detected_event.dart';
import 'ring_detected_push_parser.dart';

/// The deliberately small context attached to a local ring notification.
///
/// It can reconstruct the already-typed ring event, but contains none of the
/// original FCM payload, remote copy, token, or other transport metadata.
///
/// Version `2` (bumped from `1` alongside this same change): adds [callId],
/// required so `MainActivity`'s native `RingCallLaunchPayload.kt` validator
/// and `RingCallNavigationCoordinator.endCall` can correlate this launch
/// with a later `RING_ENDED`. An already-shown v1 notification tapped after
/// an app update simply fails to restore (`tryRestore` returns `null`) — the
/// same safe degrade as any other malformed/foreign payload, never a crash.
final class RingCallIntent {
  const RingCallIntent({
    required this.eventId,
    required this.callId,
    required this.deviceId,
    required this.occurredAt,
  });

  final String eventId;
  final String callId;
  final String deviceId;
  final DateTime occurredAt;

  factory RingCallIntent.fromEvent(RingPushEvent event) => RingCallIntent(
    eventId: event.eventId,
    callId: event.callId,
    deviceId: event.deviceId,
    occurredAt: event.occurredAt,
  );

  String serialize() => jsonEncode({
    'v': 2,
    'event_id': eventId,
    'call_id': callId,
    'device_id': deviceId,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
  });

  /// Restores through the strict push parser so persisted notification
  /// context never becomes a less-validated path into navigation.
  ///
  /// [maxAge] defaults to the call ring-timeout (60s, matching
  /// `RingCallNavigationCoordinator`'s own default): a tapped call
  /// notification older than that is not "still ringing" regardless of
  /// what created the delay, so restoring it must fail the same as any
  /// other stale/foreign payload.
  static RingCallIntent? tryRestore(
    String? encoded, {
    DateTime? now,
    Duration maxAge = const Duration(seconds: 60),
  }) {
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 5 ||
          decoded['v'] != 2) {
        return null;
      }
      final result = parseRingDetectedPush(
        {
          'push_contract_version': '1',
          'event_id': decoded['event_id'],
          'call_id': decoded['call_id'],
          'device_id': decoded['device_id'],
          'event': 'RING_DETECTED',
          'presentation_intent': 'RING_ONLY',
          'occurred_at': decoded['occurred_at'],
        },
        now: now,
        maxAge: maxAge,
      );
      return switch (result) {
        RingPushParsed(event: final RingDetectedEvent event) =>
          RingCallIntent.fromEvent(event),
        RingPushParsed() || RingPushRejected() => null,
      };
    } on Object {
      return null;
    }
  }
}

/// Stable across processes, unlike Dart's runtime [String.hashCode].
///
/// Callers must pass a call's [RingPushEvent.callId], not its `event_id`: a
/// repeated `RING_DETECTED` for the same call must replace (not stack) the
/// existing notification, and `RING_ENDED`/the local ring-timeout must be
/// able to compute this same id from `call_id` alone to cancel it.
int ringNotificationId(String callId) {
  var hash = 0x811c9dc5;
  for (final unit in callId.codeUnits) {
    hash = (hash ^ unit) * 0x01000193 & 0x7fffffff;
  }
  return hash;
}
