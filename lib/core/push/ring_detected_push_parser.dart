import 'ring_detected_event.dart';

/// Why a `RING_DETECTED` push payload was rejected. Safe to log by itself —
/// it never carries any part of the payload.
enum RingPushRejectionReason {
  missingField,
  unsupportedContractVersion,
  unsupportedEvent,
  invalidEventId,
  invalidDeviceId,
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

  final RingDetectedEvent event;
}

final class RingPushRejected extends RingPushParseResult {
  const RingPushRejected(this.reason);

  final RingPushRejectionReason reason;
}

const _contractVersion = '1';
const _supportedEvent = 'RING_DETECTED';
final _eventIdPattern = RegExp(r'^evt-[0-9a-f]{32}$');
final _deviceIdPattern = RegExp(r'^ib-[0-9a-f]{32}$');
const _requiredFields = [
  'push_contract_version',
  'event_id',
  'device_id',
  'event',
  'presentation_intent',
  'occurred_at',
];

/// Strictly validates a `RING_DETECTED` push contract v1 payload
/// (`RemoteMessage.data`) into a typed [RingDetectedEvent], or a sanitized
/// [RingPushRejected] reason. Pure and Firebase-free — takes a plain map so
/// it is trivially unit-testable and reusable from both the foreground
/// listener and the background isolate handler.
///
/// [now] defaults to [DateTime.now] in UTC; overridable for tests. [maxAge]
/// guards against stale/clock-skewed events reaching the user — it is
/// deliberately more generous than the backend's ~30s FCM delivery TTL
/// (used instead for local dedup, see `ring_event_deduplicator.dart`)
/// because pipeline/delivery jitter is expected.
RingPushParseResult parseRingDetectedPush(
  Map<String, dynamic> data, {
  DateTime? now,
  Duration maxAge = const Duration(minutes: 15),
}) {
  for (final field in _requiredFields) {
    if (data[field] is! String) {
      return const RingPushRejected(RingPushRejectionReason.missingField);
    }
  }

  if (data['push_contract_version'] != _contractVersion) {
    return const RingPushRejected(
      RingPushRejectionReason.unsupportedContractVersion,
    );
  }
  if (data['event'] != _supportedEvent) {
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

  final intent = _parsePresentationIntent(
    data['presentation_intent'] as String,
  );
  if (intent == null) {
    return const RingPushRejected(
      RingPushRejectionReason.invalidPresentationIntent,
    );
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

  return RingPushParsed(
    RingDetectedEvent(
      eventId: eventId,
      deviceId: deviceId,
      presentationIntent: intent,
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
