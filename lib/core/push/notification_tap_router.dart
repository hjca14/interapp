import 'notification_tap_diagnostic.dart';
import 'ring_call_intent.dart';

/// Routes a tapped local notification's `payload` to [onCallTap].
///
/// Both `RING_ONLY` and `NOTIFICATION_ONLY` presentations share the same
/// [RingCallIntent] payload shape (see `IncomingCallNotificationService`'s
/// doc — both represent the same live call session, just presented
/// differently), so a single successful restore always means the same
/// thing: open `IncomingCallPage` for that call, exactly like a full-screen
/// launch or foreground presentation would.
///
/// A payload that has [RingCallIntent]'s envelope shape but fails its full
/// validation (expired past the ring-timeout, malformed, a foreign app
/// version) calls [onInvalidCallTap] — the caller's cue to safely recover:
/// cancel exactly the tapped notification, stop its ringtone, and undo any
/// lock-screen bypass, without opening `IncomingCallPage` and without
/// touching any other call/notification. See [looksLikeRingCallPayload].
///
/// A payload matching neither at all (missing, or truly foreign — e.g. from
/// a different app entirely, since `MainActivity` is exported) calls no
/// callback — silently doing nothing is the correct behavior for that case,
/// never a crash or a guess.
void routeNotificationTap(
  String? payload, {
  required void Function(String payload) onCallTap,
  void Function()? onInvalidCallTap,
  void Function(NotificationTapDiagnostic diagnostic)? onDiagnostic,
}) {
  if (payload == null) return;
  if (RingCallIntent.tryRestore(payload) != null) {
    onDiagnostic?.call(NotificationTapDiagnostic.callAccepted());
    onCallTap(payload);
    return;
  }
  if (looksLikeRingCallPayload(payload)) {
    onDiagnostic?.call(NotificationTapDiagnostic.callRejected());
    onInvalidCallTap?.call();
  }
}
