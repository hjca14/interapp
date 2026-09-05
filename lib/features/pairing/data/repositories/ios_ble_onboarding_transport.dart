import 'dart:async';

import 'package:flutter/services.dart';
import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';

abstract interface class IOSBleProvisioningBridge {
  Stream<Map<Object?, Object?>> get discoveries;

  /// Progress/result events for an in-flight `sendWifiCredentials` call —
  /// a separate stream from [discoveries], same split as the Android bridge
  /// and for the same reason (never cross-deliver events to the other
  /// listener).
  Stream<Map<Object?, Object?>> get wifiProvisioningEvents;
  Future<Object?> invoke(String method, [Map<String, Object?>? arguments]);
}

/// Uses the same channel names as the Android bridge
/// (`android_ble_onboarding_transport.dart`) — only one platform's native
/// side ever registers a handler for them in a given build, so there is no
/// collision, and keeping the names identical is deliberate: it is the only
/// thing that lets `OnboardingCoordinator` and the rest of the Dart-side
/// onboarding stack stay unaware that the two platforms exist.
class MethodChannelIOSBleProvisioningBridge
    implements IOSBleProvisioningBridge {
  const MethodChannelIOSBleProvisioningBridge();

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

/// iOS adapter for Espressif's official `ESPProvision` SDK
/// (github.com/espressif/esp-idf-provisioning-ios). No CoreBluetooth/GATT,
/// protobuf, or Security 0/session logic of our own — every BLE/Protocomm
/// operation goes through `ESPDevice`/`ESPProvisionManager`. See
/// `ios/Runner/EspressifBleProvisioningBridge.swift` for the native side and
/// `docs/PHASE_3_ROADMAP.md` for how this compares with the already-validated
/// Android transport (`android_ble_onboarding_transport.dart`), which this
/// deliberately does not modify or share an implementation with — the two
/// official SDKs expose different enough shapes (see the two real iOS
/// differences documented below) that sharing a base class would either blur
/// Android's already-validated behavior or paper over iOS's.
///
/// Two real protocol/SDK differences from Android, modeled explicitly rather
/// than hidden behind a shared abstraction:
///
/// 1. **`connect()`/[establishSecureSession] split.** Android's SDK exposes
///    BLE GATT connect and the Protocomm Security 1 handshake as separate
///    operations (and the Android bridge defers the handshake itself into
///    `sendWifiCredentials` for SDK-bug reasons — see
///    `android_ble_onboarding_transport.dart`). `ESPDevice` has no such
///    split: `connect(delegate:completionHandler:)` performs the BLE
///    connection *and* the Security 1 session establishment (via
///    `ESPDeviceConnectionDelegate.getProofOfPossesion`) as one operation,
///    only calling back once both are done. So on iOS, the native `connect`
///    method call only selects the previously-discovered `ESPDevice`
///    (a local, synchronous operation); the real BLE connect and Security 1
///    handshake both happen inside the native `establishSecurity1` call
///    instead, once the PoP is available. Both of
///    [connect]/[establishSecureSession] must still be awaited in order —
///    `OnboardingCoordinator.confirmDevice` already does this and treats any
///    failure from either identically, so this reordering is invisible
///    above this class.
/// 2. **Coarser Wi-Fi progress.** Android's SDK reports the device receiving
///    credentials and applying them as two distinct `ProvisionListener`
///    callbacks (`wifiConfigSent`/`wifiConfigApplied`). `ESPDevice.provision`
///    exposes only one intermediate step (`.configApplied`, fired once the
///    config has been both sent *and* accepted for applying) before the
///    final `.success`/`.failure`. This transport therefore never emits
///    [WifiProvisioningProgress.sendingConfig] itself — only
///    [WifiProvisioningProgress.applyingConfig] once `.configApplied`
///    arrives. `OnboardingCoordinator.submitWifi` already sets
///    [WifiProvisioningProgress.sendingConfig] optimistically the moment the
///    user submits the form, before it ever listens to this stream, so the
///    UI still shows a "sending" step first — this class just never confirms
///    a distinct device-side "received" acknowledgement iOS's SDK doesn't
///    give.
class IOSBleOnboardingTransport implements BleOnboardingTransport {
  IOSBleOnboardingTransport({
    required this._developmentProofOfPossession,
    IOSBleProvisioningBridge? bridge,
  }) : _bridge = bridge ?? const MethodChannelIOSBleProvisioningBridge();

  final String _developmentProofOfPossession;
  final IOSBleProvisioningBridge _bridge;
  bool _connected = false;

  /// Non-null exactly while a `sendWifiCredentials` attempt is in flight —
  /// same single-attempt lock and external-disconnect handling as the
  /// Android transport; see its doc comment for the full rationale.
  Future<void> Function()? _cancelActiveWifiAttempt;

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

  /// Performs the real BLE connect *and* the Protocomm Security 1 handshake
  /// on iOS — see this class's doc comment, point 1. Unlike Android's
  /// `establishSecureSession` (a purely local PoP configuration step that
  /// defers the actual handshake to `sendWifiCredentials`), a failure here
  /// is the normal, expected place for an incorrect PoP or a lost BLE
  /// connection to surface on iOS.
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

  /// See `AndroidBleOnboardingTransport.sendWifiCredentials`'s doc comment
  /// for why the native event listener is attached before the native
  /// `sendWifiCredentials` method is ever invoked, and for the
  /// single-attempt lock/cleanup semantics — identical here. The event
  /// vocabulary itself is narrower on iOS: see this class's doc comment,
  /// point 2, for why `wifiConfigSent` is never emitted.
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
    if (_cancelActiveWifiAttempt != null) {
      throw const BleOperationException('sendWifiCredentials');
    }

    final controller = StreamController<WifiProvisioningProgress>();
    StreamSubscription<Map<Object?, Object?>>? eventSubscription;
    var settled = false;

    Future<void> cancelSubscription() async {
      await eventSubscription?.cancel();
      eventSubscription = null;
    }

    void releaseLock() {
      _cancelActiveWifiAttempt = null;
    }

    Future<void> succeed() async {
      if (settled) return;
      settled = true;
      releaseLock();
      await cancelSubscription();
      await controller.close();
    }

    Future<void> fail(WifiProvisioningFailureReason reason) async {
      if (settled) return;
      settled = true;
      releaseLock();
      await cancelSubscription();
      await disconnect();
      controller.addError(WifiProvisioningException(reason));
      await controller.close();
    }

    controller.onCancel = () {
      settled = true;
      releaseLock();
      return cancelSubscription();
    };

    _cancelActiveWifiAttempt = () async {
      if (settled) return;
      settled = true;
      await cancelSubscription();
      controller.addError(
        const WifiProvisioningException(
          WifiProvisioningFailureReason.deviceDisconnected,
        ),
      );
      await controller.close();
    };

    eventSubscription = _bridge.wifiProvisioningEvents.listen(
      (event) {
        switch (event['event']) {
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
      },
      onError: (Object _, StackTrace _) {
        unawaited(fail(WifiProvisioningFailureReason.noResponse));
      },
      onDone: () {
        unawaited(fail(WifiProvisioningFailureReason.noResponse));
      },
    );

    unawaited(() async {
      try {
        // ssid/password only ever exist as this call's arguments — never
        // stored in a field, logged, or included in any exception message.
        await _bridge.invoke('sendWifiCredentials', {
          'ssid': ssid,
          'password': password,
        });
      } catch (_) {
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
      'noResponse' => WifiProvisioningFailureReason.noResponse,
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
    final cancelActiveWifiAttempt = _cancelActiveWifiAttempt;
    _cancelActiveWifiAttempt = null;
    await cancelActiveWifiAttempt?.call();
    await _bridge.invoke('disconnect');
  }
}
