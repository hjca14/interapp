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
/// paths still require physical BLE presence. Only QR/manual resolution can
/// currently provide an authenticated permanent product identity; a BLE
/// transport handle or advertised name is never sent to a claim API.
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
    _setState(
      _state.copyWith(
        phase: OnboardingPhase.scanningBle,
        discoveredDevices: const [],
      ),
    );
    unawaited(_scanSubscription?.cancel());
    _scanTimeoutTimer?.cancel();
    _scanSubscription = _bleTransport.scanForProvisioningDevices().listen(
      _onDeviceDiscovered,
      onError: (Object _, StackTrace _) {
        unawaited(stopBleScan());
        _fail(
          OnboardingFailureKind.bleUnavailable,
          'Não foi possível procurar dispositivos por Bluetooth.',
        );
      },
    );
    _scanTimeoutTimer = Timer(_scanTimeout, () {
      if (_state.phase == OnboardingPhase.scanningBle &&
          _state.discoveredDevices.isEmpty) {
        unawaited(stopBleScan());
        _fail(
          OnboardingFailureKind.scanTimeout,
          'Nenhum InterBridge encontrado por perto.',
        );
      }
    });
  }

  void _onDeviceDiscovered(DiscoveredInterBridge device) {
    if (_state.discoveredDevices.contains(device)) {
      return;
    }
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
    _setState(
      _state.copyWith(
        phase: OnboardingPhase.confirmingDevice,
        selectedDevice: device,
      ),
    );
  }

  /// "Não é este" — keep the devices already found, drop the wrong pick.
  void rejectSelectedDevice() {
    _setState(
      OnboardingState(
        phase: _state.discoveredDevices.isEmpty
            ? OnboardingPhase.scanningBle
            : OnboardingPhase.deviceFound,
        discoveredDevices: _state.discoveredDevices,
      ),
    );
  }

  /// "Sim, continuar".
  Future<void> confirmDevice() async {
    final device = _state.selectedDevice;
    if (device == null) {
      return;
    }
    _analytics.track('device_confirmed');
    await stopBleScan();
    _setState(_state.copyWith(phase: OnboardingPhase.connectingBle));
    try {
      await _bleTransport.connect(device.transportId);
      await _bleTransport.establishSecureSession();
    } catch (_) {
      await _bleTransport.disconnect();
      _fail(
        OnboardingFailureKind.connectionFailed,
        'Não foi possível conectar ao InterBridge.',
      );
      return;
    }
    _analytics.track('ble_connected');
    _setState(_state.copyWith(phase: OnboardingPhase.selectingWifi));
  }

  /// Sends [ssid]/[password] over the already-secured BLE session and waits
  /// for the device to confirm it joined the network — see
  /// [BleOnboardingTransport.sendWifiCredentials]. Deliberately stops at
  /// [OnboardingPhase.wifiConnected] on success: permanent claim, Fleet
  /// Provisioning and AWS are a later phase (3C.4+), not implemented here,
  /// so this never continues into them and never implies the device is
  /// registered/added.
  Future<void> submitWifi(String ssid, String password) async {
    final trimmedSsid = ssid.trim();
    if (trimmedSsid.isEmpty) {
      return;
    }
    _setState(
      _state.copyWith(
        phase: OnboardingPhase.sendingWifi,
        wifiProvisioningProgress: WifiProvisioningProgress.sendingConfig,
      ),
    );
    try {
      await for (final progress in _bleTransport.sendWifiCredentials(
        trimmedSsid,
        password,
      )) {
        // A concurrent cancel()/dispose() already moved the state away from
        // sendingWifi — never let a late progress event resurrect it.
        if (_state.phase != OnboardingPhase.sendingWifi) return;
        _setState(_state.copyWith(wifiProvisioningProgress: progress));
      }
    } on UnimplementedError {
      if (_state.phase != OnboardingPhase.sendingWifi) return;
      await _bleTransport.disconnect();
      _fail(
        OnboardingFailureKind.wifiProvisioningNotImplemented,
        'A configuração de Wi-Fi ainda não está disponível neste '
        'aplicativo.',
      );
      return;
    } on WifiProvisioningException catch (e) {
      if (_state.phase != OnboardingPhase.sendingWifi) return;
      await _bleTransport.disconnect();
      if (e.reason == WifiProvisioningFailureReason.sessionFailed) {
        // Android-only SDK limitation, not a Wi-Fi problem: the official
        // Espressif SDK only runs the Protocomm Security 1 handshake inside
        // `ESPDevice.provision(...)`, which this transport calls here, on
        // the far side of the user already having filled in the Wi-Fi
        // form — see `AndroidBleOnboardingTransport.establishSecureSession`.
        // A wrong/mismatched PoP therefore surfaces as `sessionFailed` from
        // *this* call, never earlier, even though it is really a BLE
        // connection/authentication failure that happened before any Wi-Fi
        // credential was ever sent. Reported as `connectionFailed` — the
        // same recoverable, generic BLE-connection failure `confirmDevice`
        // already uses — with a connection message, never a Wi-Fi one:
        // showing "wrong password"-flavored UI or tracking `wifiFailed` for
        // a failure that has nothing to do with Wi-Fi would be actively
        // misleading. iOS is unaffected: its SDK runs Security 1 inside
        // `establishSecurity1`, before this screen is ever reached, so a
        // bad PoP there already fails as `connectionFailed` well before
        // `submitWifi` — never a `sessionFailed` here.
        _fail(
          OnboardingFailureKind.connectionFailed,
          'Não foi possível conectar ao InterBridge. Verifique se o '
          'dispositivo selecionado está em modo de configuração e tente '
          'novamente.',
        );
        return;
      }
      _fail(OnboardingFailureKind.wifiFailed, _wifiFailureMessage(e.reason));
      return;
    } catch (_) {
      if (_state.phase != OnboardingPhase.sendingWifi) return;
      await _bleTransport.disconnect();
      _fail(
        OnboardingFailureKind.wifiFailed,
        'Não foi possível enviar a configuração de Wi-Fi.',
      );
      return;
    }
    if (_state.phase != OnboardingPhase.sendingWifi) return;
    _analytics.track('wifi_connected');
    // The BLE session's job ends here — nothing left in this phase needs
    // it, and holding it open would just be an unused connection.
    await _bleTransport.disconnect();
    _setState(
      _state.copyWith(
        phase: OnboardingPhase.wifiConnected,
        wifiProvisioningProgress: null,
      ),
    );
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
      _fail(
        OnboardingFailureKind.invalidOrExpiredCode,
        _claimFailureMessage(OnboardingFailureKind.invalidOrExpiredCode),
      );
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
    if (code == null) {
      return false;
    }
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
      _setState(
        OnboardingState(
          phase: OnboardingPhase.checkingSetupMode,
          claimSession: session,
        ),
      );
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
    await stopBleScan();
    await _bleTransport.disconnect();
    final kind = _state.failureKind;
    final selectedDevice = _state.selectedDevice;
    final claimSession = _state.claimSession;
    switch (kind) {
      case OnboardingFailureKind.bleUnavailable:
      case OnboardingFailureKind.scanTimeout:
        await startBleOnboarding();
      case OnboardingFailureKind.connectionFailed:
        // Discards any BLE session/transportId from the failed attempt —
        // a fresh scan never reuses one — but keeps a QR/manual-resolved
        // claimSession, same as wifiFailed below: this kind now also
        // covers Android's sessionFailed-during-Wi-Fi case (see
        // submitWifi), which can legitimately happen after a QR/manual
        // fallback already resolved which device to claim.
        _setState(
          OnboardingState(
            phase: OnboardingPhase.scanningBle,
            claimSession: claimSession,
          ),
        );
        _startScan();
      case OnboardingFailureKind.wifiFailed:
        // The failed BLE session was already disconnected — the old
        // transportId handle is no longer connectable. Re-scan instead of
        // jumping straight back to selectingWifi: as long as the physical
        // device is still in its BLE provisioning window, discovery finds
        // it again and the normal confirm→connect→selectingWifi path lets
        // the user resubmit credentials, without ever reusing a stale
        // connection or leaking one.
        _setState(
          OnboardingState(
            phase: OnboardingPhase.scanningBle,
            claimSession: claimSession,
          ),
        );
        _startScan();
      case OnboardingFailureKind.wifiProvisioningNotImplemented:
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
      case OnboardingFailureKind.permanentIdentityUnavailable:
        _setState(
          const OnboardingState(phase: OnboardingPhase.enteringSetupCode),
        );
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
    _setState(
      _state.copyWith(
        phase: OnboardingPhase.error,
        failureKind: kind,
        failureReason: reason,
      ),
    );
  }

  void _failClaim(OnboardingClaimFailureReason reason) {
    final kind = switch (reason) {
      OnboardingClaimFailureReason.backendUnavailable =>
        OnboardingFailureKind.claimFailed,
      OnboardingClaimFailureReason.invalidOrExpiredCode =>
        OnboardingFailureKind.invalidOrExpiredCode,
      OnboardingClaimFailureReason.alreadyOwned =>
        OnboardingFailureKind.alreadyOwned,
      OnboardingClaimFailureReason.rateLimited =>
        OnboardingFailureKind.rateLimited,
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

  /// Specific where the device itself classified the failure (wrong
  /// password vs. network not found), generic otherwise — never includes
  /// the SSID/password themselves.
  String _wifiFailureMessage(WifiProvisioningFailureReason reason) {
    switch (reason) {
      case WifiProvisioningFailureReason.authFailed:
        return 'Senha de Wi-Fi incorreta. Confira e tente novamente.';
      case WifiProvisioningFailureReason.networkNotFound:
        return 'O InterBridge não encontrou essa rede Wi-Fi por perto.';
      case WifiProvisioningFailureReason.deviceDisconnected:
        return 'A conexão com o InterBridge foi perdida durante a '
            'configuração do Wi-Fi.';
      case WifiProvisioningFailureReason.sendFailed:
      case WifiProvisioningFailureReason.applyFailed:
      case WifiProvisioningFailureReason.unknown:
      case WifiProvisioningFailureReason.noResponse:
        return 'Não foi possível configurar o Wi-Fi do InterBridge. Tente '
            'novamente.';
      case WifiProvisioningFailureReason.sessionFailed:
        // Unreachable from submitWifi in practice — it intercepts
        // sessionFailed before ever calling this helper (see its doc
        // comment) and reports connectionFailed instead. Kept here only
        // for switch exhaustiveness / any future direct caller.
        return 'Não foi possível configurar o Wi-Fi do InterBridge. Tente '
            'novamente.';
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
      case OnboardingFailureKind.wifiProvisioningNotImplemented:
      case OnboardingFailureKind.permanentIdentityUnavailable:
      case OnboardingFailureKind.claimFailed:
      case OnboardingFailureKind.unknown:
        return 'Não foi possível concluir a configuração agora. Tente novamente.';
    }
  }

  @override
  void dispose() {
    unawaited(_scanSubscription?.cancel());
    _scanTimeoutTimer?.cancel();
    unawaited(_bleTransport.stopScan());
    unawaited(_bleTransport.disconnect());
    super.dispose();
  }
}
