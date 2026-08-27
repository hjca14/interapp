import 'package:interapp/core/network/interbridge_api_client.dart';
import 'package:interapp/features/devices/data/parsers/device_notification_preferences_parser.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/domain/repositories/device_notification_preferences_repository.dart';

typedef JsonGet = Future<Map<String, dynamic>> Function(String path);
typedef JsonPatch =
    Future<Map<String, dynamic>> Function(
      String path, {
      required Map<String, dynamic> body,
    });

class HttpDeviceNotificationPreferencesRepository
    implements DeviceNotificationPreferencesRepository {
  HttpDeviceNotificationPreferencesRepository(
    InterBridgeApiClient client, {
    DeviceNotificationPreferencesParser parser =
        const DeviceNotificationPreferencesParser(),
  }) : this.forTest(get: client.get, patch: client.patch, parser: parser);

  // Cannot use initializing formals (`this._get`/`this._patch`/`this._parser`)
  // here: this constructor's public named parameters are `get`/`patch`,
  // which already name the overridden `get()`/`patch()` methods below — an
  // initializing formal requires the parameter name to equal the field name,
  // so it would either collide with those methods or force renaming the
  // public parameters to private-looking names (`_get:`, `_patch:`) for
  // every caller. Suppressed uniformly across all three fields to keep the
  // public `forTest(get:, patch:, parser:)` signature consistent.
  HttpDeviceNotificationPreferencesRepository.forTest({
    required JsonGet get,
    required JsonPatch patch,
    DeviceNotificationPreferencesParser parser =
        const DeviceNotificationPreferencesParser(),
  }) : _get = get, // ignore: prefer_initializing_formals
       _patch = patch, // ignore: prefer_initializing_formals
       _parser = parser; // ignore: prefer_initializing_formals

  final JsonGet _get;
  final JsonPatch _patch;
  final DeviceNotificationPreferencesParser _parser;

  String _path(String id) =>
      '/v1/devices/${Uri.encodeComponent(id)}/notification-preferences';

  @override
  Future<DeviceNotificationPreferences> get(String deviceId) async {
    return _parser.parse(await _get(_path(deviceId)));
  }

  @override
  Future<DeviceNotificationPreferences> patch(
    String deviceId,
    DeviceNotificationPreferences baseline,
    DeviceNotificationPreferences draft,
  ) async {
    final payload = _parser.patch(baseline, draft);
    if (payload.isEmpty) return baseline;
    return _parser.parse(await _patch(_path(deviceId), body: payload));
  }
}
