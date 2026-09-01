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
  timestampTooOld,
  invalidExpiresAt,
  expired;

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
    RingPushRejectionReason.invalidExpiresAt => 'invalid_expires_at',
    RingPushRejectionReason.expired => 'expired',
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

/// Conservative fallback ceiling for a legacy `RING_DETECTED` (no
/// `expires_at`) that is call-mode (`RING_ONLY`/`RING_AND_NOTIFICATION`) —
/// see [parseRingDetectedPush]'s doc for why this is much tighter than the
/// generic [maxAge] used for everything else.
const _legacyCallFallbackMaxAge = Duration(seconds: 60);

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
/// because pipeline/delivery jitter is expected. It is an outer safety net
/// applied to `occurred_at` for every event regardless of `expires_at`.
///
/// `call_id` is optional on `RING_DETECTED` for backward compatibility with
/// a backend that has not deployed it yet — see [RingPushEvent.callId]'s doc
/// for the degrade. It is required on `RING_ENDED`, which is meaningless
/// without one.
///
/// `expires_at` (backend PR #27 — deployed): an optional UTC ISO-8601
/// timestamp, checked **only for `RING_DETECTED`** (a `RING_ENDED` is
/// honored regardless of its own transport staleness — better to over-
/// cancel a call than leave a phantom one ringing because the message
/// announcing its end arrived "late"). When present, it must be a
/// well-formed UTC timestamp no earlier than `occurred_at`, and the event is
/// rejected (`expired`) once `now >= expires_at`. When absent (a push from
/// before backend PR #27, or `RING_ENDED`, which never carries it in this
/// contract), `RING_DETECTED` falls back to [maxAge] for `NOTIFICATION_ONLY`
/// but to the much tighter [_legacyCallFallbackMaxAge] (60s, matching
/// `RingCallNavigationCoordinator`'s own ring-timeout) for call-mode
/// (`RING_ONLY`/`RING_AND_NOTIFICATION`) — a several-minutes-old push must
/// never start a call ringing just because it arrived within the generic
/// delivery-jitter allowance. This fallback only governs whether this
/// function accepts the event at all; it never needs to be threaded further
/// into `RingCallIntent`/`RingCallLaunchPayload.kt`, which already derive
/// their own expiry safely from `occurred_at` and the same 60s window.
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
    reference: reference,
    maxAge: maxAge,
  );
}

RingPushParseResult _parseRingDetected(
  Map<String, dynamic> data, {
  required String eventId,
  required String deviceId,
  required DateTime occurredAt,
  required DateTime reference,
  required Duration maxAge,
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

  final rawExpiresAt = data['expires_at'];
  if (rawExpiresAt != null) {
    if (rawExpiresAt is! String) {
      return const RingPushRejected(RingPushRejectionReason.invalidExpiresAt);
    }
    final expiresAt = _parseUtcTimestamp(rawExpiresAt);
    if (expiresAt == null || expiresAt.isBefore(occurredAt)) {
      return const RingPushRejected(RingPushRejectionReason.invalidExpiresAt);
    }
    if (!reference.isBefore(expiresAt)) {
      return const RingPushRejected(RingPushRejectionReason.expired);
    }
  } else if (intent.isCall &&
      reference.difference(occurredAt) > _legacyCallFallbackMaxAge) {
    // Legacy push (no expires_at yet) requesting the call experience —
    // see the function-level doc for why this needs a much tighter
    // fallback than the generic [maxAge] used elsewhere.
    return const RingPushRejected(RingPushRejectionReason.timestampTooOld);
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
