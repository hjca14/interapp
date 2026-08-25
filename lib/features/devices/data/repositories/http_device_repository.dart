import '../../../../core/network/interbridge_api_client.dart';
import '../../domain/entities/api_device.dart';
import '../../domain/repositories/device_repository.dart';
import '../parsers/device_api_parser.dart';

/// Device directory repository backed by interBackend.
///
/// [listDevices], [getDeviceDetails] and [status] are the three GET routes
/// deployed and validated in Phase 2C. interBackend PR #18 confirms that
/// [updateDeviceName] uses `PATCH /v1/devices/{device_id}` and updates the
/// authenticated user's `DeviceMembership.display_name`. The backend derives
/// that user from the JWT, so the value is personal rather than a global
/// property of the device. The PATCH implementation exists locally in the
/// backend, but is not deployed to AWS and has not been validated remotely.
class HttpDeviceRepository implements DeviceRepository {
  const HttpDeviceRepository(
    this._api, {
    this._parser = const DeviceApiParser(),
  });

  final InterBridgeApiClient _api;
  final DeviceApiParser _parser;

  /// Gets a page of device memberships.
  ///
  /// [cursor] is passed through unchanged. The repository never decodes or
  /// persists it, because continuation cursors are opaque backend values.
  @override
  Future<ApiDevicePage> listDevices({int limit = 25, String? cursor}) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'deve estar entre 1 e 100');
    }
    final responseJson = await _api.get(
      '/v1/devices',
      query: {'limit': '$limit', 'cursor': ?cursor},
    );
    return _parser.parseDevicePage(responseJson);
  }

  /// Gets device details by ID, supporting navigation without router `extra`.
  @override
  Future<ApiDeviceDetail> getDeviceDetails(String deviceId) async {
    final encodedDeviceId = Uri.encodeComponent(deviceId);
    final responseJson = await _api.get('/v1/devices/$encodedDeviceId');
    return _parser.parseDeviceDetail(responseJson);
  }

  /// Gets status separately from device identity/details.
  Future<ApiDeviceStatus> status(String deviceId) async {
    final encodedDeviceId = Uri.encodeComponent(deviceId);
    final responseJson = await _api.get('/v1/devices/$encodedDeviceId/status');
    return _parser.parseDeviceStatus(responseJson);
  }

  /// Sets or clears the authenticated user's personal device name.
  /// [displayName] must already be
  /// trimmed and non-empty, or `null` to clear the custom name — callers
  /// (`ApiDeviceDetailController.updateName`) are responsible for that, this
  /// method does not re-validate it.
  @override
  Future<ApiDeviceDetail> updateDeviceName(
    String deviceId,
    String? displayName,
  ) async {
    final encodedDeviceId = Uri.encodeComponent(deviceId);
    final responseJson = await _api.patch(
      '/v1/devices/$encodedDeviceId',
      body: {'display_name': displayName},
    );
    return _parser.parseDeviceDetail(responseJson);
  }
}
