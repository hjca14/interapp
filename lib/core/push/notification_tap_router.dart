import 'device_event_notification_intent.dart';
import 'ring_call_intent.dart';

/// Routes a tapped local notification's `payload` to the right destination
/// by trying each known shape in turn — [RingCallIntent] (call mode) first,
/// then [DeviceEventNotificationIntent] (`NOTIFICATION_ONLY`). The two
/// shapes are mutually exclusive by construction (different key sets), so
/// there is no ambiguity to resolve.
///
/// A payload matching neither (missing, malformed, from a version of the
/// app that used a different shape, or simply expired per
/// [RingCallIntent.tryRestore]'s own ring-timeout window) calls neither
/// callback — silently doing nothing is the correct behavior for an already
/// stale/foreign tap, never a crash or a guess.
void routeNotificationTap(
  String? payload, {
  required void Function(String payload) onCallTap,
  required void Function(String deviceId) onDeviceEventTap,
}) {
  if (payload == null) return;
  if (RingCallIntent.tryRestore(payload) != null) {
    onCallTap(payload);
    return;
  }
  final deviceEvent = DeviceEventNotificationIntent.tryRestore(payload);
  if (deviceEvent != null) {
    onDeviceEventTap(deviceEvent.deviceId);
  }
}
