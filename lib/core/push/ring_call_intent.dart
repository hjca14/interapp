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
  /// context never becomes a less-validated path into navigation. Always
  /// synthesizes `presentation_intent: RING_ONLY` and never an
  /// `expires_at` — this represents a call-mode launch/tap, and carries no
  /// transport-level expiry of its own, so the parser's legacy call-mode
  /// fallback (a hard ~60s ceiling from `occurred_at`) always applies.
  ///
  /// [maxAge] defaults to the call ring-timeout (60s, matching
  /// `RingCallNavigationCoordinator`'s own default) and can only ever
  /// *tighten* that ceiling, never loosen it: a tapped call notification
  /// older than ~60s is not "still ringing" regardless of what created the
  /// delay or what a caller requests, so restoring it must fail the same as
  /// any other stale/foreign payload. See
  /// `ring_detected_push_parser.dart`'s doc comment for why call-mode
  /// events are bound to this tighter window instead of the generic,
  /// message-delivery-jitter `maxAge`.
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

/// Whether [encoded] has [RingCallIntent]'s JSON envelope shape (exact key
/// set, `v == 2`) regardless of whether its *content* would also pass
/// [RingCallIntent.tryRestore]'s full validation (id formats, freshness).
///
/// Lets a caller distinguish "this was a call notification's payload, which
/// just failed stricter validation" (e.g. tapped after its ~60s ring-timeout
/// window, or produced by a different app version) from "this payload was
/// never a call notification's to begin with" — see
/// `routeNotificationTap`'s safe-recovery path for a tap that falls into the
/// former case.
bool looksLikeRingCallPayload(String? encoded) {
  if (encoded == null) return false;
  try {
    final decoded = jsonDecode(encoded);
    return decoded is Map<String, dynamic> &&
        decoded.length == 5 &&
        decoded['v'] == 2 &&
        decoded.containsKey('event_id') &&
        decoded.containsKey('call_id') &&
        decoded.containsKey('device_id') &&
        decoded.containsKey('occurred_at');
  } on Object {
    return false;
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
