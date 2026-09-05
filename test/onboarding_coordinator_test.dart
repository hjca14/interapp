import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/pairing/domain/entities/claim_session.dart';
import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';
import 'package:interapp/features/pairing/domain/entities/onboarding_state.dart';
import 'package:interapp/features/pairing/domain/entities/setup_code.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/domain/repositories/onboarding_claim_repository.dart';
import 'package:interapp/features/pairing/domain/services/onboarding_analytics.dart';
import 'package:interapp/features/pairing/presentation/controllers/onboarding_coordinator.dart';

class _RecordingAnalytics implements OnboardingAnalytics {
  final events = <String>[];

  @override
  void track(String event, [Map<String, Object?>? properties]) =>
      events.add(event);
}

class _FakeBleTransport implements BleOnboardingTransport {
  BleAvailabilityIssue? availabilityIssue;
  List<DiscoveredInterBridge> devicesToDiscover = [];
  Object? scanError;
  Object? connectError;
  Object? secureSessionError;

  /// Thrown directly (e.g. an [UnimplementedError] or a generic
  /// [Exception]) from `sendWifiCredentials` before any progress is
  /// emitted. Mutually exclusive with [wifiFailureReason]/[wifiProgress]
  /// below — set at most one failure mode per test.
  Object? wifiError;

  /// Emitted as a [WifiProvisioningException] after [wifiProgress] has
  /// already been yielded, simulating a device-reported failure
  /// (`provisioningFailedFromDevice`/`wifiConfigFailed`/etc.) instead of a
  /// transport-level one.
  WifiProvisioningFailureReason? wifiFailureReason;

  /// Progress events yielded before success/[wifiFailureReason] — defaults
  /// to the two real SDK steps.
  List<WifiProvisioningProgress> wifiProgress = const [
    WifiProvisioningProgress.sendingConfig,
    WifiProvisioningProgress.applyingConfig,
  ];

  int connectCallCount = 0;
  int stopScanCallCount = 0;
  int disconnectCallCount = 0;
  int sendWifiCallCount = 0;

  /// Every ssid/password [sendWifiCredentials] was actually called with, in
  /// order — lets tests confirm the right value reached the transport on
  /// each attempt without the coordinator itself ever needing to store one.
  final wifiCallArguments = <(String ssid, String password)>[];

  /// Every BLE operation invoked, in call order — lets tests assert the
  /// mandatory scan → connect → Security 1 → Wi-Fi sequence directly,
  /// instead of only checking each step happened somewhere.
  final operationLog = <String>[];

  @override
  Future<BleAvailabilityIssue?> checkAvailability() async => availabilityIssue;

  @override
  Stream<DiscoveredInterBridge> scanForProvisioningDevices() {
    operationLog.add('scan');
    if (scanError != null) {
      return Stream.error(scanError!);
    }
    return Stream.fromIterable(devicesToDiscover);
  }

  @override
  Future<void> stopScan() async => stopScanCallCount++;

  @override
  Future<void> connect(String transportId) async {
    connectCallCount++;
    operationLog.add('connect');
    if (connectError != null) {
      throw connectError!;
    }
  }

  @override
  Future<void> establishSecureSession() async {
    operationLog.add('establishSecureSession');
    if (secureSessionError != null) throw secureSessionError!;
  }

  @override
  Future<void> requestIdentifyBlink() async {}

  /// When set, `sendWifiCredentials` pauses right after being called and
  /// before yielding/failing anything, until this completes — lets a test
  /// pause mid-flight (e.g. to call `cancel()`) and then observe how the
  /// coordinator reacts to a late outcome arriving after that.
  Completer<void>? wifiGate;

  @override
  Stream<WifiProvisioningProgress> sendWifiCredentials(
    String ssid,
    String password,
  ) async* {
    sendWifiCallCount++;
    operationLog.add('sendWifiCredentials');
    wifiCallArguments.add((ssid, password));
    if (wifiGate != null) {
      await wifiGate!.future;
    }
    if (wifiError != null) {
      throw wifiError!;
    }
    for (final step in wifiProgress) {
      yield step;
    }
    if (wifiFailureReason != null) {
      throw WifiProvisioningException(wifiFailureReason!);
    }
  }

  @override
  Future<void> sendFleetProvisioningMaterial(
    Map<String, dynamic> material,
  ) async {}

  @override
  Future<void> disconnect() async => disconnectCallCount++;
}

class _FakeClaimRepository implements OnboardingClaimRepository {
  OnboardingClaimFailureReason? startFailure;
  OnboardingClaimFailureReason? resolveFailure;
  bool resolvedSessionExpired = false;
  String resolvedDeviceId = 'ib-resolved';
  int startCallCount = 0;
  int cancelCallCount = 0;
  String? lastCancelledSessionId;

  ClaimSession _session(String deviceId, {required bool expired}) {
    return ClaimSession(
      claimSessionId: 'claim-$deviceId-$startCallCount',
      deviceId: deviceId,
      userId: 'user-1',
      expiresAt: expired
          ? DateTime.now().toUtc().subtract(const Duration(minutes: 1))
          : DateTime.now().toUtc().add(const Duration(minutes: 10)),
      status: ClaimSessionStatus.active,
    );
  }

  @override
  Future<ClaimSession> start({required String deviceId}) async {
    startCallCount++;
    if (startFailure != null) {
      throw OnboardingClaimException(startFailure!);
    }
    return _session(deviceId, expired: false);
  }

  @override
  Future<ClaimSession> resolveSetupCode(SetupCode setupCode) async {
    if (resolveFailure != null) {
      throw OnboardingClaimException(resolveFailure!);
    }
    return _session(resolvedDeviceId, expired: resolvedSessionExpired);
  }

  @override
  Future<ClaimSession> complete(String claimSessionId) async {
    return ClaimSession(
      claimSessionId: claimSessionId,
      deviceId: resolvedDeviceId,
      userId: 'user-1',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      status: ClaimSessionStatus.completed,
    );
  }

  @override
  Future<void> cancel(String claimSessionId) async {
    cancelCallCount++;
    lastCancelledSessionId = claimSessionId;
  }
}

const _deviceA = DiscoveredInterBridge(
  transportId: 'ble-handle-a',
  friendlyName: 'InterBridge-AAAA',
);
const _deviceB = DiscoveredInterBridge(
  transportId: 'ble-handle-b',
  friendlyName: 'InterBridge-BBBB',
);

OnboardingCoordinator _coordinator({
  _FakeBleTransport? ble,
  _FakeClaimRepository? claim,
  _RecordingAnalytics? analytics,
  Duration scanTimeout = const Duration(milliseconds: 30),
}) {
  return OnboardingCoordinator(
    bleTransport: ble ?? _FakeBleTransport(),
    claimRepository: claim ?? _FakeClaimRepository(),
    analytics: analytics ?? _RecordingAnalytics(),
    scanTimeout: scanTimeout,
  );
}

void main() {
  test('the primary path runs scan, connect, Security 1, then Wi-Fi in that '
      'order, stops at wifiConnected honestly (never success/claim), and '
      'never uses its BLE transport handle as product identity', () async {
    final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA];
    final claim = _FakeClaimRepository()
      ..resolvedDeviceId = 'ib-authenticated-a'
      ..startFailure = OnboardingClaimFailureReason.backendUnavailable;
    final analytics = _RecordingAnalytics();
    final coordinator = _coordinator(
      ble: ble,
      claim: claim,
      analytics: analytics,
    );

    expect(coordinator.state.phase, OnboardingPhase.idle);

    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.state.phase, OnboardingPhase.deviceFound);
    expect(coordinator.state.discoveredDevices, [_deviceA]);

    coordinator.selectDevice(_deviceA);
    expect(coordinator.state.phase, OnboardingPhase.confirmingDevice);

    await coordinator.confirmDevice();
    expect(coordinator.state.phase, OnboardingPhase.selectingWifi);
    expect(ble.connectCallCount, 1);

    await coordinator.submitWifi('home-network', 'secret-password');

    expect(coordinator.state.phase, OnboardingPhase.wifiConnected);
    expect(OnboardingPhase.wifiConnected.isTerminal, isTrue);
    // Deliberately never success/claimActive/awsProvisioning — permanent
    // claim, identity, Fleet Provisioning and AWS are a later phase.
    expect(coordinator.state.failureKind, isNull);
    expect(claim.startCallCount, 0);
    expect(
      ble.operationLog,
      containsAllInOrder([
        'scan',
        'connect',
        'establishSecureSession',
        'sendWifiCredentials',
      ]),
    );
    expect(ble.wifiCallArguments, [('home-network', 'secret-password')]);
    expect(
      analytics.events,
      containsAllInOrder([
        'onboarding_started',
        'ble_scan_started',
        'device_discovered',
        'device_confirmed',
        'ble_connected',
        'wifi_connected',
      ]),
    );
    // The BLE session's job ends the moment Wi-Fi connects — nothing is
    // left holding the connection open.
    expect(ble.disconnectCallCount, 1);
  });

  test(
    'Bluetooth disabled surfaces a bleUnavailable error without scanning',
    () async {
      final ble = _FakeBleTransport()
        ..availabilityIssue = BleAvailabilityIssue.bluetoothDisabled;
      final coordinator = _coordinator(ble: ble);

      await coordinator.startBleOnboarding();

      expect(coordinator.state.phase, OnboardingPhase.error);
      expect(
        coordinator.state.failureKind,
        OnboardingFailureKind.bleUnavailable,
      );
    },
  );

  test('permission denied surfaces a bleUnavailable error', () async {
    final ble = _FakeBleTransport()
      ..availabilityIssue = BleAvailabilityIssue.permissionDenied;
    final coordinator = _coordinator(ble: ble);

    await coordinator.startBleOnboarding();

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(coordinator.state.failureKind, OnboardingFailureKind.bleUnavailable);
  });

  test('zero devices found times out into a scanTimeout error', () async {
    final coordinator = _coordinator(
      scanTimeout: const Duration(milliseconds: 10),
    );

    await coordinator.startBleOnboarding();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(coordinator.state.failureKind, OnboardingFailureKind.scanTimeout);
  });

  test('one device found is listed', () async {
    final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA];
    final coordinator = _coordinator(ble: ble);

    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.state.discoveredDevices, [_deviceA]);
  });

  test('multiple devices found are all listed', () async {
    final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA, _deviceB];
    final coordinator = _coordinator(ble: ble);

    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.state.discoveredDevices, [_deviceA, _deviceB]);
  });

  test('a scan stream error surfaces a bleUnavailable failure', () async {
    final ble = _FakeBleTransport()..scanError = Exception('adapter error');
    final coordinator = _coordinator(ble: ble);

    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(coordinator.state.failureKind, OnboardingFailureKind.bleUnavailable);
  });

  test(
    'rejecting the wrong device goes back to the list without losing it',
    () async {
      final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA, _deviceB];
      final coordinator = _coordinator(ble: ble);
      await coordinator.startBleOnboarding();
      await Future<void>.delayed(Duration.zero);
      coordinator.selectDevice(_deviceA);

      coordinator.rejectSelectedDevice();

      expect(coordinator.state.phase, OnboardingPhase.deviceFound);
      expect(coordinator.state.selectedDevice, isNull);
      expect(coordinator.state.discoveredDevices, [_deviceA, _deviceB]);
    },
  );

  test('a BLE connection failure surfaces a connectionFailed error', () async {
    final ble = _FakeBleTransport()
      ..devicesToDiscover = [_deviceA]
      ..connectError = Exception('connection dropped');
    final coordinator = _coordinator(ble: ble);
    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);
    coordinator.selectDevice(_deviceA);

    await coordinator.confirmDevice();

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(
      coordinator.state.failureKind,
      OnboardingFailureKind.connectionFailed,
    );
    expect(
      coordinator.state.failureReason,
      'Não foi possível conectar ao InterBridge. Verifique se o '
      'dispositivo selecionado está em modo de configuração e tente '
      'novamente.',
    );
    expect(ble.disconnectCallCount, 1);
  });

  test('a Security 1 or PoP failure disconnects and fails connection before '
      'ever reaching selectingWifi — this is exactly the shape of iOS\'s real '
      'failure mode, where ESPDevice.connect() runs the handshake itself '
      'inside establishSecureSession, so a bad PoP surfaces here and never '
      'lets the user reach the Wi-Fi form at all. Must show the exact same '
      'message as Android\'s reclassified sessionFailed case below — same '
      'conceptual failure, same wording on both platforms', () async {
    final ble = _FakeBleTransport()
      ..devicesToDiscover = [_deviceA]
      ..secureSessionError = Exception('sanitized handshake failure');
    final coordinator = _coordinator(ble: ble);
    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);
    coordinator.selectDevice(_deviceA);

    await coordinator.confirmDevice();

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(
      coordinator.state.failureKind,
      OnboardingFailureKind.connectionFailed,
    );
    expect(
      coordinator.state.failureReason,
      'Não foi possível conectar ao InterBridge. Verifique se o '
      'dispositivo selecionado está em modo de configuração e tente '
      'novamente.',
    );
    expect(coordinator.state.failureReason, isNot(contains('PoP')));
    expect(coordinator.state.failureReason, isNot(contains('chave')));
    expect(coordinator.state.failureReason, isNot(contains('Security')));
    expect(coordinator.state.failureReason, isNot(contains('Wi-Fi')));
    expect(ble.disconnectCallCount, 1);
    expect(ble.sendWifiCallCount, 0);
  });

  test(
    'an empty Wi-Fi SSID is rejected locally, without contacting the backend',
    () async {
      final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA];
      final coordinator = _coordinator(ble: ble);
      await coordinator.startBleOnboarding();
      await Future<void>.delayed(Duration.zero);
      coordinator.selectDevice(_deviceA);
      await coordinator.confirmDevice();

      await coordinator.submitWifi('', 'password');

      expect(coordinator.state.phase, OnboardingPhase.selectingWifi);
    },
  );

  test('a device-reported Wi-Fi failure surfaces a specific, actionable '
      'wifiFailed error and never includes the password', () async {
    const password = 'super-secret-wifi-password';
    final ble = _FakeBleTransport()
      ..devicesToDiscover = [_deviceA]
      ..wifiFailureReason = WifiProvisioningFailureReason.authFailed;
    final coordinator = _coordinator(ble: ble);
    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);
    coordinator.selectDevice(_deviceA);
    await coordinator.confirmDevice();

    await coordinator.submitWifi('home-network', password);

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(coordinator.state.failureKind, OnboardingFailureKind.wifiFailed);
    expect(coordinator.state.failureReason, isNot(contains(password)));
    expect(coordinator.state.failureReason, contains('Senha'));
  });

  test('a generic Wi-Fi send failure (not device-classified) also surfaces '
      'wifiFailed, with a generic message', () async {
    final ble = _FakeBleTransport()
      ..devicesToDiscover = [_deviceA]
      ..wifiError = Exception('send failed');
    final coordinator = _coordinator(ble: ble);
    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);
    coordinator.selectDevice(_deviceA);
    await coordinator.confirmDevice();

    await coordinator.submitWifi('home-network', 'password');

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(coordinator.state.failureKind, OnboardingFailureKind.wifiFailed);
    expect(ble.disconnectCallCount, 1);
  });

  test(
    'a sessionFailed reported during sendWifiCredentials (Android\'s '
    'Security 1/PoP handshake, which the official SDK only runs inside '
    'ESPDevice.provision) is reclassified as connectionFailed, with a '
    'connection message — never wifiFailed or any Wi-Fi-flavored wording',
    () async {
      final ble = _FakeBleTransport()
        ..devicesToDiscover = [_deviceA]
        ..wifiFailureReason = WifiProvisioningFailureReason.sessionFailed;
      final coordinator = _coordinator(ble: ble);
      await coordinator.startBleOnboarding();
      await Future<void>.delayed(Duration.zero);
      coordinator.selectDevice(_deviceA);
      await coordinator.confirmDevice();

      await coordinator.submitWifi('home-network', 'password');

      expect(coordinator.state.phase, OnboardingPhase.error);
      expect(
        coordinator.state.failureKind,
        OnboardingFailureKind.connectionFailed,
      );
      expect(
        coordinator.state.failureReason,
        'Não foi possível conectar ao InterBridge. Verifique se o '
        'dispositivo selecionado está em modo de configuração e tente '
        'novamente.',
      );
      expect(coordinator.state.failureReason, isNot(contains('Wi-Fi')));
      expect(coordinator.state.failureReason, isNot(contains('Security')));
      expect(coordinator.state.failureReason, isNot(contains('senha')));
      expect(ble.disconnectCallCount, 1);
    },
  );

  test(
    'retrying that reclassified sessionFailed restarts discovery/connection '
    'from scratch — never reuses the failed transportId, and Wi-Fi is only '
    'reachable again after a fresh, real confirmDevice/establishSecureSession',
    () async {
      final ble = _FakeBleTransport()
        ..devicesToDiscover = [_deviceA]
        ..wifiFailureReason = WifiProvisioningFailureReason.sessionFailed;
      final claim = _FakeClaimRepository()
        ..resolvedDeviceId = 'ib-authenticated-a';
      final coordinator = _coordinator(ble: ble, claim: claim);
      coordinator.startManualFallback();
      await coordinator.submitManualCode('482719362051');
      await Future<void>.delayed(Duration.zero);
      coordinator.selectDevice(_deviceA);
      await coordinator.confirmDevice();
      await coordinator.submitWifi('home-network', 'wrong-pop-on-device');
      expect(
        coordinator.state.failureKind,
        OnboardingFailureKind.connectionFailed,
      );
      final claimSessionBeforeRetry = coordinator.state.claimSession;
      final connectCallsBeforeRetry = ble.connectCallCount;
      final wifiCallsBeforeRetry = ble.sendWifiCallCount;

      ble.wifiFailureReason = null;
      await coordinator.retry();
      await Future<void>.delayed(Duration.zero);

      // Back to discovery, never straight to selectingWifi/sendingWifi —
      // the old BLE session is gone, so there is nothing to resubmit
      // credentials to yet.
      expect(coordinator.state.phase, OnboardingPhase.deviceFound);
      expect(coordinator.state.discoveredDevices, [_deviceA]);
      expect(coordinator.state.claimSession, claimSessionBeforeRetry);
      expect(ble.connectCallCount, connectCallsBeforeRetry);
      expect(ble.sendWifiCallCount, wifiCallsBeforeRetry);

      // Only a fresh, explicit confirm→connect→Security 1 actually
      // reconnects — retry() itself never does this on the user's behalf.
      coordinator.selectDevice(_deviceA);
      await coordinator.confirmDevice();
      expect(ble.connectCallCount, connectCallsBeforeRetry + 1);
      await coordinator.submitWifi('home-network', 'password');
      expect(coordinator.state.phase, OnboardingPhase.wifiConnected);
    },
  );

  test('a transport that has not implemented Wi-Fi provisioning surfaces '
      'wifiProvisioningNotImplemented and releases BLE', () async {
    final ble = _FakeBleTransport()
      ..devicesToDiscover = [_deviceA]
      ..wifiError = UnimplementedError();
    final coordinator = _coordinator(ble: ble);
    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);
    coordinator.selectDevice(_deviceA);
    await coordinator.confirmDevice();

    await coordinator.submitWifi('home-network', 'password');

    expect(
      coordinator.state.failureKind,
      OnboardingFailureKind.wifiProvisioningNotImplemented,
    );
    expect(ble.disconnectCallCount, 1);
  });

  test('an expired resolved claim session does not block Wi-Fi provisioning — '
      'claim validity is a later phase\'s concern, not checked here', () async {
    final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA];
    final claim = _FakeClaimRepository()
      ..resolvedDeviceId = 'ib-authenticated-a'
      ..resolvedSessionExpired = true
      ..startFailure = OnboardingClaimFailureReason.backendUnavailable;
    final coordinator = _coordinator(ble: ble, claim: claim);

    coordinator.startManualFallback();
    await coordinator.submitManualCode('482719362051');
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.state.claimSession?.isExpired, isTrue);

    coordinator.selectDevice(_deviceA);
    await coordinator.confirmDevice();
    await coordinator.submitWifi('home-network', 'password');

    expect(coordinator.state.phase, OnboardingPhase.wifiConnected);
    expect(claim.startCallCount, 0);
    expect(coordinator.state.claimSession?.isExpired, isTrue);
  });

  test(
    'a valid QR payload resolves the code and converges into BLE scanning',
    () async {
      final claim = _FakeClaimRepository();
      final analytics = _RecordingAnalytics();
      final coordinator = _coordinator(claim: claim, analytics: analytics);

      coordinator.startQrFallback();
      expect(coordinator.state.phase, OnboardingPhase.scanningQr);

      await coordinator.submitQrPayload(
        '{"version": 1, "setup_code": "482719362051"}',
      );
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.state.claimSession, isNotNull);
      expect(coordinator.state.phase, OnboardingPhase.scanningBle);
      expect(analytics.events, contains('fallback_qr_used'));
    },
  );

  test(
    'an unreadable QR payload surfaces an invalidOrExpiredCode error',
    () async {
      final coordinator = _coordinator();
      coordinator.startQrFallback();

      await coordinator.submitQrPayload('not a valid qr payload');

      expect(coordinator.state.phase, OnboardingPhase.error);
      expect(
        coordinator.state.failureKind,
        OnboardingFailureKind.invalidOrExpiredCode,
      );
    },
  );

  test(
    'an invalid manual code is rejected locally, without changing phase',
    () async {
      final coordinator = _coordinator();
      coordinator.startManualFallback();

      final accepted = await coordinator.submitManualCode('123');

      expect(accepted, isFalse);
      expect(coordinator.state.phase, OnboardingPhase.enteringSetupCode);
    },
  );

  test(
    'a valid manual code resolves and converges into BLE scanning',
    () async {
      final analytics = _RecordingAnalytics();
      final coordinator = _coordinator(analytics: analytics);
      coordinator.startManualFallback();

      final accepted = await coordinator.submitManualCode('4827 1936 2051');
      await Future<void>.delayed(Duration.zero);

      expect(accepted, isTrue);
      expect(coordinator.state.claimSession, isNotNull);
      expect(analytics.events, contains('fallback_manual_used'));
    },
  );

  test('a rate-limited code resolution surfaces a rateLimited error', () async {
    final claim = _FakeClaimRepository()
      ..resolveFailure = OnboardingClaimFailureReason.rateLimited;
    final coordinator = _coordinator(claim: claim);
    coordinator.startManualFallback();

    await coordinator.submitManualCode('482719362051');

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(coordinator.state.failureKind, OnboardingFailureKind.rateLimited);
  });

  test(
    'an already-owned device surfaces alreadyOwned, never a silent takeover',
    () async {
      final claim = _FakeClaimRepository()
        ..resolveFailure = OnboardingClaimFailureReason.alreadyOwned;
      final coordinator = _coordinator(claim: claim);
      coordinator.startManualFallback();

      await coordinator.submitManualCode('482719362051');

      expect(coordinator.state.phase, OnboardingPhase.error);
      expect(coordinator.state.failureKind, OnboardingFailureKind.alreadyOwned);
      expect(coordinator.state.claimSession, isNull);
    },
  );

  test('cancel() resets to idle even with nothing in flight', () async {
    final coordinator = _coordinator();
    coordinator.startManualFallback();

    await coordinator.cancel();

    expect(coordinator.state.phase, OnboardingPhase.idle);
  });

  test(
    'cancel() cancels the backend claim session while one is still active',
    () async {
      final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA];
      final claim = _FakeClaimRepository()
        ..resolvedDeviceId = 'ib-authenticated-a';
      final coordinator = _coordinator(ble: ble, claim: claim);
      coordinator.startManualFallback();
      await coordinator.submitManualCode('482719362051');
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.state.claimSession, isNotNull);

      await coordinator.cancel();

      expect(claim.cancelCallCount, 1);
      expect(coordinator.state.phase, OnboardingPhase.idle);
    },
  );

  test(
    'cancel() during an in-flight Wi-Fi send leaves no stuck stream, and a '
    'late outcome arriving after that never resurrects the cancelled state',
    () async {
      final ble = _FakeBleTransport()
        ..devicesToDiscover = [_deviceA]
        ..wifiGate = Completer<void>();
      final coordinator = _coordinator(ble: ble);
      await coordinator.startBleOnboarding();
      await Future<void>.delayed(Duration.zero);
      coordinator.selectDevice(_deviceA);
      await coordinator.confirmDevice();
      final wifiFuture = coordinator.submitWifi('home-network', 'password');
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.state.phase, OnboardingPhase.sendingWifi);

      await coordinator.cancel();
      expect(coordinator.state.phase, OnboardingPhase.idle);

      // The send that was in flight when cancel() ran now resolves late,
      // as either outcome — neither may clobber the already-cancelled
      // idle state.
      ble.wifiGate!.complete();
      await wifiFuture;
      expect(coordinator.state.phase, OnboardingPhase.idle);
    },
  );

  test('retrying a scanTimeout restarts the scan', () async {
    final ble = _FakeBleTransport();
    final coordinator = _coordinator(
      ble: ble,
      scanTimeout: const Duration(milliseconds: 10),
    );
    await coordinator.startBleOnboarding();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(coordinator.state.phase, OnboardingPhase.error);

    ble.devicesToDiscover = [_deviceA];
    await coordinator.retry();
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.state.discoveredDevices, [_deviceA]);
    expect(ble.stopScanCallCount, greaterThanOrEqualTo(2));
    expect(ble.disconnectCallCount, 1);
  });

  test('retrying a wifiFailed error re-scans (never reuses the stale BLE '
      'handle) so the device can be found and reconnected again while still '
      'in its BLE window, preserving any resolved claim session', () async {
    final ble = _FakeBleTransport()
      ..devicesToDiscover = [_deviceA]
      ..wifiFailureReason = WifiProvisioningFailureReason.networkNotFound;
    final claim = _FakeClaimRepository()
      ..resolvedDeviceId = 'ib-authenticated-a';
    final coordinator = _coordinator(ble: ble, claim: claim);
    coordinator.startManualFallback();
    await coordinator.submitManualCode('482719362051');
    await Future<void>.delayed(Duration.zero);
    coordinator.selectDevice(_deviceA);
    await coordinator.confirmDevice();
    await coordinator.submitWifi('home-network', 'wrong-network-name');
    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(ble.disconnectCallCount, 1);
    final claimSessionBeforeRetry = coordinator.state.claimSession;

    ble.wifiFailureReason = null;
    await coordinator.retry();
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.state.phase, OnboardingPhase.deviceFound);
    expect(coordinator.state.discoveredDevices, [_deviceA]);
    expect(coordinator.state.claimSession, claimSessionBeforeRetry);

    // The whole confirm → connect → Wi-Fi path still works from here.
    coordinator.selectDevice(_deviceA);
    await coordinator.confirmDevice();
    await coordinator.submitWifi('home-network', 'password');
    expect(coordinator.state.phase, OnboardingPhase.wifiConnected);
  });

  test(
    'retrying an invalidOrExpiredCode error goes back to manual entry',
    () async {
      final claim = _FakeClaimRepository()
        ..resolveFailure = OnboardingClaimFailureReason.invalidOrExpiredCode;
      final coordinator = _coordinator(claim: claim);
      coordinator.startManualFallback();
      await coordinator.submitManualCode('482719362051');
      expect(coordinator.state.phase, OnboardingPhase.error);

      await coordinator.retry();

      expect(coordinator.state.phase, OnboardingPhase.enteringSetupCode);
    },
  );

  test('success, error and wifiConnected are all terminal phases', () {
    expect(OnboardingPhase.success.isTerminal, isTrue);
    expect(OnboardingPhase.error.isTerminal, isTrue);
    expect(OnboardingPhase.wifiConnected.isTerminal, isTrue);
    expect(OnboardingPhase.selectingWifi.isTerminal, isFalse);
    expect(OnboardingPhase.sendingWifi.isTerminal, isFalse);
  });
}
