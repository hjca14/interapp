import 'package:interapp/features/devices/domain/entities/device_status.dart';

/// Contract used by the app to communicate with an InterBridge device.
///
/// Implementations may use a local connection, Bluetooth, Wi-Fi, MQTT or a
/// WebSocket without requiring changes to presentation widgets.
abstract class DeviceConnectionRepository {
  /// Establishes/refreshes the connection to [deviceId]. What this actually
  /// does depends entirely on the transport (nothing, for the local
  /// implementation).
  Future<void> connect(String deviceId);

  /// Sends the "open door" command to [deviceId]. Treat this as a sensitive
  /// operation once a real implementation exists — it unlocks a physical
  /// entrance.
  Future<void> openDoor(String deviceId);

  /// Dials [number] through [deviceId]'s intercom line. Not a phone call —
  /// no `tel:`/OS dialer is involved anywhere in this app.
  Future<void> dial(String deviceId, String number);

  /// Streams [DeviceStatus] updates for [deviceId] for as long as it's
  /// listened to. This is what `deviceStatusProvider` exposes to the UI —
  /// screens should never build a [DeviceStatus] by hand.
  Stream<DeviceStatus> watchStatus(String deviceId);
}
