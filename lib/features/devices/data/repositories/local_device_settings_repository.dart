import 'dart:convert';

import 'package:interapp/features/devices/domain/entities/device_settings.dart';
import 'package:interapp/features/devices/domain/repositories/device_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores each device's [DeviceSettings] under its own
/// `device_settings_<deviceId>` key in `shared_preferences`, mirroring how
/// `LocalFavoritesRepository` isolates favorites per device.
///
/// [DeviceSettings.toMap] is JSON-encoded to a single string rather than
/// using the tab-separated format the flatter entities use — see the doc
/// comment on `DeviceSettings.toMap` for why.
class LocalDeviceSettingsRepository implements DeviceSettingsRepository {
  static const _keyPrefix = 'device_settings_';

  @override
  Future<DeviceSettings> get(String deviceId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('$_keyPrefix$deviceId');
    if (raw == null) return const DeviceSettings();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return DeviceSettings.fromMap(map);
    } on FormatException {
      // Corrupted/foreign value under this key: fall back to defaults
      // instead of crashing the settings screen.
      return const DeviceSettings();
    }
  }

  @override
  Future<void> save(String deviceId, DeviceSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_keyPrefix$deviceId',
      jsonEncode(settings.toMap()),
    );
  }
}
