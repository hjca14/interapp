import 'ring_detected_event.dart';
import 'ring_detected_push_parser.dart';

/// A minimal, sanitized record of one `RING_DETECTED` push handling
/// attempt — safe to log. Never carries the raw payload, a full
/// `event_id`/`device_id`, a token, or a user id.
final class RingPushDiagnostic {
  const RingPushDiagnostic._({
    required this.path,
    required this.maskedEventId,
    required this.contractValid,
    required this.presentationIntent,
    required this.presented,
    required this.reason,
  });

  factory RingPushDiagnostic.presented(String path, RingDetectedEvent event) {
    return RingPushDiagnostic._(
      path: path,
      maskedEventId: _mask(event.eventId),
      contractValid: true,
      presentationIntent: event.presentationIntent,
      presented: true,
      reason: 'presented',
    );
  }

  factory RingPushDiagnostic.duplicate(String path, RingDetectedEvent event) {
    return RingPushDiagnostic._(
      path: path,
      maskedEventId: _mask(event.eventId),
      contractValid: true,
      presentationIntent: event.presentationIntent,
      presented: false,
      reason: 'duplicate_event_id',
    );
  }

  factory RingPushDiagnostic.presentationFailed(
    String path,
    RingDetectedEvent event,
  ) {
    return RingPushDiagnostic._(
      path: path,
      maskedEventId: _mask(event.eventId),
      contractValid: true,
      presentationIntent: event.presentationIntent,
      presented: false,
      reason: 'presentation_failed',
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
      presentationIntent: null,
      presented: false,
      reason: 'internal_error',
    );
  }

  /// `foreground` | `background_handler`.
  final String path;
  final String? maskedEventId;
  final bool contractValid;
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
        'event=${contractValid ? 'RING_DETECTED' : '-'} '
        'presentation_intent=${presentationIntent?.name ?? '-'} '
        'apresentado=$presented '
        'motivo=$reason';
  }

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
