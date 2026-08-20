import '../../../../core/network/interbridge_api_client.dart';
import '../../domain/entities/api_device.dart';
import '../parsers/device_api_parser.dart';

/// Read-only repository for the three device routes deployed in Phase 2C.
class HttpDeviceRepository {
  const HttpDeviceRepository(
    this._api, {
    DeviceApiParser parser = const DeviceApiParser(),
  }) : _parser = parser;

  final InterBridgeApiClient _api;
  final DeviceApiParser _parser;

  /// Gets a page of device memberships.
  ///
  /// [cursor] is passed through unchanged. The repository never decodes or
  /// persists it, because continuation cursors are opaque backend values.
  Future<ApiDevicePage> list({int limit = 25, String? cursor}) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'deve estar entre 1 e 100');
    }
    final responseJson = await _api.get(
      '/v1/devices',
      query: {'limit': '$limit', if (cursor != null) 'cursor': cursor},
    );
    return _parser.parseDevicePage(responseJson);
  }

  /// Gets device details by ID, supporting navigation without router `extra`.
  Future<ApiDeviceDetail> detail(String deviceId) async {
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
}
