import 'package:interapp/core/network/interbridge_api_client.dart';
import 'package:interapp/features/devices/data/parsers/device_notification_preferences_parser.dart';
import 'package:interapp/features/devices/domain/entities/device_notification_preferences.dart';
import 'package:interapp/features/devices/domain/repositories/device_notification_preferences_repository.dart';

class HttpDeviceNotificationPreferencesRepository
    implements DeviceNotificationPreferencesRepository {
  HttpDeviceNotificationPreferencesRepository(
    this._client, {
    DeviceNotificationPreferencesParser parser =
        const DeviceNotificationPreferencesParser(),
  }) : _parser = parser;
  final InterBridgeApiClient _client;
  final DeviceNotificationPreferencesParser _parser;

  String _path(String id) =>
      '/v1/devices/${Uri.encodeComponent(id)}/notification-preferences';

  @override
  Future<DeviceNotificationPreferences> get(String deviceId) async =>
      _parser.parse(await _client.get(_path(deviceId)));

  @override
  Future<DeviceNotificationPreferences> patch(
    String deviceId,
    DeviceNotificationPreferences baseline,
    DeviceNotificationPreferences draft,
  ) async => _parser.parse(
    await _client.patch(_path(deviceId), body: _parser.patch(baseline, draft)),
  );
}
