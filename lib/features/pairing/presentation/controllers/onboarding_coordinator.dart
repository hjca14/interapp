import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:interapp/features/pairing/domain/entities/claim_session.dart';
import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';
import 'package:interapp/features/pairing/domain/entities/onboarding_state.dart';
import 'package:interapp/features/pairing/domain/entities/setup_code.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';
import 'package:interapp/features/pairing/domain/repositories/onboarding_claim_repository.dart';
import 'package:interapp/features/pairing/domain/services/onboarding_analytics.dart';

/// Drives the whole onboarding flow — nearby BLE discovery (primary), QR
/// `setup_code`, and manual `setup_code` (fallbacks) — through one state
/// machine, per PROJECT_CONTEXT.md, "Onboarding".
///
/// Screens never talk to [BleOnboardingTransport]/[OnboardingClaimRepository]
/// directly; they only read [state] and call methods here. Both fallback
/// paths resolve into the exact same BLE scan/connect/Wi-Fi/claim sequence
/// the primary path uses — QR/manual entry only answers "which device",
/// never skips physically talking to it.
class OnboardingCoordinator extends ChangeNotifier {
  OnboardingCoordinator({
    required this._bleTransport,
    required this._claimRepository,
    required this._analytics,
    this._scanTimeout = const Duration(seconds: 20),
  });

  final BleOnboardingTransport _bleTransport;
  final OnboardingClaimRepository _claimRepository;
  final OnboardingAnalytics _analytics;

  /// How long [OnboardingPhase.scanningBle] waits with zero discovered
  /// devices before failing with [OnboardingFailureKind.scanTimeout].
  /// Injectable so tests don't need a real 20-second wait.
  final Duration _scanTimeout;

  StreamSubscription<DiscoveredInterBridge>? _scanSubscription;
  Timer? _scanTimeoutTimer;

  OnboardingState _state = const OnboardingState();
  OnboardingState get state => _state;

  void _setState(OnboardingState next) {
    _state = next;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Primary: nearby BLE discovery
  // ---------------------------------------------------------------------

  /// Entry point from the "Adicionar InterBridge" intro screen.
  Future<void> startBleOnboarding() async {
    _analytics.track('onboarding_started');
    _setState(const OnboardingState(phase: OnboardingPhase.checkingSetupMode));
    await _checkAvailabilityAndScan();
  }

  Future<void> _checkAvailabilityAndScan() async {
    final issue = await _bleTransport.checkAvailability();
    if (issue != null) {
      _fail(OnboardingFailureKind.bleUnavailable, _bleIssueMessage(issue));
      return;
    }
    _startScan();
  }

  void _startScan() {
    _analytics.track('ble_scan_started');
    _setState(_state.copyWith(phase: OnboardingPhase.scanningBle, discoveredDevices: const []));
    unawaited(_scanSubscription?.cancel());
    _scanTimeoutTimer?.cancel();
    _scanSubscription = _bleTransport.scanForProvisioningDevices().listen(
      _onDeviceDiscovered,
      onError: (Object _, StackTrace _) {
        _fail(OnboardingFailureKind.bleUnavailable, 'Não foi possível procurar dispositivos por Bluetooth.');
      },
    );
    _scanTimeoutTimer = Timer(_scanTimeout, () {
      if (_state.phase == OnboardingPhase.scanningBle && _state.discoveredDevices.isEmpty) {
        _fail(OnboardingFailureKind.scanTimeout, 'Nenhum InterBridge encontrado por perto.');
      }
    });
  }

  void _onDeviceDiscovered(DiscoveredInterBridge device) {
    if (_state.discoveredDevices.contains(device)) return;
    _analytics.track('device_discovered');
    final updated = [..._state.discoveredDevices, device];
    final nextPhase = _state.phase == OnboardingPhase.scanningBle
        ? OnboardingPhase.deviceFound
        : _state.phase;
    _setState(_state.copyWith(phase: nextPhase, discoveredDevices: updated));
  }

  Future<void> stopBleScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _scanTimeoutTimer?.cancel();
    await _bleTransport.stopScan();
  }

  /// User tapped a device from the discovery list.
  void selectDevice(DiscoveredInterBridge device) {
    _setState(_state.copyWith(phase: OnboardingPhase.confirmingDevice, selectedDevice: device));
  }

  /// "Não é este" — keep the devices already found, drop the wrong pick.
  void rejectSelectedDevice() {
    _setState(
      OnboardingState(
        phase: _state.discoveredDevices.isEmpty ? OnboardingPhase.scanningBle : OnboardingPhase.deviceFound,
        discoveredDevices: _state.discoveredDevices,
      ),
    );
  }

  /// "Sim, continuar".
  Future<void> confirmDevice() async {
    final device = _state.selectedDevice;
    if (device == null) return;
    _analytics.track('device_confirmed');
    await stopBleScan();
    _setState(_state.copyWith(phase: OnboardingPhase.connectingBle));
    try {
      await _bleTransport.connect(device.deviceId);
      await _bleTransport.establishSecureSession();
    } catch (_) {
      _fail(OnboardingFailureKind.connectionFailed, 'Não foi possível conectar ao InterBridge.');
      return;
    }
    _analytics.track('ble_connected');
    _setState(_state.copyWith(phase: OnboardingPhase.selectingWifi));
  }

  Future<void> submitWifi(String ssid, String password) async {
    if (ssid.trim().isEmpty) return;
    _setState(_state.copyWith(phase: OnboardingPhase.sendingWifi));
    try {
      await _bleTransport.sendWifiCredentials(ssid, password);
    } catch (_) {
      _fail(OnboardingFailureKind.wifiFailed, 'Não foi possível enviar a configuração de Wi-Fi.');
      return;
    }
    _analytics.track('wifi_config_sent');
    await _startOrContinueClaim();
  }

  Future<void> _startOrContinueClaim() async {
    final device = _state.selectedDevice;
    if (device == null) {
      _fail(OnboardingFailureKind.unknown, 'Algo deu errado. Tente novamente.');
      return;
    }
    var session = _state.claimSession;
    if (session == null || session.deviceId != device.deviceId || session.isExpired) {
      _setState(_state.copyWith(phase: OnboardingPhase.startingClaim));
      try {
        session = await _claimRepository.start(deviceId: device.deviceId);
      } on OnboardingClaimException catch (e) {
        _failClaim(e.reason);
        return;
      }
      _analytics.track('claim_started');
    }
    _setState(_state.copyWith(phase: OnboardingPhase.claimActive, claimSession: session));
    await _runProvisioning(session);
  }

  Future<void> _runProvisioning(ClaimSession session) async {
    _setState(_state.copyWith(phase: OnboardingPhase.awsProvisioning));
    _analytics.track('provisioning_started');
    try {
      await _bleTransport.sendFleetProvisioningMaterial({'claim_session_id': session.claimSessionId});
    } catch (_) {
      _fail(OnboardingFailureKind.claimFailed, 'O InterBridge não conseguiu concluir o provisionamento.');
      return;
    }
    _setState(_state.copyWith(phase: OnboardingPhase.verifyingDevice));
    try {
      final completed = await _claimRepository.complete(session.claimSessionId);
      _setState(_state.copyWith(phase: OnboardingPhase.success, claimSession: completed));
      _analytics.track('onboarding_completed');
      unawaited(_bleTransport.disconnect());
    } on OnboardingClaimException catch (e) {
      _failClaim(e.reason);
    }
  }

  // ---------------------------------------------------------------------
  // Fallback: QR setup_code
  // ---------------------------------------------------------------------

  void startQrFallback() {
    _analytics.track('fallback_qr_used');
    _setState(_state.copyWith(phase: OnboardingPhase.scanningQr));
  }

  Future<void> submitQrPayload(String raw) async {
    final code = parseSetupCodeQrPayload(raw);
    if (code == null) {
      _fail(OnboardingFailureKind.invalidOrExpiredCode, _claimFailureMessage(OnboardingFailureKind.invalidOrExpiredCode));
      return;
    }
    await _resolveSetupCode(code);
  }

  // ---------------------------------------------------------------------
  // Fallback: manual setup_code
  // ---------------------------------------------------------------------

  void startManualFallback() {
    _analytics.track('fallback_manual_used');
    _setState(_state.copyWith(phase: OnboardingPhase.enteringSetupCode));
  }

  /// Returns `false` (and leaves the phase as-is) for a locally-invalid
  /// code, so the entry screen can show inline validation instead of a full
  /// error phase — matches how the rest of the app treats form errors.
  Future<bool> submitManualCode(String rawInput) async {
    final code = SetupCode.tryParse(rawInput);
    if (code == null) return false;
    await _resolveSetupCode(code);
    return true;
  }

  Future<void> _resolveSetupCode(SetupCode code) async {
    _setState(_state.copyWith(phase: OnboardingPhase.resolvingSetupCode));
    try {
      final session = await _claimRepository.resolveSetupCode(code);
      // Converge into the same BLE path the primary flow uses — QR/manual
      // only ever answers "which device", never skips physical BLE
      // presence.
      _setState(OnboardingState(phase: OnboardingPhase.checkingSetupMode, claimSession: session));
      await _checkAvailabilityAndScan();
    } on OnboardingClaimException catch (e) {
      _failClaim(e.reason);
    }
  }

  // ---------------------------------------------------------------------
  // Cancel / retry
  // ---------------------------------------------------------------------

  Future<void> cancel() async {
    final session = _state.claimSession;
    await stopBleScan();
    await _bleTransport.disconnect();
    if (session != null && session.status == ClaimSessionStatus.active) {
      try {
        await _claimRepository.cancel(session.claimSessionId);
      } catch (_) {
        // Best-effort — cancelling shouldn't block the user from leaving.
      }
    }
    _setState(const OnboardingState());
  }

  /// Context-aware retry from [OnboardingPhase.error], per "Retry/recovery":
  /// BLE scan retry, BLE reconnect, Wi-Fi password retry, claim restart,
  /// device-provisioning retry.
  Future<void> retry() async {
    final kind = _state.failureKind;
    final selectedDevice = _state.selectedDevice;
    final claimSession = _state.claimSession;
    switch (kind) {
      case OnboardingFailureKind.bleUnavailable:
      case OnboardingFailureKind.scanTimeout:
        await startBleOnboarding();
      case OnboardingFailureKind.connectionFailed:
        _setState(const OnboardingState(phase: OnboardingPhase.scanningBle));
        _startScan();
      case OnboardingFailureKind.wifiFailed:
      case OnboardingFailureKind.claimFailed:
        _setState(
          OnboardingState(
            phase: OnboardingPhase.selectingWifi,
            selectedDevice: selectedDevice,
            claimSession: claimSession,
          ),
        );
      case OnboardingFailureKind.invalidOrExpiredCode:
      case OnboardingFailureKind.rateLimited:
        _setState(const OnboardingState(phase: OnboardingPhase.enteringSetupCode));
      case OnboardingFailureKind.alreadyOwned:
      case OnboardingFailureKind.unknown:
      case null:
        _setState(const OnboardingState());
    }
  }

  // ---------------------------------------------------------------------
  // Failure helpers
  // ---------------------------------------------------------------------

  void _fail(OnboardingFailureKind kind, String reason) {
    _analytics.track('onboarding_failed', {'kind': kind.name});
    _setState(_state.copyWith(phase: OnboardingPhase.error, failureKind: kind, failureReason: reason));
  }

  void _failClaim(OnboardingClaimFailureReason reason) {
    final kind = switch (reason) {
      OnboardingClaimFailureReason.backendUnavailable => OnboardingFailureKind.claimFailed,
      OnboardingClaimFailureReason.invalidOrExpiredCode => OnboardingFailureKind.invalidOrExpiredCode,
      OnboardingClaimFailureReason.alreadyOwned => OnboardingFailureKind.alreadyOwned,
      OnboardingClaimFailureReason.rateLimited => OnboardingFailureKind.rateLimited,
    };
    _fail(kind, _claimFailureMessage(kind));
  }

  String _bleIssueMessage(BleAvailabilityIssue issue) {
    switch (issue) {
      case BleAvailabilityIssue.bluetoothDisabled:
        return 'Ative o Bluetooth do seu celular para continuar.';
      case BleAvailabilityIssue.permissionDenied:
        return 'Permita o acesso ao Bluetooth para continuar.';
      case BleAvailabilityIssue.unsupported:
        return 'A busca por Bluetooth ainda não está disponível neste aplicativo.';
    }
  }

  /// Deliberately generic for [OnboardingFailureKind.invalidOrExpiredCode]/
  /// [OnboardingFailureKind.alreadyOwned] — never reveals *why* a code
  /// didn't work, per "Do not expose device-enumeration information" /
  /// "Do not say whether the code belongs to another specific user".
  String _claimFailureMessage(OnboardingFailureKind kind) {
    switch (kind) {
      case OnboardingFailureKind.alreadyOwned:
        return 'Este InterBridge já está associado a uma conta.';
      case OnboardingFailureKind.invalidOrExpiredCode:
        return 'Não foi possível localizar ou adicionar esse dispositivo.';
      case OnboardingFailureKind.rateLimited:
        return 'Muitas tentativas. Aguarde um pouco antes de tentar de novo.';
      case OnboardingFailureKind.bleUnavailable:
      case OnboardingFailureKind.scanTimeout:
      case OnboardingFailureKind.connectionFailed:
      case OnboardingFailureKind.wifiFailed:
      case OnboardingFailureKind.claimFailed:
      case OnboardingFailureKind.unknown:
        return 'Não foi possível concluir a configuração agora. Tente novamente.';
    }
  }

  @override
  void dispose() {
    unawaited(_scanSubscription?.cancel());
    _scanTimeoutTimer?.cancel();
    super.dispose();
  }
}
