import '../entities/device_notification_preferences.dart';

abstract class DeviceNotificationPreferencesRepository {
  Future<DeviceNotificationPreferences> get(String deviceId);
  Future<DeviceNotificationPreferences> patch(
    String deviceId,
    DeviceNotificationPreferences baseline,
    DeviceNotificationPreferences draft,
  );
}
