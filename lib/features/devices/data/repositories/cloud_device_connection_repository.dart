import 'package:interapp/features/devices/domain/entities/device_command_result.dart';
import 'package:interapp/features/devices/domain/entities/device_status.dart';
import 'package:interapp/features/devices/domain/repositories/device_backend_repository.dart';
import 'package:interapp/features/devices/domain/repositories/device_connection_repository.dart';

/// Implements [DeviceConnectionRepository] by delegating to a
/// [DeviceBackendRepository] — the "real" future path once a backend
/// exists, per `docs/communication-integration.md`.
///
/// Not the active implementation yet: `devices_providers.dart` still wires
/// `deviceConnectionRepositoryProvider` to `LocalDeviceConnectionRepository`
/// (which also carries the debug "simulate incoming call" hook used during
/// development). Swapping which one is active is a one-line change in that
/// provider once [DeviceBackendRepository] has a real implementation behind
/// it — no presentation code needs to change either way, which is the
/// entire point of depending on the abstract [DeviceConnectionRepository].
class CloudDeviceConnectionRepository implements DeviceConnectionRepository {
  CloudDeviceConnectionRepository(this._backend);

  final DeviceBackendRepository _backend;

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<DeviceCommandResult> openDoor(String deviceId) =>
      _backend.openDoor(deviceId);

  @override
  Future<void> dial(String deviceId, String number) async {
    // DIAL isn't part of protocol v1 — no such command exists yet. Kept as
    // a no-op like `LocalDeviceConnectionRepository.dial` rather than
    // throwing, since nothing calls this yet either.
  }

  @override
  Stream<DeviceStatus> watchStatus(String deviceId) =>
      _backend.watchDeviceStatus(deviceId);
}
