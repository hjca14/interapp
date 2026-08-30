import 'ring_detected_event.dart';
import 'ring_detected_push_parser.dart';
import 'ring_event_deduplicator.dart';
import 'ring_push_diagnostic.dart';

/// Narrow seam for actually showing the local notification for a validated
/// [RingDetectedEvent]. Implemented by
/// `IncomingCallNotificationService` (reused, not duplicated) in both the
/// main isolate (foreground) and a fresh instance built inside the
/// background isolate handler.
abstract interface class RingNotificationPresenter {
  Future<void> present(RingDetectedEvent event);
}

/// The single place that parses, dedupes, and presents a `RING_DETECTED`
/// push — shared by the foreground listener
/// (`PushNotificationService`) and the top-level background isolate handler
/// (`firebaseMessagingBackgroundHandler`) so neither duplicates the other's
/// parsing/channel/composition logic.
///
/// Never throws: every failure (parse rejection, dedup, or a presentation
/// error) is swallowed and reported only through [onDiagnostic], which the
/// caller should log — sanitized by construction — behind a debug-only
/// gate. [path] identifies which caller this is (`foreground` or
/// `background_handler`) for that diagnostic.
Future<void> presentRingDetectedPush({
  required Map<String, dynamic> data,
  required RingNotificationPresenter presenter,
  required RingEventDeduplicator deduplicator,
  required String path,
  required void Function(RingPushDiagnostic diagnostic) onDiagnostic,
  DateTime? now,
}) async {
  try {
    final result = parseRingDetectedPush(data, now: now);
    switch (result) {
      case RingPushRejected(:final reason):
        onDiagnostic(RingPushDiagnostic.rejected(path, reason));
        return;
      case RingPushParsed(:final event):
        final isNew = await deduplicator.shouldPresent(event.eventId);
        if (!isNew) {
          onDiagnostic(RingPushDiagnostic.duplicate(path, event));
          return;
        }
        try {
          await presenter.present(event);
          onDiagnostic(RingPushDiagnostic.presented(path, event));
        } on Object {
          onDiagnostic(RingPushDiagnostic.presentationFailed(path, event));
        }
    }
  } on Object {
    // Sanitized on purpose: a broken deduplicator (storage failure, etc.)
    // must not crash the caller — foreground listener or background
    // isolate alike.
    onDiagnostic(RingPushDiagnostic.internalError(path));
  }
}
