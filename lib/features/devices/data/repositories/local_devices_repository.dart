import 'package:interapp/features/devices/domain/entities/interbridge_device.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's registered devices (their identity, not status) in
/// `shared_preferences`. This is the prototype's device storage; a future
/// backend implementation would satisfy the same shape without changing the
/// screens that call it (see `HomePage`).
class LocalDevicesRepository {
  static const _devicesKey = 'interbridge_devices';
  static const _selectedDeviceKey = 'selected_interbridge_device';

  /// Loads every saved device. Entries that fail to parse are silently
  /// dropped (see `InterBridgeDevice.fromStorage`) rather than crashing the
  /// whole list.
  Future<List<InterBridgeDevice>> getAll() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_devicesKey) ?? [])
        .map(InterBridgeDevice.fromStorage)
        .whereType<InterBridgeDevice>()
        .toList();
  }

  /// Overwrites the entire saved device list. Callers (`HomePage`) keep the
  /// in-memory list as the source of truth and call this after every
  /// add/edit/remove.
  Future<void> saveAll(List<InterBridgeDevice> devices) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_devicesKey, devices.map((device) => device.toStorage()).toList());
  }

  /// Id of the last device the user opened. Not read anywhere yet — reserved
  /// for a future "resume last device" behavior.
  Future<String?> getSelectedId() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_selectedDeviceKey);
  }

  Future<void> setSelectedId(String id) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_selectedDeviceKey, id);
  }
}
