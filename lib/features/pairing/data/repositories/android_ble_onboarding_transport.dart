import 'dart:async';

import 'package:flutter/services.dart';
import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';

abstract interface class AndroidBleProvisioningBridge {
  Stream<Map<Object?, Object?>> get discoveries;
  Future<Object?> invoke(String method, [Map<String, Object?>? arguments]);
}

class MethodChannelAndroidBleProvisioningBridge
    implements AndroidBleProvisioningBridge {
  const MethodChannelAndroidBleProvisioningBridge();

  static const _methods = MethodChannel('interapp/ble_onboarding');
  static const _events = EventChannel('interapp/ble_onboarding/discovery');

  @override
  Stream<Map<Object?, Object?>> get discoveries => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .cast<Map<Object?, Object?>>();

  @override
  Future<Object?> invoke(String method, [Map<String, Object?>? arguments]) =>
      _methods.invokeMethod<Object?>(method, arguments);
}

class BleOperationException implements Exception {
  const BleOperationException(this.operation);
  final String operation;
  @override
  String toString() => 'BleOperationException($operation)';
}

/// Android adapter for Espressif's official provisioning SDK. No GATT,
/// protobuf, endpoint, or Security 1 handshake is implemented in Dart.
class AndroidBleOnboardingTransport implements BleOnboardingTransport {
  AndroidBleOnboardingTransport({
    required this._developmentProofOfPossession,
    AndroidBleProvisioningBridge? bridge,
  }) : _bridge = bridge ?? const MethodChannelAndroidBleProvisioningBridge();

  final String _developmentProofOfPossession;
  final AndroidBleProvisioningBridge _bridge;
  bool _connected = false;

  @override
  Future<BleAvailabilityIssue?> checkAvailability() async {
    if (_developmentProofOfPossession.isEmpty) {
      return BleAvailabilityIssue.unsupported;
    }
    final status = await _bridge.invoke('checkAvailability');
    return switch (status) {
      'ready' => null,
      'bluetoothDisabled' => BleAvailabilityIssue.bluetoothDisabled,
      'permissionDenied' => BleAvailabilityIssue.permissionDenied,
      _ => BleAvailabilityIssue.unsupported,
    };
  }

  @override
  Stream<DiscoveredInterBridge> scanForProvisioningDevices() async* {
    await _bridge.invoke('startScan');
    final seen = <String>{};
    yield* _bridge.discoveries.map((event) {
      final id = event['transportId'];
      final name = event['name'];
      if (id is! String ||
          name is! String ||
          !name.startsWith('InterBridge-')) {
        throw const FormatException('Invalid sanitized BLE discovery event');
      }
      return DiscoveredInterBridge(transportId: id, friendlyName: name);
    }).where((device) => seen.add(device.friendlyName));
  }

  @override
  Future<void> stopScan() async => _bridge.invoke('stopScan');

  @override
  Future<void> connect(String transportId) async {
    await stopScan();
    try {
      await _bridge.invoke('connect', {'transportId': transportId});
      _connected = true;
    } on PlatformException {
      await disconnect();
      throw const BleOperationException('connect');
    }
  }

  @override
  Future<void> establishSecureSession() async {
    if (!_connected) throw const BleOperationException('secureSession');
    try {
      await _bridge.invoke('establishSecurity1', {
        'pop': _developmentProofOfPossession,
      });
    } on PlatformException {
      await disconnect();
      throw const BleOperationException('secureSession');
    }
  }

  @override
  Future<void> requestIdentifyBlink() async {}

  @override
  Future<void> sendWifiCredentials(String ssid, String password) async {
    await disconnect();
    throw UnimplementedError('Wi-Fi provisioning is reserved for phase 3C.3.');
  }

  @override
  Future<void> sendFleetProvisioningMaterial(
    Map<String, dynamic> material,
  ) async {
    await disconnect();
    throw UnimplementedError('Fleet provisioning is outside phase 3C.2.');
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _bridge.invoke('disconnect');
  }
}
