import 'dart:async';

import 'package:interapp/features/devices/domain/entities/device_status.dart';
import 'package:interapp/features/devices/domain/repositories/device_connection_repository.dart';

/// Temporary implementation used until the InterBridge transport is available.
///
/// It reports that no device is connected and performs no device action.
/// Replace this class with a Bluetooth, Wi-Fi, MQTT or WebSocket implementation
/// later.
class LocalDeviceConnectionRepository implements DeviceConnectionRepository {
  final _controllers = <String, StreamController<DeviceStatus>>{};

  StreamController<DeviceStatus> _controllerFor(String deviceId) {
    return _controllers.putIfAbsent(
      deviceId,
      () => StreamController<DeviceStatus>.broadcast(),
    );
  }

  @override
  Future<void> dial(String deviceId, String number) async {}

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> openDoor(String deviceId) async {}

  @override
  Stream<DeviceStatus> watchStatus(String deviceId) async* {
    yield const DeviceStatus(isOnline: false);
    yield* _controllerFor(deviceId).stream;
  }

  /// Debug-only: pulses [DeviceStatus.hasIncomingCall] for [deviceId] so the
  /// incoming-call UI can be exercised before real hardware exists.
  ///
  /// Not part of the [DeviceConnectionRepository] contract — a real
  /// implementation will emit this from an actual hardware event instead.
  void simulateIncomingCall(String deviceId) {
    final controller = _controllerFor(deviceId);
    controller.add(const DeviceStatus(isOnline: false, hasIncomingCall: true));
    Timer(const Duration(seconds: 20), () {
      if (!controller.isClosed) {
        controller.add(const DeviceStatus(isOnline: false));
      }
    });
  }
}
