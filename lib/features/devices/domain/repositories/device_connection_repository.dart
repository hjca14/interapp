import 'package:interapp/features/devices/domain/entities/device_command_result.dart';
import 'package:interapp/features/devices/domain/entities/device_status.dart';

/// Contract used by the app to communicate with an InterBridge device.
///
/// Implementations may use a local connection, Bluetooth, Wi-Fi, MQTT or a
/// WebSocket without requiring changes to presentation widgets.
///
/// Distinct from `DeviceBackendRepository`: that one models "what the AWS
/// application backend's API exposes"; this one models "how the app
/// interacts with *a* device", regardless of what's behind it. Today the
/// only implementation is `LocalDeviceConnectionRepository` (no hardware).
/// A future `CloudDeviceConnectionRepository` would implement this contract
/// by delegating to `DeviceBackendRepository`:
///
/// ```text
/// DeviceDetailPage
///        ↓
/// provider/controller
///        ↓
/// DeviceConnectionRepository
///        ↓
/// CloudDeviceConnectionRepository
///        ↓
/// DeviceBackendRepository
///        ↓
/// authenticated backend HTTPS API
/// ```
abstract class DeviceConnectionRepository {
  /// Establishes/refreshes the connection to [deviceId]. What this actually
  /// does depends entirely on the transport (nothing, for the local
  /// implementation).
  Future<void> connect(String deviceId);

  /// Requests the `OPEN_DOOR` command for [deviceId] and returns its
  /// outcome. Treat this as a sensitive operation — it unlocks a physical
  /// entrance. A `200`-equivalent response is not success: only a
  /// [DeviceCommandResult] with `status == DeviceCommandStatus.completed`
  /// is (see `docs/communication-protocol.md` §20.1).
  Future<DeviceCommandResult> openDoor(String deviceId);

  /// Dials [number] through [deviceId]'s intercom line. Not a phone call —
  /// no `tel:`/OS dialer is involved anywhere in this app.
  Future<void> dial(String deviceId, String number);

  /// Streams [DeviceStatus] updates for [deviceId] for as long as it's
  /// listened to. This is what `deviceStatusProvider` exposes to the UI —
  /// screens should never build a [DeviceStatus] by hand.
  Stream<DeviceStatus> watchStatus(String deviceId);
}
