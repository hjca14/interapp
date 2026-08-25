import '../../../../core/network/interbridge_api_client.dart';
import '../../domain/entities/api_device.dart';
import '../../domain/repositories/device_repository.dart';
import '../parsers/device_api_parser.dart';

/// Device directory repository backed by interBackend.
///
/// [listDevices], [getDeviceDetails] and [status] are the three GET routes
/// deployed and validated in Phase 2C. [updateDeviceName] is different: it
/// targets a `PATCH /v1/devices/{device_id}` route that has **not** been
/// confirmed or deployed by interBackend at the time this was written (no
/// OpenAPI spec, PR, or doc in this repo defines it — see
/// `docs/APP_COMMUNICATION_STATUS.md`, "Device rename" row, status
/// Provisional). The method below is a best-effort implementation of the
/// most likely shape, following the same snake_case/`/v1/devices/{id}`
/// convention as the deployed routes, so it is ready to use the moment the
/// backend confirms it — but it must not be treated as validated, and
/// `deviceRepositoryProvider` (`devices_providers.dart`) does not have to
/// change to wire it in: it already reads this class.
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

  /// Sets or clears the device's friendly name. See the class dartdoc for
  /// why this specific route is provisional. [displayName] must already be
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
