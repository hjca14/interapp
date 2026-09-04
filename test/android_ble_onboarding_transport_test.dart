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

  /// Called synchronously, from inside [invoke] itself, the instant
  /// `method == 'sendWifiCredentials'` is handled — before `invoke`'s own
  /// Future is even returned to its caller. Lets a test simulate the real
  /// native side firing `wifiConnected`/`wifiFailed`/progress events the
  /// moment `ESPDevice.provision(...)` starts, which can race ahead of
  /// Dart's `sendWifiCredentials` still merely awaiting the platform
  /// method call's own round trip — exactly the ordering
  /// [AndroidBleOnboardingTransport.sendWifiCredentials] must survive.
  void Function()? onSendWifiCredentialsInvoked;

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
    if (method == 'sendWifiCredentials') {
      onSendWifiCredentialsInvoked?.call();
    }
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

  test('sendWifiCredentials refuses to run before connecting — synchronously, '
      'a precondition failure, never a lost/racy stream event', () async {
    final bridge = _FakeBridge();
    final transport = AndroidBleOnboardingTransport(
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
      final transport = AndroidBleOnboardingTransport(
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

  group('start/native-event race', () {
    // These reproduce the real hazard: ESPDevice's ProvisionListener can
    // start firing the moment provision() is handled natively, which can
    // be before the *previous* platform message (subscribing this event
    // stream) has been processed by the other side — if the two were sent
    // in the wrong order. `_FakeBridge.onSendWifiCredentialsInvoked` fires
    // synchronously from inside `invoke('sendWifiCredentials', ...)`
    // itself, simulating an event arriving as early as physically
    // possible — before `sendWifiCredentials`'s own Future to that
    // platform call has even resolved. If the event subscription were
    // established only after `invoke` returns (the bug this closes), the
    // event below would be silently dropped by the broadcast
    // `EventChannel` stream (which never buffers for a late listener) and
    // this stream would simply hang forever.

    test('an event emitted synchronously from inside the native invoke call '
        'is never lost — progress is still observed', () async {
      final bridge = _FakeBridge();
      bridge.onSendWifiCredentialsInvoked = () {
        bridge.wifiEvents.add({'event': 'wifiConfigSent'});
      };
      final transport = AndroidBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      await _connectAndSecure(transport);

      final progress = <WifiProvisioningProgress>[];
      final subscription = transport
          .sendWifiCredentials('home-network', 'password')
          .listen(progress.add);
      await Future<void>.delayed(Duration.zero);

      expect(
        progress,
        [WifiProvisioningProgress.sendingConfig],
        reason:
            'the event fired the instant the native call was handled '
            'must still reach the listener, not be silently dropped',
      );
      await subscription.cancel();
    });

    test('wifiConnected emitted synchronously from inside the native invoke '
        'call still ends the stream at wifiConnected — never a stuck '
        'spinner waiting for an event that already happened', () async {
      final bridge = _FakeBridge();
      bridge.onSendWifiCredentialsInvoked = () {
        bridge.wifiEvents.add({'event': 'wifiConnected'});
      };
      final transport = AndroidBleOnboardingTransport(
        developmentProofOfPossession: configuredTestValue(),
        bridge: bridge,
      );
      await _connectAndSecure(transport);

      // If this event were lost, .toList() below would never complete —
      // this test would hang/time out instead of failing fast, exactly
      // matching the "stuck on Conectando..." symptom in the bug report.
      final progress = await transport
          .sendWifiCredentials('home-network', 'password')
          .toList();

      expect(
        progress,
        isEmpty,
        reason: 'wifiConnected never itself yields a progress value',
      );
    });

    test('a failure emitted synchronously from inside the native invoke call '
        'is still received, surfaced as WifiProvisioningException, and '
        'releases the BLE connection', () async {
      final bridge = _FakeBridge();
      bridge.onSendWifiCredentialsInvoked = () {
        bridge.wifiEvents.add({'event': 'wifiFailed', 'reason': 'authFailed'});
      };
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
            WifiProvisioningFailureReason.authFailed,
          ),
        ),
      );
      expect(bridge.calls.last, 'disconnect');
    });

    test(
      'the native event subscription is already active at the exact '
      'moment the native invoke call is sent — not established afterward',
      () async {
        final bridge = _FakeBridge();
        var listenerActiveWhenInvoked = false;
        bridge.onSendWifiCredentialsInvoked = () {
          // Checked from inside invoke() itself, before its own Future
          // even resolves — this is the earliest possible moment the real
          // native side could fire an event, per the class doc.
          listenerActiveWhenInvoked = bridge.wifiEvents.hasListener;
        };
        final transport = AndroidBleOnboardingTransport(
          developmentProofOfPossession: configuredTestValue(),
          bridge: bridge,
        );
        await _connectAndSecure(transport);

        final subscription = transport
            .sendWifiCredentials('home-network', 'password')
            .listen((_) {});
        await Future<void>.delayed(Duration.zero);

        expect(bridge.calls, contains('sendWifiCredentials'));
        expect(
          listenerActiveWhenInvoked,
          isTrue,
          reason:
              'wifiProvisioningEvents must already have a listener before '
              'the native sendWifiCredentials call is ever sent',
        );
        await subscription.cancel();
      },
    );
  });

  test('cancelling the returned stream cancels the native event subscription '
      '— never leaves it listening underneath a dropped attempt', () async {
    final bridge = _FakeBridge();
    final transport = AndroidBleOnboardingTransport(
      developmentProofOfPossession: configuredTestValue(),
      bridge: bridge,
    );
    await _connectAndSecure(transport);

    final subscription = transport
        .sendWifiCredentials('home-network', 'password')
        .listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(bridge.wifiEvents.hasListener, isTrue);

    await subscription.cancel();

    expect(
      bridge.wifiEvents.hasListener,
      isFalse,
      reason:
          'cancelling the caller-facing stream must release the native '
          'listener too, not leave it subscribed with nothing consuming it',
    );
  });

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
