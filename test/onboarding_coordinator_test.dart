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
  void track(String event, [Map<String, Object?>? properties]) => events.add(event);
}

class _FakeBleTransport implements BleOnboardingTransport {
  BleAvailabilityIssue? availabilityIssue;
  List<DiscoveredInterBridge> devicesToDiscover = [];
  Object? scanError;
  Object? connectError;
  Object? wifiError;
  int connectCallCount = 0;
  int stopScanCallCount = 0;
  int disconnectCallCount = 0;

  @override
  Future<BleAvailabilityIssue?> checkAvailability() async => availabilityIssue;

  @override
  Stream<DiscoveredInterBridge> scanForProvisioningDevices() {
    if (scanError != null) return Stream.error(scanError!);
    return Stream.fromIterable(devicesToDiscover);
  }

  @override
  Future<void> stopScan() async => stopScanCallCount++;

  @override
  Future<void> connect(String deviceId) async {
    connectCallCount++;
    if (connectError != null) throw connectError!;
  }

  @override
  Future<void> establishSecureSession() async {}

  @override
  Future<void> requestIdentifyBlink() async {}

  @override
  Future<void> sendWifiCredentials(String ssid, String password) async {
    if (wifiError != null) throw wifiError!;
  }

  @override
  Future<void> sendFleetProvisioningMaterial(Map<String, dynamic> material) async {}

  @override
  Future<void> disconnect() async => disconnectCallCount++;
}

class _FakeClaimRepository implements OnboardingClaimRepository {
  OnboardingClaimFailureReason? startFailure;
  OnboardingClaimFailureReason? resolveFailure;
  OnboardingClaimFailureReason? completeFailure;
  bool resolvedSessionExpired = false;
  String resolvedDeviceId = 'ib-resolved';
  Completer<void>? completeGate;
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
    if (startFailure != null) throw OnboardingClaimException(startFailure!);
    return _session(deviceId, expired: false);
  }

  @override
  Future<ClaimSession> resolveSetupCode(SetupCode setupCode) async {
    if (resolveFailure != null) throw OnboardingClaimException(resolveFailure!);
    return _session(resolvedDeviceId, expired: resolvedSessionExpired);
  }

  @override
  Future<ClaimSession> complete(String claimSessionId) async {
    if (completeGate != null) await completeGate!.future;
    if (completeFailure != null) throw OnboardingClaimException(completeFailure!);
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

const _deviceA = DiscoveredInterBridge(deviceId: 'ib-aaaa', friendlyName: 'InterBridge-AAAA');
const _deviceB = DiscoveredInterBridge(deviceId: 'ib-bbbb', friendlyName: 'InterBridge-BBBB');

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
  test('primary BLE onboarding: idle -> ... -> success, with a completed claim session', () async {
    final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA];
    final claim = _FakeClaimRepository()..resolvedDeviceId = _deviceA.deviceId;
    final analytics = _RecordingAnalytics();
    final coordinator = _coordinator(ble: ble, claim: claim, analytics: analytics);

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

    expect(coordinator.state.phase, OnboardingPhase.success);
    expect(coordinator.state.claimSession?.status, ClaimSessionStatus.completed);
    expect(
      analytics.events,
      containsAllInOrder([
        'onboarding_started',
        'ble_scan_started',
        'device_discovered',
        'device_confirmed',
        'ble_connected',
        'wifi_config_sent',
        'claim_started',
        'provisioning_started',
        'onboarding_completed',
      ]),
    );
  });

  test('Bluetooth disabled surfaces a bleUnavailable error without scanning', () async {
    final ble = _FakeBleTransport()..availabilityIssue = BleAvailabilityIssue.bluetoothDisabled;
    final coordinator = _coordinator(ble: ble);

    await coordinator.startBleOnboarding();

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(coordinator.state.failureKind, OnboardingFailureKind.bleUnavailable);
  });

  test('permission denied surfaces a bleUnavailable error', () async {
    final ble = _FakeBleTransport()..availabilityIssue = BleAvailabilityIssue.permissionDenied;
    final coordinator = _coordinator(ble: ble);

    await coordinator.startBleOnboarding();

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(coordinator.state.failureKind, OnboardingFailureKind.bleUnavailable);
  });

  test('zero devices found times out into a scanTimeout error', () async {
    final coordinator = _coordinator(scanTimeout: const Duration(milliseconds: 10));

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

  test('rejecting the wrong device goes back to the list without losing it', () async {
    final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA, _deviceB];
    final coordinator = _coordinator(ble: ble);
    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);
    coordinator.selectDevice(_deviceA);

    coordinator.rejectSelectedDevice();

    expect(coordinator.state.phase, OnboardingPhase.deviceFound);
    expect(coordinator.state.selectedDevice, isNull);
    expect(coordinator.state.discoveredDevices, [_deviceA, _deviceB]);
  });

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
    expect(coordinator.state.failureKind, OnboardingFailureKind.connectionFailed);
  });

  test('an empty Wi-Fi SSID is rejected locally, without contacting the backend', () async {
    final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA];
    final coordinator = _coordinator(ble: ble);
    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);
    coordinator.selectDevice(_deviceA);
    await coordinator.confirmDevice();

    await coordinator.submitWifi('', 'password');

    expect(coordinator.state.phase, OnboardingPhase.selectingWifi);
  });

  test('a Wi-Fi send failure surfaces a wifiFailed error', () async {
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
  });

  test('a claim-start backend failure surfaces claimFailed', () async {
    final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA];
    final claim = _FakeClaimRepository()..startFailure = OnboardingClaimFailureReason.backendUnavailable;
    final coordinator = _coordinator(ble: ble, claim: claim);
    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);
    coordinator.selectDevice(_deviceA);
    await coordinator.confirmDevice();

    await coordinator.submitWifi('home-network', 'password');

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(coordinator.state.failureKind, OnboardingFailureKind.claimFailed);
  });

  test('a claim-completion backend failure surfaces claimFailed', () async {
    final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA];
    final claim = _FakeClaimRepository()..completeFailure = OnboardingClaimFailureReason.backendUnavailable;
    final coordinator = _coordinator(ble: ble, claim: claim);
    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);
    coordinator.selectDevice(_deviceA);
    await coordinator.confirmDevice();

    await coordinator.submitWifi('home-network', 'password');

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(coordinator.state.failureKind, OnboardingFailureKind.claimFailed);
  });

  test('an expired resolved claim session is not reused — a fresh one is started', () async {
    final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA];
    final claim = _FakeClaimRepository()
      ..resolvedDeviceId = _deviceA.deviceId
      ..resolvedSessionExpired = true;
    final coordinator = _coordinator(ble: ble, claim: claim);

    coordinator.startManualFallback();
    await coordinator.submitManualCode('482719362051');
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.state.claimSession?.isExpired, isTrue);

    coordinator.selectDevice(_deviceA);
    await coordinator.confirmDevice();
    await coordinator.submitWifi('home-network', 'password');

    expect(claim.startCallCount, 1);
    expect(coordinator.state.claimSession?.isExpired, isFalse);
    expect(coordinator.state.phase, OnboardingPhase.success);
  });

  test('a valid QR payload resolves the code and converges into BLE scanning', () async {
    final claim = _FakeClaimRepository();
    final analytics = _RecordingAnalytics();
    final coordinator = _coordinator(claim: claim, analytics: analytics);

    coordinator.startQrFallback();
    expect(coordinator.state.phase, OnboardingPhase.scanningQr);

    await coordinator.submitQrPayload('{"version": 1, "setup_code": "482719362051"}');
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.state.claimSession, isNotNull);
    expect(coordinator.state.phase, OnboardingPhase.scanningBle);
    expect(analytics.events, contains('fallback_qr_used'));
  });

  test('an unreadable QR payload surfaces an invalidOrExpiredCode error', () async {
    final coordinator = _coordinator();
    coordinator.startQrFallback();

    await coordinator.submitQrPayload('not a valid qr payload');

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(coordinator.state.failureKind, OnboardingFailureKind.invalidOrExpiredCode);
  });

  test('an invalid manual code is rejected locally, without changing phase', () async {
    final coordinator = _coordinator();
    coordinator.startManualFallback();

    final accepted = await coordinator.submitManualCode('123');

    expect(accepted, isFalse);
    expect(coordinator.state.phase, OnboardingPhase.enteringSetupCode);
  });

  test('a valid manual code resolves and converges into BLE scanning', () async {
    final analytics = _RecordingAnalytics();
    final coordinator = _coordinator(analytics: analytics);
    coordinator.startManualFallback();

    final accepted = await coordinator.submitManualCode('4827 1936 2051');
    await Future<void>.delayed(Duration.zero);

    expect(accepted, isTrue);
    expect(coordinator.state.claimSession, isNotNull);
    expect(analytics.events, contains('fallback_manual_used'));
  });

  test('a rate-limited code resolution surfaces a rateLimited error', () async {
    final claim = _FakeClaimRepository()..resolveFailure = OnboardingClaimFailureReason.rateLimited;
    final coordinator = _coordinator(claim: claim);
    coordinator.startManualFallback();

    await coordinator.submitManualCode('482719362051');

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(coordinator.state.failureKind, OnboardingFailureKind.rateLimited);
  });

  test('an already-owned device surfaces alreadyOwned, never a silent takeover', () async {
    final claim = _FakeClaimRepository()..resolveFailure = OnboardingClaimFailureReason.alreadyOwned;
    final coordinator = _coordinator(claim: claim);
    coordinator.startManualFallback();

    await coordinator.submitManualCode('482719362051');

    expect(coordinator.state.phase, OnboardingPhase.error);
    expect(coordinator.state.failureKind, OnboardingFailureKind.alreadyOwned);
    expect(coordinator.state.claimSession, isNull);
  });

  test('cancel() resets to idle even with nothing in flight', () async {
    final coordinator = _coordinator();
    coordinator.startManualFallback();

    await coordinator.cancel();

    expect(coordinator.state.phase, OnboardingPhase.idle);
  });

  test('cancel() cancels the backend claim session while one is still active', () async {
    final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA];
    final gate = Completer<void>();
    final claim = _FakeClaimRepository()
      ..resolvedDeviceId = _deviceA.deviceId
      ..completeGate = gate;
    final coordinator = _coordinator(ble: ble, claim: claim);
    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);
    coordinator.selectDevice(_deviceA);
    await coordinator.confirmDevice();
    final wifiFuture = coordinator.submitWifi('home-network', 'password');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(coordinator.state.claimSession, isNotNull);

    await coordinator.cancel();

    expect(claim.cancelCallCount, 1);
    expect(coordinator.state.phase, OnboardingPhase.idle);

    gate.complete();
    await wifiFuture;
  });

  test('retrying a scanTimeout restarts the scan', () async {
    final ble = _FakeBleTransport();
    final coordinator = _coordinator(ble: ble, scanTimeout: const Duration(milliseconds: 10));
    await coordinator.startBleOnboarding();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(coordinator.state.phase, OnboardingPhase.error);

    ble.devicesToDiscover = [_deviceA];
    await coordinator.retry();
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.state.discoveredDevices, [_deviceA]);
  });

  test('retrying an invalidOrExpiredCode error goes back to manual entry', () async {
    final claim = _FakeClaimRepository()..resolveFailure = OnboardingClaimFailureReason.invalidOrExpiredCode;
    final coordinator = _coordinator(claim: claim);
    coordinator.startManualFallback();
    await coordinator.submitManualCode('482719362051');
    expect(coordinator.state.phase, OnboardingPhase.error);

    await coordinator.retry();

    expect(coordinator.state.phase, OnboardingPhase.enteringSetupCode);
  });

  test('reaching success is the terminal, navigable state', () async {
    final ble = _FakeBleTransport()..devicesToDiscover = [_deviceA];
    final claim = _FakeClaimRepository()..resolvedDeviceId = _deviceA.deviceId;
    final coordinator = _coordinator(ble: ble, claim: claim);
    await coordinator.startBleOnboarding();
    await Future<void>.delayed(Duration.zero);
    coordinator.selectDevice(_deviceA);
    await coordinator.confirmDevice();

    await coordinator.submitWifi('home-network', 'password');

    expect(coordinator.state.phase, OnboardingPhase.success);
    expect(OnboardingPhase.success.isTerminal, isTrue);
  });
}
