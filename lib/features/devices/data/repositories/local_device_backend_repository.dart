import 'package:interapp/core/protocol/protocol_constants.dart';
import 'package:interapp/features/devices/domain/entities/device_command.dart';
import 'package:interapp/features/devices/domain/entities/device_command_result.dart';
import 'package:interapp/features/devices/domain/entities/device_event.dart';
import 'package:interapp/features/devices/domain/entities/device_protocol_error.dart';
import 'package:interapp/features/devices/domain/entities/device_status.dart';
import 'package:interapp/features/devices/domain/entities/interbridge_device.dart';
import 'package:interapp/features/devices/domain/repositories/device_backend_repository.dart';
import 'package:interapp/features/pairing/domain/entities/device_claim.dart';

/// Temporary implementation used until the AWS application backend exists.
///
/// Named `Local...` to match the project's convention for "the placeholder
/// used before the real transport/backend is wired up" (see
/// `LocalDeviceConnectionRepository`) — it does not mean this stores
/// anything locally. Every operation honestly reports
/// [DeviceProtocolError.cloudUnavailable] instead of faking success, since
/// there genuinely is no backend to talk to yet.
class LocalDeviceBackendRepository implements DeviceBackendRepository {
  @override
  Future<DeviceClaimResult> claimDevice(DeviceClaim claim) async {
    return const DeviceClaimResult(
      status: DeviceClaimStatus.backendUnavailable,
    );
  }

  @override
  Future<List<InterBridgeDevice>> getDevices() async => const [];

  @override
  Future<DeviceStatus> getDeviceStatus(String deviceId) async {
    return const DeviceStatus(isOnline: false);
  }

  @override
  Stream<DeviceStatus> watchDeviceStatus(String deviceId) {
    return Stream.value(const DeviceStatus(isOnline: false));
  }

  @override
  Future<DeviceCommandResult> openDoor(String deviceId) =>
      _unavailable(DeviceCommandType.openDoor);

  @override
  Future<DeviceCommandResult> restart(String deviceId) =>
      _unavailable(DeviceCommandType.restart);

  Future<DeviceCommandResult> _unavailable(DeviceCommandType command) async {
    return DeviceCommandResult(
      commandId: generateCommandId(),
      command: command,
      status: DeviceCommandStatus.failed,
      error: DeviceProtocolError.cloudUnavailable,
    );
  }

  @override
  Stream<DeviceEvent> watchDeviceEvents(String deviceId) =>
      const Stream.empty();

  @override
  Future<List<DeviceEvent>> getRecentEvents(String deviceId) async => const [];
}
