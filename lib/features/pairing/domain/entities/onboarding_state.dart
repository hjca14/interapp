import 'package:interapp/features/pairing/domain/entities/claim_session.dart';
import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';

/// The unified onboarding state machine driving all three entry paths
/// (nearby BLE discovery, QR `setup_code`, manual `setup_code`) through
/// `OnboardingCoordinator`. See PROJECT_CONTEXT.md, "Onboarding".
///
/// The two fallback paths ([scanningQr]/[enteringSetupCode]/
/// [resolvingSetupCode]) exist only to resolve *which* device the user
/// means — QR does not skip physical BLE presence. Once resolved, they
/// re-enter the same [scanningBle]/[deviceFound]/... path the primary flow
/// uses, so there is exactly one implementation of "talk to the device and
/// the backend", not three.
enum OnboardingPhase {
  idle,

  /// Checking Bluetooth is on and permission is granted before scanning.
  checkingSetupMode,
  scanningBle,

  /// At least one candidate device has been found; more may still arrive
  /// while the user decides.
  deviceFound,

  /// Waiting for the user to confirm the physically-blinking device matches
  /// the one selected from the list.
  confirmingDevice,
  connectingBle,
  selectingWifi,
  sendingWifi,

  /// The device confirmed it joined the given Wi-Fi network
  /// (`deviceProvisioningSuccess`). Deliberately distinct from [success]:
  /// permanent claim, production identity, Fleet Provisioning and AWS are
  /// still pending — this app build stops here honestly instead of
  /// implying the device is registered/added.
  wifiConnected,
  startingClaim,
  claimActive,
  awsProvisioning,
  verifyingDevice,
  success,

  /// Terminal failure state for any path. [OnboardingState.failureKind]
  /// tells the UI what recovery actions make sense (retry scan, show
  /// fallback options, retry Wi-Fi, etc.) — kept as one phase instead of
  /// one enum value per failure so recovery logic lives in one place.
  error,

  // --- Fallback-only phases ---
  scanningQr,
  enteringSetupCode,
  resolvingSetupCode;

  bool get isTerminal =>
      this == success || this == error || this == wifiConnected;

  bool get isFallbackOnly =>
      this == scanningQr ||
      this == enteringSetupCode ||
      this == resolvingSetupCode;
}

/// Coarse reason for [OnboardingPhase.error], so the UI can pick the right
/// recovery affordance without string-matching a message. Never exposes
/// which specific user/device a code belongs to — see
/// `docs`, "Do not expose device-enumeration information".
enum OnboardingFailureKind {
  bleUnavailable,
  scanTimeout,
  connectionFailed,
  wifiFailed,
  wifiProvisioningNotImplemented,
  permanentIdentityUnavailable,
  claimFailed,
  alreadyOwned,
  invalidOrExpiredCode,
  rateLimited,
  unknown,
}

class OnboardingState {
  const OnboardingState({
    this.phase = OnboardingPhase.idle,
    this.discoveredDevices = const [],
    this.selectedDevice,
    this.claimSession,
    this.failureKind,
    this.failureReason,
    this.wifiProvisioningProgress,
  });

  final OnboardingPhase phase;

  /// Accumulates while [phase] is [OnboardingPhase.scanningBle]/
  /// [OnboardingPhase.deviceFound].
  final List<DiscoveredInterBridge> discoveredDevices;

  /// Set once the user has picked (or a fallback path has resolved) a
  /// specific device to onboard.
  final DiscoveredInterBridge? selectedDevice;

  /// An authenticated permanent identity resolved by QR/manual fallback.
  /// BLE discovery itself must never populate this from its transport handle.
  final ClaimSession? claimSession;

  /// Only meaningful when [phase] is [OnboardingPhase.error].
  final OnboardingFailureKind? failureKind;

  /// Short, user-safe explanation — never a raw exception message or a
  /// backend diagnostic string.
  final String? failureReason;

  /// Only meaningful while [phase] is [OnboardingPhase.sendingWifi] — lets
  /// the UI distinguish "sending" from "connecting" instead of one opaque
  /// spinner. Never carries the SSID/password themselves.
  final WifiProvisioningProgress? wifiProvisioningProgress;

  OnboardingState copyWith({
    OnboardingPhase? phase,
    List<DiscoveredInterBridge>? discoveredDevices,
    DiscoveredInterBridge? selectedDevice,
    ClaimSession? claimSession,
    OnboardingFailureKind? failureKind,
    String? failureReason,
    WifiProvisioningProgress? wifiProvisioningProgress,
  }) {
    return OnboardingState(
      phase: phase ?? this.phase,
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      selectedDevice: selectedDevice ?? this.selectedDevice,
      claimSession: claimSession ?? this.claimSession,
      failureKind: failureKind ?? this.failureKind,
      wifiProvisioningProgress:
          wifiProvisioningProgress ?? this.wifiProvisioningProgress,
      failureReason: failureReason ?? this.failureReason,
    );
  }
}
