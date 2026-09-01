import 'dart:convert';

/// The minimal context attached to a `NOTIFICATION_ONLY` local notification.
///
/// Deliberately a different shape than [RingCallIntent] (a different `kind`
/// discriminator, no `call_id`/`event_id`): a notification represents an
/// event that already happened, not a live call, so tapping it must never be
/// mistaken for a [RingCallIntent] and routed into `IncomingCallPage` —
/// there is nothing to answer/dismiss. `MainActivity`'s lock-screen
/// validator also only recognizes the call shape, so this payload never
/// grants `setShowWhenLocked`/`setTurnScreenOn` either.
final class DeviceEventNotificationIntent {
  const DeviceEventNotificationIntent({required this.deviceId});

  final String deviceId;

  static const _kind = 'DEVICE_EVENT';
  static final _deviceIdPattern = RegExp(r'^ib-[0-9a-f]{32}$');

  String serialize() =>
      jsonEncode({'v': 1, 'kind': _kind, 'device_id': deviceId});

  /// Strict, symmetric to [RingCallIntent.tryRestore]: exact key set, exact
  /// `kind`, and a validated `device_id` — never a looser fallback path.
  static DeviceEventNotificationIntent? tryRestore(String? encoded) {
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> || decoded.length != 3) {
        return null;
      }
      if (decoded['v'] != 1 || decoded['kind'] != _kind) return null;
      final deviceId = decoded['device_id'];
      if (deviceId is! String || !_deviceIdPattern.hasMatch(deviceId)) {
        return null;
      }
      return DeviceEventNotificationIntent(deviceId: deviceId);
    } on Object {
      return null;
    }
  }
}
