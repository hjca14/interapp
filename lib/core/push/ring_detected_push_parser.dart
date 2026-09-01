import 'ring_detected_event.dart';

/// Why a `RING_DETECTED`/`RING_ENDED` push payload was rejected. Safe to log
/// by itself — it never carries any part of the payload.
enum RingPushRejectionReason {
  missingField,
  unsupportedContractVersion,
  unsupportedEvent,
  invalidEventId,
  invalidDeviceId,
  invalidCallId,
  invalidPresentationIntent,
  invalidTimestamp,
  timestampTooOld;

  /// Short snake_case code for diagnostics, e.g. `missing_field`.
  String get wireCode => switch (this) {
    RingPushRejectionReason.missingField => 'missing_field',
    RingPushRejectionReason.unsupportedContractVersion =>
      'unsupported_contract_version',
    RingPushRejectionReason.unsupportedEvent => 'unsupported_event',
    RingPushRejectionReason.invalidEventId => 'invalid_event_id',
    RingPushRejectionReason.invalidDeviceId => 'invalid_device_id',
    RingPushRejectionReason.invalidCallId => 'invalid_call_id',
    RingPushRejectionReason.invalidPresentationIntent =>
      'invalid_presentation_intent',
    RingPushRejectionReason.invalidTimestamp => 'invalid_timestamp',
    RingPushRejectionReason.timestampTooOld => 'timestamp_too_old',
  };
}

/// Outcome of [parseRingDetectedPush]. Pattern-match with `switch` — see
/// callers in `ring_detected_presenter.dart`.
sealed class RingPushParseResult {
  const RingPushParseResult();
}

final class RingPushParsed extends RingPushParseResult {
  const RingPushParsed(this.event);

  final RingPushEvent event;
}

final class RingPushRejected extends RingPushParseResult {
  const RingPushRejected(this.reason);

  final RingPushRejectionReason reason;
}

const _contractVersion = '1';
const _ringDetected = 'RING_DETECTED';
const _ringEnded = 'RING_ENDED';
final _eventIdPattern = RegExp(r'^evt-[0-9a-f]{32}$');
final _deviceIdPattern = RegExp(r'^ib-[0-9a-f]{32}$');
final _callIdPattern = RegExp(r'^call-[0-9a-f]{32}$');

const _commonRequiredFields = [
  'push_contract_version',
  'event_id',
  'device_id',
  'event',
  'occurred_at',
];

/// Strictly validates a `RING_DETECTED`/`RING_ENDED` push contract v1
/// payload (`RemoteMessage.data`) into a typed [RingPushEvent], or a
/// sanitized [RingPushRejected] reason. Pure and Firebase-free — takes a
/// plain map so it is trivially unit-testable and reusable from both the
/// foreground listener and the background isolate handler.
///
/// [now] defaults to [DateTime.now] in UTC; overridable for tests. [maxAge]
/// guards against stale/clock-skewed events reaching the user — it is
/// deliberately more generous than the backend's ~30s FCM delivery TTL
/// (used instead for local dedup, see `ring_event_deduplicator.dart`)
/// because pipeline/delivery jitter is expected. It bounds message
/// *delivery* staleness only; how long a call keeps ringing once accepted is
/// `RingCallNavigationCoordinator`'s separate, much shorter ring-timeout
/// concern.
///
/// `call_id` is optional on `RING_DETECTED` for backward compatibility with
/// a backend that has not deployed it yet — see [RingPushEvent.callId]'s doc
/// for the degrade. It is required on `RING_ENDED`, which is meaningless
/// without one. **Expected backend contract** (new, not yet deployed): an
/// optional `call_id` matching `^call-[0-9a-f]{32}$` on `RING_DETECTED`, and
/// a `RING_ENDED` message shaped like `RING_DETECTED` but without
/// `presentation_intent` and with `call_id` required.
RingPushParseResult parseRingDetectedPush(
  Map<String, dynamic> data, {
  DateTime? now,
  Duration maxAge = const Duration(minutes: 15),
}) {
  for (final field in _commonRequiredFields) {
    if (data[field] is! String) {
      return const RingPushRejected(RingPushRejectionReason.missingField);
    }
  }

  if (data['push_contract_version'] != _contractVersion) {
    return const RingPushRejected(
      RingPushRejectionReason.unsupportedContractVersion,
    );
  }

  final eventName = data['event'] as String;
  if (eventName != _ringDetected && eventName != _ringEnded) {
    return const RingPushRejected(RingPushRejectionReason.unsupportedEvent);
  }

  final eventId = data['event_id'] as String;
  if (!_eventIdPattern.hasMatch(eventId)) {
    return const RingPushRejected(RingPushRejectionReason.invalidEventId);
  }

  final deviceId = data['device_id'] as String;
  if (!_deviceIdPattern.hasMatch(deviceId)) {
    return const RingPushRejected(RingPushRejectionReason.invalidDeviceId);
  }

  final occurredAtRaw = data['occurred_at'] as String;
  final occurredAt = _parseUtcTimestamp(occurredAtRaw);
  if (occurredAt == null) {
    return const RingPushRejected(RingPushRejectionReason.invalidTimestamp);
  }

  final reference = (now ?? DateTime.now()).toUtc();
  if (reference.difference(occurredAt) > maxAge) {
    return const RingPushRejected(RingPushRejectionReason.timestampTooOld);
  }

  if (eventName == _ringEnded) {
    return _parseRingEnded(
      data,
      eventId: eventId,
      deviceId: deviceId,
      occurredAt: occurredAt,
    );
  }
  return _parseRingDetected(
    data,
    eventId: eventId,
    deviceId: deviceId,
    occurredAt: occurredAt,
  );
}

RingPushParseResult _parseRingDetected(
  Map<String, dynamic> data, {
  required String eventId,
  required String deviceId,
  required DateTime occurredAt,
}) {
  if (data['presentation_intent'] is! String) {
    return const RingPushRejected(RingPushRejectionReason.missingField);
  }
  final intent = _parsePresentationIntent(
    data['presentation_intent'] as String,
  );
  if (intent == null) {
    return const RingPushRejected(
      RingPushRejectionReason.invalidPresentationIntent,
    );
  }

  final rawCallId = data['call_id'];
  if (rawCallId != null &&
      (rawCallId is! String || !_callIdPattern.hasMatch(rawCallId))) {
    return const RingPushRejected(RingPushRejectionReason.invalidCallId);
  }

  return RingPushParsed(
    RingDetectedEvent(
      eventId: eventId,
      deviceId: deviceId,
      presentationIntent: intent,
      occurredAt: occurredAt,
      callId: rawCallId as String?,
    ),
  );
}

RingPushParseResult _parseRingEnded(
  Map<String, dynamic> data, {
  required String eventId,
  required String deviceId,
  required DateTime occurredAt,
}) {
  if (data['call_id'] is! String) {
    return const RingPushRejected(RingPushRejectionReason.missingField);
  }
  final callId = data['call_id'] as String;
  if (!_callIdPattern.hasMatch(callId)) {
    return const RingPushRejected(RingPushRejectionReason.invalidCallId);
  }

  return RingPushParsed(
    RingEndedEvent(
      eventId: eventId,
      callId: callId,
      deviceId: deviceId,
      occurredAt: occurredAt,
    ),
  );
}

RingPresentationIntent? _parsePresentationIntent(String raw) => switch (raw) {
  'RING_ONLY' => RingPresentationIntent.ringOnly,
  'NOTIFICATION_ONLY' => RingPresentationIntent.notificationOnly,
  'RING_AND_NOTIFICATION' => RingPresentationIntent.ringAndNotification,
  _ => null,
};

/// Requires an explicit `Z` suffix (strict UTC) rather than relying on
/// [DateTime.parse]'s more permissive offset handling.
DateTime? _parseUtcTimestamp(String raw) {
  if (!raw.endsWith('Z')) {
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || !parsed.isUtc) {
    return null;
  }
  return parsed;
}
