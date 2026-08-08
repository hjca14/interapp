import 'package:interapp/features/devices/domain/entities/device_settings.dart';

/// Persists one [DeviceSettings] per device.
///
/// Abstracted the same way `DeviceConnectionRepository` is: today only
/// [LocalDeviceSettingsRepository] exists, but this is the seam a future
/// Supabase-backed implementation plugs into without `DeviceSettingsPage`
/// changing (see PROJECT_CONTEXT.md, "Backend futuro").
abstract class DeviceSettingsRepository {
  /// Returns [deviceId]'s settings, or [DeviceSettings]'s defaults if none
  /// have been saved yet — the caller should never have to special-case "no
  /// settings exist".
  Future<DeviceSettings> get(String deviceId);

  /// Overwrites [deviceId]'s settings.
  Future<void> save(String deviceId, DeviceSettings settings);
}
