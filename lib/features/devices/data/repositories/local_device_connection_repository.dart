import 'package:interapp/features/devices/domain/entities/device_status.dart';
import 'package:interapp/features/devices/domain/repositories/device_connection_repository.dart';

/// Temporary implementation used until the InterBridge transport is available.
///
/// It reports that no device is connected and performs no device action.
/// Replace this class with a Bluetooth, Wi-Fi, MQTT or WebSocket implementation
/// later.
class LocalDeviceConnectionRepository implements DeviceConnectionRepository {
  @override
  Future<void> dial(String deviceId, String number) async {}

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> openDoor(String deviceId) async {}

  @override
  Stream<DeviceStatus> watchStatus(String deviceId) {
    return Stream.value(const DeviceStatus(isOnline: false));
  }
}
