import 'device_event_notification_intent.dart';
import 'notification_tap_diagnostic.dart';
import 'ring_call_intent.dart';

/// Routes a tapped local notification's `payload` to the right destination
/// by trying each known shape in turn — [RingCallIntent] (call mode) first,
/// then [DeviceEventNotificationIntent] (`NOTIFICATION_ONLY`). The two
/// shapes are mutually exclusive by construction (different key sets), so
/// there is no ambiguity to resolve.
///
/// A payload that has [RingCallIntent]'s envelope shape but fails its full
/// validation (expired past the ring-timeout, malformed, a foreign app
/// version) calls [onInvalidCallTap] — the caller's cue to safely recover:
/// cancel exactly the tapped notification, stop its ringtone, and undo any
/// lock-screen bypass, without opening `IncomingCallPage` and without
/// touching any other call/notification. See [looksLikeRingCallPayload].
///
/// A payload matching neither shape at all (missing, or truly foreign) calls
/// no callback — silently doing nothing is the correct behavior for that
/// case, never a crash or a guess.
void routeNotificationTap(
  String? payload, {
  required void Function(String payload) onCallTap,
  required void Function(String deviceId) onDeviceEventTap,
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
    return;
  }
  final deviceEvent = DeviceEventNotificationIntent.tryRestore(payload);
  if (deviceEvent != null) {
    onDiagnostic?.call(NotificationTapDiagnostic.deviceNotificationAccepted());
    onDeviceEventTap(deviceEvent.deviceId);
  }
}
