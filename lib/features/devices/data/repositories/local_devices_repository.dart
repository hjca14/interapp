import 'package:interapp/features/devices/domain/entities/interbridge_device.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDevicesRepository {
  static const _devicesKey = 'interbridge_devices';
  static const _selectedDeviceKey = 'selected_interbridge_device';

  Future<List<InterBridgeDevice>> getAll() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_devicesKey) ?? [])
        .map(InterBridgeDevice.fromStorage)
        .whereType<InterBridgeDevice>()
        .toList();
  }

  Future<void> saveAll(List<InterBridgeDevice> devices) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_devicesKey, devices.map((device) => device.toStorage()).toList());
  }

  Future<String?> getSelectedId() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_selectedDeviceKey);
  }

  Future<void> setSelectedId(String id) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_selectedDeviceKey, id);
  }
}
