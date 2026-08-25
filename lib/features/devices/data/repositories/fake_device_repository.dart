import '../../../../core/network/api_failure.dart';
import '../../domain/entities/api_device.dart';
import '../../domain/repositories/device_repository.dart';

/// Deterministic in-memory [DeviceRepository] for development and tests.
///
/// Connection point: this exists because interBackend has not confirmed or
/// deployed the `PATCH /v1/devices/{device_id}` route `updateDeviceName`
/// needs (see `HttpDeviceRepository`'s dartdoc and
/// `docs/APP_COMMUNICATION_STATUS.md`). It is not wired into
/// `deviceRepositoryProvider` today — `HttpDeviceRepository` is, because
/// `listDevices`/`getDeviceDetails` are already real and deployed. Once the
/// rename route is confirmed, this class stays as a test double; no
/// production provider needs to change to start using it, and none should.
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
