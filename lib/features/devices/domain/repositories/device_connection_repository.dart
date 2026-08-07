import 'package:interapp/features/devices/domain/entities/device_status.dart';

/// Contract used by the app to communicate with an InterBridge device.
///
/// Implementations may use a local connection, Bluetooth, Wi-Fi, MQTT or a
/// WebSocket without requiring changes to presentation widgets.
abstract class DeviceConnectionRepository {
  Future<void> connect(String deviceId);

  Future<void> openDoor(String deviceId);

  Future<void> dial(String deviceId, String number);

  Stream<DeviceStatus> watchStatus(String deviceId);
}
