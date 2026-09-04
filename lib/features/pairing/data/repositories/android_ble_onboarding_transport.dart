import 'dart:async';

import 'package:flutter/services.dart';
import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';

abstract interface class AndroidBleProvisioningBridge {
  Stream<Map<Object?, Object?>> get discoveries;

  /// Progress/result events for an in-flight `sendWifiCredentials` call —
  /// a separate stream from [discoveries] so Wi-Fi provisioning and BLE
  /// discovery can never cross-deliver events to each other's listener.
  Stream<Map<Object?, Object?>> get wifiProvisioningEvents;
  Future<Object?> invoke(String method, [Map<String, Object?>? arguments]);
}

class MethodChannelAndroidBleProvisioningBridge
    implements AndroidBleProvisioningBridge {
  const MethodChannelAndroidBleProvisioningBridge();

  static const _methods = MethodChannel('interapp/ble_onboarding');
  static const _events = EventChannel('interapp/ble_onboarding/discovery');
  static const _wifiEvents = EventChannel('interapp/ble_onboarding/wifi');

  @override
  Stream<Map<Object?, Object?>> get discoveries => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .cast<Map<Object?, Object?>>();

  @override
  Stream<Map<Object?, Object?>> get wifiProvisioningEvents => _wifiEvents
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
    yield* _bridge.discoveries
        .map((event) {
          final id = event['transportId'];
          final name = event['name'];
          if (id is! String ||
              name is! String ||
              !name.startsWith('InterBridge-')) {
            throw const FormatException(
              'Invalid sanitized BLE discovery event',
            );
          }
          return DiscoveredInterBridge(transportId: id, friendlyName: name);
        })
        .where((device) => seen.add(device.friendlyName));
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

  /// Subscribes to [AndroidBleProvisioningBridge.wifiProvisioningEvents]
  /// *before* ever invoking the native `sendWifiCredentials` method call,
  /// then returns a single-subscription [Stream] that relays the resulting
  /// progress/outcome.
  ///
  /// Order matters here in a way it doesn't for [scanForProvisioningDevices]
  /// (whose `async*` body already awaits `startScan` before consuming
  /// [AndroidBleProvisioningBridge.discoveries]): the native side starts
  /// calling `ESPDevice.provision(...)`'s listener the moment
  /// `sendWifiCredentials` is handled, which can be before the *previous*
  /// platform message (subscribing this stream) would have been processed
  /// if the two were sent in the other order. `EventChannel`/`MethodChannel`
  /// messages to the same platform are delivered FIFO, so listening first
  /// guarantees the native `wifiEventSink` is already attached — including
  /// for `wifiConnected`, which never repeats and would otherwise strand the
  /// UI on "Conectando..." forever if lost. A broadcast [EventChannel]
  /// stream never buffers for a listener that subscribes late, so an
  /// `await for` starting only after `invoke` returns is not safe here.
  @override
  Stream<WifiProvisioningProgress> sendWifiCredentials(
    String ssid,
    String password,
  ) {
    if (ssid.isEmpty) {
      throw ArgumentError.value(ssid, 'ssid', 'must not be empty');
    }
    if (!_connected) {
      throw const BleOperationException('sendWifiCredentials');
    }

    final controller = StreamController<WifiProvisioningProgress>();
    StreamSubscription<Map<Object?, Object?>>? eventSubscription;
    // Exactly one of succeed()/fail() may ever settle the controller — a
    // single active attempt, cleaned up deterministically on every exit.
    var settled = false;

    Future<void> cancelSubscription() async {
      await eventSubscription?.cancel();
      eventSubscription = null;
    }

    Future<void> succeed() async {
      if (settled) return;
      settled = true;
      await cancelSubscription();
      await controller.close();
    }

    Future<void> fail(WifiProvisioningFailureReason reason) async {
      if (settled) return;
      settled = true;
      await cancelSubscription();
      await disconnect();
      controller.addError(WifiProvisioningException(reason));
      await controller.close();
    }

    // Cancelling the returned stream (the coordinator dropping this
    // attempt, or a test tearing down) must release the native listener
    // too — never leave it subscribed underneath a call nobody is
    // listening to anymore.
    controller.onCancel = () {
      settled = true;
      return cancelSubscription();
    };

    eventSubscription = _bridge.wifiProvisioningEvents.listen((event) {
      switch (event['event']) {
        case 'wifiConfigSent':
          if (!settled) controller.add(WifiProvisioningProgress.sendingConfig);
        case 'wifiConfigApplied':
          if (!settled) {
            controller.add(WifiProvisioningProgress.applyingConfig);
          }
        case 'wifiConnected':
          unawaited(succeed());
        case 'wifiFailed':
          unawaited(fail(_parseWifiFailureReason(event['reason'])));
        default:
        // Ignore anything else — defensive against an unrelated/unknown
        // native event reaching this stream.
      }
    });

    unawaited(() async {
      try {
        // ssid/password only ever exist as this call's arguments — never
        // stored in a field, logged, or included in any exception message.
        await _bridge.invoke('sendWifiCredentials', {
          'ssid': ssid,
          'password': password,
        });
      } on PlatformException {
        await fail(WifiProvisioningFailureReason.sendFailed);
      }
    }());

    return controller.stream;
  }

  WifiProvisioningFailureReason _parseWifiFailureReason(Object? reason) {
    return switch (reason) {
      'authFailed' => WifiProvisioningFailureReason.authFailed,
      'networkNotFound' => WifiProvisioningFailureReason.networkNotFound,
      'deviceDisconnected' => WifiProvisioningFailureReason.deviceDisconnected,
      'sendFailed' => WifiProvisioningFailureReason.sendFailed,
      'applyFailed' => WifiProvisioningFailureReason.applyFailed,
      'sessionFailed' => WifiProvisioningFailureReason.sessionFailed,
      _ => WifiProvisioningFailureReason.unknown,
    };
  }

  @override
  Future<void> sendFleetProvisioningMaterial(
    Map<String, dynamic> material,
  ) async {
    await disconnect();
    throw UnimplementedError('Fleet provisioning is a later phase (3C.4+).');
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _bridge.invoke('disconnect');
  }
}
