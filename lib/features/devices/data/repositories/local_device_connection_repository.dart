import 'package:interapp/features/devices/domain/entities/device_status.dart';
import 'package:interapp/features/devices/domain/repositories/device_connection_repository.dart';

/// Temporary implementation used until the InterBridge transport is available.
///
/// It deliberately emits no status and performs no device action. Replace this
/// class with a Bluetooth, Wi-Fi, MQTT or WebSocket implementation later.
class LocalDeviceConnectionRepository implements DeviceConnectionRepository {
  @override
  Future<void> call(String deviceId) async {}

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> openDoor(String deviceId) async {}

  @override
  Stream<DeviceStatus> watchStatus(String deviceId) => const Stream.empty();
}
