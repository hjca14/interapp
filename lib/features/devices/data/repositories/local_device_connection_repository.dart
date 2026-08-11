import 'dart:async';

import 'package:interapp/core/protocol/protocol_constants.dart';
import 'package:interapp/features/devices/domain/entities/device_command.dart';
import 'package:interapp/features/devices/domain/entities/device_command_result.dart';
import 'package:interapp/features/devices/domain/entities/device_protocol_error.dart';
import 'package:interapp/features/devices/domain/entities/device_status.dart';
import 'package:interapp/features/devices/domain/repositories/device_connection_repository.dart';

/// Temporary implementation used until the InterBridge transport is available.
///
/// It reports that no device is connected and performs no device action.
/// Replace this class with a Bluetooth, Wi-Fi, MQTT or WebSocket implementation
/// later.
class LocalDeviceConnectionRepository implements DeviceConnectionRepository {
  /// One broadcast controller per device, so [simulateIncomingCall] on one
  /// device never leaks a status update into another device's stream.
  final _controllers = <String, StreamController<DeviceStatus>>{};

  /// Returns the existing controller for [deviceId], creating one on first
  /// use.
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
  Future<DeviceCommandResult> openDoor(String deviceId) async {
    // This implementation represents "no hardware/backend connected at
    // all" — NOT_PROVISIONED is the honest protocol error for that, rather
    // than pretending the command was accepted.
    return DeviceCommandResult(
      commandId: generateCommandId(),
      command: DeviceCommandType.openDoor,
      status: DeviceCommandStatus.rejected,
      error: DeviceProtocolError.notProvisioned,
    );
  }

  @override
  Stream<DeviceStatus> watchStatus(String deviceId) async* {
    // Always start from "not connected" — never invent an online/firmware
    // state just because a screen needs something to show.
    yield const DeviceStatus(isOnline: false);
    // Then forward whatever this device's controller emits later, which
    // today is only [simulateIncomingCall] pulses.
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
