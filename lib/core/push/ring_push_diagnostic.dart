import 'ring_detected_event.dart';
import 'ring_detected_push_parser.dart';

/// A minimal, sanitized record of one `RING_DETECTED`/`RING_ENDED` push
/// handling attempt — safe to log. Never carries the raw payload, a full
/// `event_id`/`device_id`/`call_id`, a token, or a user id.
final class RingPushDiagnostic {
  const RingPushDiagnostic._({
    required this.path,
    required this.maskedEventId,
    required this.contractValid,
    required this.eventName,
    required this.presentationIntent,
    required this.presented,
    required this.reason,
  });

  factory RingPushDiagnostic.presented(String path, RingPushEvent event) {
    return RingPushDiagnostic._(
      path: path,
      maskedEventId: _mask(event.eventId),
      contractValid: true,
      eventName: _eventName(event),
      presentationIntent: switch (event) {
        RingDetectedEvent(:final presentationIntent) => presentationIntent,
        RingEndedEvent() => null,
      },
      presented: true,
      reason: 'presented',
    );
  }

  factory RingPushDiagnostic.duplicate(String path, RingPushEvent event) {
    return RingPushDiagnostic._(
      path: path,
      maskedEventId: _mask(event.eventId),
      contractValid: true,
      eventName: _eventName(event),
      presentationIntent: switch (event) {
        RingDetectedEvent(:final presentationIntent) => presentationIntent,
        RingEndedEvent() => null,
      },
      presented: false,
      reason: 'duplicate_event_id',
    );
  }

  factory RingPushDiagnostic.presentationFailed(
    String path,
    RingPushEvent event,
  ) {
    return RingPushDiagnostic._(
      path: path,
      maskedEventId: _mask(event.eventId),
      contractValid: true,
      eventName: _eventName(event),
      presentationIntent: switch (event) {
        RingDetectedEvent(:final presentationIntent) => presentationIntent,
        RingEndedEvent() => null,
      },
      presented: false,
      reason: 'presentation_failed',
    );
  }

  /// A `RING_DETECTED` whose `call_id` was already durably marked ended —
  /// its `RING_ENDED` was processed first (no ordering guarantee between
  /// FCM deliveries/isolates). See `RingCallTombstoneStore`. Never reaches
  /// [RingNotificationPresenter.present]: no notification, no ringtone, no
  /// full-screen intent, no navigation.
  factory RingPushDiagnostic.suppressedAlreadyEnded(
    String path,
    RingDetectedEvent event,
  ) {
    return RingPushDiagnostic._(
      path: path,
      maskedEventId: _mask(event.eventId),
      contractValid: true,
      eventName: _eventName(event),
      presentationIntent: event.presentationIntent,
      presented: false,
      reason: 'start_suppressed_already_ended',
    );
  }

  factory RingPushDiagnostic.rejected(
    String path,
    RingPushRejectionReason reason,
  ) {
    return RingPushDiagnostic._(
      path: path,
      maskedEventId: null,
      contractValid: false,
      eventName: null,
      presentationIntent: null,
      presented: false,
      reason: reason.wireCode,
    );
  }

  /// An unexpected failure outside parsing/presentation itself (e.g. the
  /// deduplicator's storage backend). Always sanitized the same way as
  /// every other outcome here — no payload, no exception message.
  factory RingPushDiagnostic.internalError(String path) {
    return RingPushDiagnostic._(
      path: path,
      maskedEventId: null,
      contractValid: false,
      eventName: null,
      presentationIntent: null,
      presented: false,
      reason: 'internal_error',
    );
  }

  /// `foreground` | `background_handler`.
  final String path;
  final String? maskedEventId;
  final bool contractValid;

  /// `RING_DETECTED` | `RING_ENDED`, or `null` when [contractValid] is
  /// `false` (nothing was successfully parsed to name).
  final String? eventName;
  final RingPresentationIntent? presentationIntent;
  final bool presented;
  final String reason;

  /// A single-line, debug-only diagnostic string. Callers still must gate
  /// this behind `kDebugMode`/an equivalent flag — this class only ensures
  /// the *content* is sanitized, not where it gets printed.
  String toLogLine() {
    return '[RING][DEBUG-ONLY] $path '
        'event_id=${maskedEventId ?? '-'} '
        'contract_valid=$contractValid '
        'event=${eventName ?? '-'} '
        'presentation_intent=${presentationIntent?.name ?? '-'} '
        'apresentado=$presented '
        'motivo=$reason';
  }

  static String _eventName(RingPushEvent event) => switch (event) {
    RingDetectedEvent() => 'RING_DETECTED',
    RingEndedEvent() => 'RING_ENDED',
  };

  /// Shows only the last 4 hex characters of `evt-<32 hex>`, matching the
  /// masking style used elsewhere for short-lived codes
  /// (`SetupCode.maskedForLogging`).
  static String _mask(String eventId) {
    if (eventId.length <= 4) {
      return eventId;
    }
    final visible = eventId.substring(eventId.length - 4);
    final hidden = ''.padLeft(eventId.length - 4, '•');
    return '$hidden$visible';
  }
}
