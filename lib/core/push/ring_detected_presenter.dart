import 'ring_detected_event.dart';
import 'ring_detected_push_parser.dart';
import 'ring_event_deduplicator.dart';
import 'ring_push_diagnostic.dart';

/// Narrow seam for actually showing/ending the local notification for a
/// validated push. Implemented by `IncomingCallNotificationService` (reused,
/// not duplicated) in both the main isolate (foreground) and a fresh
/// instance built inside the background isolate handler.
abstract interface class RingNotificationPresenter {
  Future<void> present(RingDetectedEvent event);

  /// Ends the call named by `event.callId` locally: cancels its
  /// notification/ringtone. A `RING_ENDED` for a call that is not currently
  /// showing (already dismissed, timed out, or never presented here) is a
  /// safe no-op — see `IncomingCallNotificationService.endCall`.
  Future<void> endCall(RingEndedEvent event);
}

/// The single place that parses, dedupes, and presents/ends a
/// `RING_DETECTED`/`RING_ENDED` push — shared by the foreground listener
/// (`PushNotificationService`) and the top-level background isolate handler
/// (`firebaseMessagingBackgroundHandler`) so neither duplicates the other's
/// parsing/channel/composition logic.
///
/// Never throws: every failure (parse rejection, dedup, or a
/// presentation/end error) is swallowed and reported only through
/// [onDiagnostic], which the caller should log — sanitized by construction —
/// behind a debug-only gate. [path] identifies which caller this is
/// (`foreground` or `background_handler`) for that diagnostic.
///
/// Deduplication is keyed by `event_id` for both event kinds — this both
/// smooths over FCM's at-least-once delivery (as before) and, for
/// `RING_ENDED`, makes a duplicate end delivery idempotent for free: a
/// second identical `RING_ENDED` is simply deduplicated away, never calling
/// [RingNotificationPresenter.endCall] twice.
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
        final isNew = await deduplicator.reserve(event.eventId);
        if (!isNew) {
          onDiagnostic(RingPushDiagnostic.duplicate(path, event));
          return;
        }
        try {
          switch (event) {
            case RingDetectedEvent():
              await presenter.present(event);
            case RingEndedEvent():
              await presenter.endCall(event);
          }
          onDiagnostic(RingPushDiagnostic.presented(path, event));
        } on Object {
          // The reservation above must not outlive a failed presentation —
          // nothing was actually shown/ended, so a legitimate retry within
          // the window must still be allowed through.
          await deduplicator.release(event.eventId);
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
