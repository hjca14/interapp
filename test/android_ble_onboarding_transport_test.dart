import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/pairing/data/repositories/android_ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';

class _FakeBridge implements AndroidBleProvisioningBridge {
  final events = StreamController<Map<Object?, Object?>>.broadcast();
  final wifiEvents = StreamController<Map<Object?, Object?>>.broadcast();
  final calls = <String>[];
  final callArguments = <String, Map<String, Object?>?>{};
  String availability = 'ready';
  String? failingMethod;

  @override
  Stream<Map<Object?, Object?>> get discoveries => events.stream;

  @override
  Stream<Map<Object?, Object?>> get wifiProvisioningEvents => wifiEvents.stream;

  @override
  Future<Object?> invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    calls.add(method);
    callArguments[method] = arguments;
    if (method == failingMethod) {
      throw PlatformException(code: 'expected');
    }
    return method == 'checkAvailability' ? availability : null;
  }
}

/// Connects and completes Security 1 so [transport] is ready for
/// `sendWifiCredentials` — mirrors what `OnboardingCoordinator.confirmDevice`
/// does before ever calling it.
Future<void> _connectAndSecure(AndroidBleOnboardingTransport transport) async {
  await transport.connect('opaque-a');
  await transport.establishSecureSession();
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

  test('filters prefix and deduplicates by advertised name', () async {
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
    bridge.events.add({'transportId': 'opaque-b', 'name': 'InterBridge-A91C'});
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

  test('sendWifiCredentials refuses to run before connecting', () async {
    final bridge = _FakeBridge();
    final transport = AndroidBleOnboardingTransport(
      developmentProofOfPossession: configuredTestValue(),
      bridge: bridge,
    );
    await expectLater(
      transport.sendWifiCredentials('home-network', 'password').drain<void>(),
      throwsA(isA<BleOperationException>()),
    );
    expect(bridge.calls, isNot(contains('sendWifiCredentials')));
  });

  test('an empty SSID is rejected before any native call', () async {
    final bridge = _FakeBridge();
    final transport = AndroidBleOnboardingTransport(
      developmentProofOfPossession: configuredTestValue(),
      bridge: bridge,
    );
    await _connectAndSecure(transport);

    await expectLater(
      transport.sendWifiCredentials('', 'password').drain<void>(),
      throwsA(isA<ArgumentError>()),
    );
    expect(bridge.calls, isNot(contains('sendWifiCredentials')));
  });

  test(
    'an empty password is sent as-is for an open network — only SSID is required',
    () async {
      final bridge = _FakeBridge();
      final transport = AndroidBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      await _connectAndSecure(transport);

      final progressFuture = transport
          .sendWifiCredentials('open-network', '')
          .toList();
      await Future<void>.delayed(Duration.zero);
      bridge.wifiEvents.add({'event': 'wifiConnected'});

      await progressFuture;
      expect(bridge.callArguments['sendWifiCredentials'], {
        'ssid': 'open-network',
        'password': '',
      });
    },
  );

  test(
    'sends ssid/password as the native call arguments, never persisted elsewhere',
    () async {
      final bridge = _FakeBridge();
      final transport = AndroidBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      await _connectAndSecure(transport);

      final progressFuture = transport
          .sendWifiCredentials('home-network', 'secret-password')
          .toList();
      await Future<void>.delayed(Duration.zero);
      bridge.wifiEvents.add({'event': 'wifiConnected'});

      await progressFuture;
      expect(bridge.callArguments['sendWifiCredentials'], {
        'ssid': 'home-network',
        'password': 'secret-password',
      });
    },
  );

  test(
    'reports sendingConfig then applyingConfig, and completes normally — '
    'never emitting a value — once the device confirms it connected',
    () async {
      final bridge = _FakeBridge();
      final transport = AndroidBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      await _connectAndSecure(transport);

      final progress = <WifiProvisioningProgress>[];
      final stream = transport.sendWifiCredentials('home-network', 'password');
      final done = Completer<void>();
      stream.listen(
        progress.add,
        onDone: done.complete,
        onError: (Object e) => done.completeError(e),
      );
      await Future<void>.delayed(Duration.zero);

      bridge.wifiEvents.add({'event': 'wifiConfigSent'});
      bridge.wifiEvents.add({'event': 'wifiConfigApplied'});
      bridge.wifiEvents.add({'event': 'wifiConnected'});
      await done.future;

      expect(progress, [
        WifiProvisioningProgress.sendingConfig,
        WifiProvisioningProgress.applyingConfig,
      ]);
    },
  );

  test(
    'a native invoke failure on sendWifiCredentials itself surfaces sendFailed '
    'and disconnects',
    () async {
      final bridge = _FakeBridge()..failingMethod = 'sendWifiCredentials';
      final transport = AndroidBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      await _connectAndSecure(transport);

      await expectLater(
        transport.sendWifiCredentials('home-network', 'password').drain<void>(),
        throwsA(
          isA<WifiProvisioningException>().having(
            (e) => e.reason,
            'reason',
            WifiProvisioningFailureReason.sendFailed,
          ),
        ),
      );
      expect(bridge.calls.last, 'disconnect');
    },
  );

  for (final entry in {
    'authFailed': WifiProvisioningFailureReason.authFailed,
    'networkNotFound': WifiProvisioningFailureReason.networkNotFound,
    'deviceDisconnected': WifiProvisioningFailureReason.deviceDisconnected,
    'sessionFailed': WifiProvisioningFailureReason.sessionFailed,
    'applyFailed': WifiProvisioningFailureReason.applyFailed,
    'something-unrecognized': WifiProvisioningFailureReason.unknown,
  }.entries) {
    test('a wifiFailed event with reason "${entry.key}" maps to '
        '${entry.value} and disconnects', () async {
      final bridge = _FakeBridge();
      final transport = AndroidBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      await _connectAndSecure(transport);

      final future = transport
          .sendWifiCredentials('home-network', 'password')
          .drain<void>();
      await Future<void>.delayed(Duration.zero);
      bridge.wifiEvents.add({'event': 'wifiFailed', 'reason': entry.key});

      await expectLater(
        future,
        throwsA(
          isA<WifiProvisioningException>().having(
            (e) => e.reason,
            'reason',
            entry.value,
          ),
        ),
      );
      expect(bridge.calls.last, 'disconnect');
    });
  }
}
