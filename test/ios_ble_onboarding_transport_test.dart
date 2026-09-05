import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/pairing/data/repositories/ios_ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';

class _FakeBridge implements IOSBleProvisioningBridge {
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
/// does before ever calling it. At the Dart level this is the same two
/// calls Android makes; only the native iOS side actually performs the real
/// BLE connect inside the second one — see
/// `IOSBleOnboardingTransport`'s doc comment.
Future<void> _connectAndSecure(IOSBleOnboardingTransport transport) async {
  await transport.connect('opaque-a');
  await transport.establishSecureSession();
}

void main() {
  String configuredTestValue() => String.fromCharCode(120);

  test('fails closed when development PoP is absent', () async {
    final transport = IOSBleOnboardingTransport(
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
      final transport = IOSBleOnboardingTransport(
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
    final transport = IOSBleOnboardingTransport(
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
    'stops scan before connect and completes Security 1 separately — the '
    'real BLE connect and Security 1 handshake both happen natively inside '
    'establishSecurity1 on iOS, but that reordering is invisible at this '
    'Dart call boundary',
    () async {
      final bridge = _FakeBridge();
      final transport = IOSBleOnboardingTransport(
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
    final transport = IOSBleOnboardingTransport(
      developmentProofOfPossession: configuredTestValue(),
      bridge: bridge,
    );
    await expectLater(
      transport.connect('opaque-a'),
      throwsA(isA<BleOperationException>()),
    );
    expect(bridge.calls.last, 'disconnect');
  });

  test(
    'a PoP rejected during establishSecurity1 (the real Security 1 '
    'handshake on iOS) closes resources exactly like a connect failure',
    () async {
      final bridge = _FakeBridge()..failingMethod = 'establishSecurity1';
      final transport = IOSBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      await transport.connect('opaque-a');
      await expectLater(
        transport.establishSecureSession(),
        throwsA(isA<BleOperationException>()),
      );
      expect(bridge.calls.last, 'disconnect');
    },
  );

  test('sendWifiCredentials refuses to run before connecting — synchronously, '
      'a precondition failure, never a lost/racy stream event', () async {
    final bridge = _FakeBridge();
    final transport = IOSBleOnboardingTransport(
      developmentProofOfPossession: configuredTestValue(),
      bridge: bridge,
    );
    expect(
      () => transport.sendWifiCredentials('home-network', 'password'),
      throwsA(isA<BleOperationException>()),
    );
    expect(bridge.calls, isNot(contains('sendWifiCredentials')));
  });

  test(
    'an empty SSID is rejected synchronously, before any native call',
    () async {
      final bridge = _FakeBridge();
      final transport = IOSBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      await _connectAndSecure(transport);

      expect(
        () => transport.sendWifiCredentials('', 'password'),
        throwsA(isA<ArgumentError>()),
      );
      expect(bridge.calls, isNot(contains('sendWifiCredentials')));
    },
  );

  test(
    'an empty password is sent as-is for an open network — only SSID is required',
    () async {
      final bridge = _FakeBridge();
      final transport = IOSBleOnboardingTransport(
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
      final transport = IOSBleOnboardingTransport(
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
    'reports only applyingConfig, and completes normally — never emitting a '
    'value — once the device confirms it connected. ESPProvision never '
    'gives a distinct "device received config" callback the way Android '
    'does, so sendingConfig is never emitted here — see '
    'IOSBleOnboardingTransport\'s doc comment, point 2.',
    () async {
      final bridge = _FakeBridge();
      final transport = IOSBleOnboardingTransport(
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

      bridge.wifiEvents.add({'event': 'wifiConfigApplied'});
      bridge.wifiEvents.add({'event': 'wifiConnected'});
      await done.future;

      expect(progress, [WifiProvisioningProgress.applyingConfig]);
    },
  );

  test(
    'an unrecognized native event (e.g. a stray wifiConfigSent, which iOS '
    'never emits for real) is ignored rather than surfaced or crashing',
    () async {
      final bridge = _FakeBridge();
      final transport = IOSBleOnboardingTransport(
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

      expect(progress, [WifiProvisioningProgress.applyingConfig]);
    },
  );

  test('maps a device-reported failure reason and disconnects', () async {
    final bridge = _FakeBridge();
    final transport = IOSBleOnboardingTransport(
      developmentProofOfPossession: configuredTestValue(),
      bridge: bridge,
    );
    await _connectAndSecure(transport);

    final stream = transport.sendWifiCredentials('home-network', 'wrong');
    final resultFuture = stream.toList();
    await Future<void>.delayed(Duration.zero);
    bridge.wifiEvents.add({'event': 'wifiFailed', 'reason': 'authFailed'});

    await expectLater(
      resultFuture,
      throwsA(
        isA<WifiProvisioningException>().having(
          (e) => e.reason,
          'reason',
          WifiProvisioningFailureReason.authFailed,
        ),
      ),
    );
    expect(bridge.calls.last, 'disconnect');
  });

  test(
    'an unclassified reason string maps to unknown rather than throwing',
    () async {
      final bridge = _FakeBridge();
      final transport = IOSBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      await _connectAndSecure(transport);

      final stream = transport.sendWifiCredentials('home-network', 'x');
      final resultFuture = stream.toList();
      await Future<void>.delayed(Duration.zero);
      bridge.wifiEvents.add({
        'event': 'wifiFailed',
        'reason': 'somethingNew',
      });

      await expectLater(
        resultFuture,
        throwsA(
          isA<WifiProvisioningException>().having(
            (e) => e.reason,
            'reason',
            WifiProvisioningFailureReason.unknown,
          ),
        ),
      );
    },
  );

  test(
    'a second sendWifiCredentials call while one is already active fails '
    'synchronously — at most one attempt in flight at a time',
    () async {
      final bridge = _FakeBridge();
      final transport = IOSBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      await _connectAndSecure(transport);

      transport.sendWifiCredentials('home-network', 'password');
      expect(
        () => transport.sendWifiCredentials('home-network', 'password'),
        throwsA(isA<BleOperationException>()),
      );
    },
  );

  test(
    'the native event channel closing mid-attempt ends it as noResponse, '
    'never left hanging',
    () async {
      final bridge = _FakeBridge();
      final transport = IOSBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      await _connectAndSecure(transport);

      final stream = transport.sendWifiCredentials('home-network', 'password');
      final resultFuture = stream.toList();
      await Future<void>.delayed(Duration.zero);
      await bridge.wifiEvents.close();

      await expectLater(
        resultFuture,
        throwsA(
          isA<WifiProvisioningException>().having(
            (e) => e.reason,
            'reason',
            WifiProvisioningFailureReason.noResponse,
          ),
        ),
      );
    },
  );

  test(
    'disconnect() while a Wi-Fi attempt is in flight tears it down as '
    'deviceDisconnected instead of leaving the stream open forever',
    () async {
      final bridge = _FakeBridge();
      final transport = IOSBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      await _connectAndSecure(transport);

      final events = <Object>[];
      final done = Completer<void>();
      transport
          .sendWifiCredentials('home-network', 'password')
          .listen(events.add, onError: events.add, onDone: done.complete);
      await Future<void>.delayed(Duration.zero);

      await transport.disconnect();
      await done.future;

      expect(
        events,
        [
          isA<WifiProvisioningException>().having(
            (e) => e.reason,
            'reason',
            WifiProvisioningFailureReason.deviceDisconnected,
          ),
        ],
        reason:
            'an external disconnect must still resolve the caller-facing '
            'stream, never leave it hanging',
      );
    },
  );
}
