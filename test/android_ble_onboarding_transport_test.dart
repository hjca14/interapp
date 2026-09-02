import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/pairing/data/repositories/android_ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';

class _FakeBridge implements AndroidBleProvisioningBridge {
  final events = StreamController<Map<Object?, Object?>>.broadcast();
  final calls = <String>[];
  String availability = 'ready';
  String? failingMethod;

  @override
  Stream<Map<Object?, Object?>> get discoveries => events.stream;

  @override
  Future<Object?> invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    calls.add(method);
    if (method == failingMethod) {
      throw PlatformException(code: 'expected');
    }
    return method == 'checkAvailability' ? availability : null;
  }
}

void main() {
  String configuredTestValue() => String.fromCharCode(120);

  test('fails closed when development PoP is absent', () async {
    final transport = AndroidBleOnboardingTransport(
      developmentProofOfPossession: '',
      bridge: _FakeBridge(),
    );
    expect(
      await transport.checkAvailability(),
      BleAvailabilityIssue.unsupported,
    );
  });

  test(
    'maps native availability issues without requesting at app startup',
    () async {
      final bridge = _FakeBridge()..availability = 'permissionDenied';
      final transport = AndroidBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      expect(
        await transport.checkAvailability(),
        BleAvailabilityIssue.permissionDenied,
      );
      expect(bridge.calls, ['checkAvailability']);
    },
  );

  test('filters prefix and deduplicates opaque transport handles', () async {
    final bridge = _FakeBridge();
    final transport = AndroidBleOnboardingTransport(
      developmentProofOfPossession: configuredTestValue(),
      bridge: bridge,
    );
    final found = <Object>[];
    final subscription = transport.scanForProvisioningDevices().listen(
      found.add,
    );
    await Future<void>.delayed(Duration.zero);
    bridge.events.add({'transportId': 'opaque-a', 'name': 'InterBridge-A91C'});
    bridge.events.add({'transportId': 'opaque-a', 'name': 'InterBridge-A91C'});
    await Future<void>.delayed(Duration.zero);
    expect(found, hasLength(1));
    await subscription.cancel();
  });

  test(
    'stops scan before connect and completes Security 1 separately',
    () async {
      final bridge = _FakeBridge();
      final transport = AndroidBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      await transport.connect('opaque-a');
      await transport.establishSecureSession();
      expect(bridge.calls, ['stopScan', 'connect', 'establishSecurity1']);
    },
  );

  test('connection failure closes resources', () async {
    final bridge = _FakeBridge()..failingMethod = 'connect';
    final transport = AndroidBleOnboardingTransport(
      developmentProofOfPossession: configuredTestValue(),
      bridge: bridge,
    );
    await expectLater(
      transport.connect('opaque-a'),
      throwsA(isA<BleOperationException>()),
    );
    expect(bridge.calls.last, 'disconnect');
  });

  test('unimplemented Wi-Fi fails explicitly and disconnects', () async {
    final bridge = _FakeBridge();
    final transport = AndroidBleOnboardingTransport(
      developmentProofOfPossession: configuredTestValue(),
      bridge: bridge,
    );
    await expectLater(
      transport.sendWifiCredentials('ssid', 'password'),
      throwsUnimplementedError,
    );
    expect(bridge.calls.last, 'disconnect');
  });
}
