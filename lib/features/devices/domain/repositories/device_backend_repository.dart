import 'package:interapp/features/devices/domain/entities/device_command_result.dart';
import 'package:interapp/features/devices/domain/entities/device_event.dart';
import 'package:interapp/features/devices/domain/entities/device_status.dart';
import 'package:interapp/features/devices/domain/entities/interbridge_device.dart';
import 'package:interapp/features/pairing/domain/entities/device_claim.dart';

/// The app's contract for the **AWS application backend** — authenticated
/// HTTPS/application APIs, never AWS IoT Core/MQTT directly. See
/// `docs/communication-integration.md` for the full architecture.
///
/// This is deliberately a separate contract from `DeviceConnectionRepository`
/// (see that file's doc comment): this one represents "what the backend API
/// exposes", the other represents "how the app talks to *a* device
/// regardless of transport". A future `CloudDeviceConnectionRepository`
/// implements the latter by delegating to this.
abstract class DeviceBackendRepository {
  /// Associates a scanned [DeviceClaim] with the signed-in user. An
  /// application backend operation (§6.1), not a device command.
  Future<DeviceClaimResult> claimDevice(DeviceClaim claim);

  /// Devices owned/shared with the signed-in user, as known by the backend
  /// — not local `shared_preferences` state.
  Future<List<InterBridgeDevice>> getDevices();

  Future<DeviceStatus> getDeviceStatus(String deviceId);

  /// Live status updates. The concrete delivery mechanism (WebSocket,
  /// AppSync, polling...) is an implementation detail the app must not
  /// assume — see `docs/communication-integration.md`, "Realtime".
  Stream<DeviceStatus> watchDeviceStatus(String deviceId);

  Future<DeviceCommandResult> openDoor(String deviceId);

  Future<DeviceCommandResult> restart(String deviceId);

  /// Live events as they're relayed by the backend.
  Stream<DeviceEvent> watchDeviceEvents(String deviceId);

  Future<List<DeviceEvent>> getRecentEvents(String deviceId);
}
