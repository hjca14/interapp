import '../../../../core/network/api_failure.dart';
import '../../domain/entities/api_device.dart';
import '../../domain/repositories/device_repository.dart';

/// Deterministic in-memory [DeviceRepository] for development and tests.
///
/// This fake represents the device directory as seen by one authenticated
/// user. Its `displayName` values belong to that user's memberships; create
/// separate fake instances when a test needs independent views for different
/// users. It deliberately does not model authentication or a multi-user
/// backend. Production remains wired to [HttpDeviceRepository].
class FakeDeviceRepository implements DeviceRepository {
  FakeDeviceRepository({List<ApiDeviceDetail> devices = const []})
    : _devices = {for (final device in devices) device.deviceId: device};

  final Map<String, ApiDeviceDetail> _devices;

  @override
  Future<ApiDevicePage> listDevices({int limit = 25, String? cursor}) async {
    final items = _devices.values
        .map(
          (device) => ApiDeviceSummary(
            deviceId: device.deviceId,
            displayName: device.displayName,
            role: device.role,
            status: MembershipStatus.active,
          ),
        )
        .toList(growable: false);
    return ApiDevicePage(items: items);
  }

  @override
  Future<ApiDeviceDetail> getDeviceDetails(String deviceId) async {
    return _require(deviceId);
  }

  @override
  Future<ApiDeviceDetail> updateDeviceName(
    String deviceId,
    String? displayName,
  ) async {
    final current = _require(deviceId);
    final updated = ApiDeviceDetail(
      deviceId: current.deviceId,
      displayName: displayName,
      hardwareVersion: current.hardwareVersion,
      ownershipStatus: current.ownershipStatus,
      provisioningStatus: current.provisioningStatus,
      role: current.role,
    );
    _devices[deviceId] = updated;
    return updated;
  }

  ApiDeviceDetail _require(String deviceId) {
    final device = _devices[deviceId];
    if (device == null) {
      throw const ApiFailure(
        ApiFailureKind.notFound,
        'Dispositivo não encontrado.',
      );
    }
    return device;
  }
}
