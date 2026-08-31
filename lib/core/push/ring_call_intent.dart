import 'dart:convert';

import 'ring_detected_event.dart';
import 'ring_detected_push_parser.dart';

/// The deliberately small context attached to a local ring notification.
///
/// It can reconstruct the already-typed ring event, but contains none of the
/// original FCM payload, remote copy, token, or other transport metadata.
final class RingCallIntent {
  const RingCallIntent({
    required this.eventId,
    required this.deviceId,
    required this.occurredAt,
  });

  final String eventId;
  final String deviceId;
  final DateTime occurredAt;

  factory RingCallIntent.fromEvent(RingDetectedEvent event) => RingCallIntent(
    eventId: event.eventId,
    deviceId: event.deviceId,
    occurredAt: event.occurredAt,
  );

  String serialize() => jsonEncode({
    'v': 1,
    'event_id': eventId,
    'device_id': deviceId,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
  });

  /// Restores through the strict v1 push parser so persisted notification
  /// context never becomes a less-validated path into navigation.
  static RingCallIntent? tryRestore(
    String? encoded, {
    DateTime? now,
    Duration maxAge = const Duration(minutes: 15),
  }) {
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 4 ||
          decoded['v'] != 1) {
        return null;
      }
      final result = parseRingDetectedPush(
        {
          'push_contract_version': '1',
          'event_id': decoded['event_id'],
          'device_id': decoded['device_id'],
          'event': 'RING_DETECTED',
          'presentation_intent': 'NOTIFICATION_ONLY',
          'occurred_at': decoded['occurred_at'],
        },
        now: now,
        maxAge: maxAge,
      );
      return switch (result) {
        RingPushParsed(:final event) => RingCallIntent.fromEvent(event),
        RingPushRejected() => null,
      };
    } on Object {
      return null;
    }
  }
}

/// Stable across processes, unlike Dart's runtime [String.hashCode].
int ringNotificationId(String eventId) {
  var hash = 0x811c9dc5;
  for (final unit in eventId.codeUnits) {
    hash = (hash ^ unit) * 0x01000193 & 0x7fffffff;
  }
  return hash;
}
