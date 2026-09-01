import 'ring_call_tombstone.dart';
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
/// Never throws: every failure (parse rejection, dedup, tombstone I/O, or a
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
///
/// [tombstones] closes a different gap than the deduplicator: FCM delivery
/// and the separate background isolate give no guarantee that
/// `RING_DETECTED(call_id=X)` is processed before its own later
/// `RING_ENDED(call_id=X)` — the two have different `event_id`s and can
/// travel through different paths. A `RING_ENDED` durably marks its
/// `call_id` ended *before* this function ever cancels/ends anything for
/// it, so that a `RING_DETECTED` for the same `call_id` processed
/// afterward — however it arrives, on however this isolate started — sees
/// the tombstone and is suppressed: it never reaches
/// [RingNotificationPresenter.present], so no notification, ringtone,
/// full-screen intent, or navigation happens for a call already known to be
/// over. A `RING_DETECTED` for any other `call_id` is unaffected.
Future<void> presentRingDetectedPush({
  required Map<String, dynamic> data,
  required RingNotificationPresenter presenter,
  required RingEventDeduplicator deduplicator,
  required RingCallTombstoneStore tombstones,
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
        if (event case RingDetectedEvent()) {
          // Checked before the dedup reservation: a suppressed start should
          // never consume/hold a reservation slot for its event_id — a
          // harmless, safe-to-retry no-op either way, but simpler to reason
          // about this way.
          //
          // Guarded locally, not left to the outer catch: [tombstones] is an
          // injected interface, and this function — not any one concrete
          // implementation — is what guarantees a failing [isEnded] fails
          // *open* (presents normally) rather than the outer catch's
          // fail-closed `internalError` (which would suppress every call
          // for the rest of this invocation whenever the store hiccups).
          var isEnded = false;
          try {
            isEnded = await tombstones.isEnded(event.callId);
          } on Object {
            isEnded = false;
          }
          if (isEnded) {
            onDiagnostic(
              RingPushDiagnostic.suppressedAlreadyEnded(path, event),
            );
            return;
          }
        }

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
              // Durably recorded before the (best-effort, local-only)
              // notification/UI cancellation — see the function doc.
              // Never undone even if the cancellation below throws: the
              // call *is* over regardless of whether cleanup succeeded, and
              // the dedup release path a few lines down only retries the
              // cancellation, not this fact.
              await tombstones.markEnded(event.callId, at: event.occurredAt);
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
    // Sanitized on purpose: a broken deduplicator/tombstone store (storage
    // failure, etc.) must not crash the caller — foreground listener or
    // background isolate alike.
    onDiagnostic(RingPushDiagnostic.internalError(path));
  }
}
