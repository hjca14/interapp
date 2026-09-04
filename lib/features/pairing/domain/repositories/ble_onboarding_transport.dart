import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';

/// Why BLE scanning/connecting can't proceed right now — surfaced to the
/// coordinator so it can show an actionable message ("turn on Bluetooth")
/// instead of a generic failure.
enum BleAvailabilityIssue { bluetoothDisabled, permissionDenied, unsupported }

/// A step the device reported while applying Wi-Fi credentials sent via
/// [BleOnboardingTransport.sendWifiCredentials] — surfaced so the UI can
/// show "sending" vs. "connecting" instead of one opaque spinner.
enum WifiProvisioningProgress {
  /// SSID/password were sent to the device; it has not yet confirmed
  /// applying them.
  sendingConfig,

  /// The device accepted the config and is now attempting to join the
  /// network.
  applyingConfig,
}

/// Why [BleOnboardingTransport.sendWifiCredentials] failed to connect —
/// mirrors the official Espressif SDK's `ProvisionListener` callbacks
/// one-to-one, so the coordinator can show a specific, actionable message
/// (wrong password vs. network not found) instead of one generic failure.
enum WifiProvisioningFailureReason {
  /// The device rejected the password (`ProvisionFailureReason.AUTH_FAILED`).
  authFailed,

  /// The device could not find the given network
  /// (`ProvisionFailureReason.NETWORK_NOT_FOUND`).
  networkNotFound,

  /// The BLE connection was lost while provisioning was in progress
  /// (`ProvisionFailureReason.DEVICE_DISCONNECTED`).
  deviceDisconnected,

  /// The config could not even be sent to the device (`wifiConfigFailed`).
  sendFailed,

  /// The device accepted the config but failed to apply/connect with it,
  /// for a reason it did not further classify (`wifiConfigApplyFailed`).
  applyFailed,

  /// The secure session needed to send the config was not available
  /// (`createSessionFailed`).
  sessionFailed,

  /// A terminal failure the device did not further classify
  /// (`onProvisioningFailed`, or `ProvisionFailureReason.UNKNOWN`).
  unknown,

  /// The integration gave up rather than the device explicitly reporting a
  /// result: either the native SDK never invoked any `ProvisionListener`
  /// callback within a bounded time (the Android bridge's own UX-safety-net
  /// watchdog — not a diagnosis, see its doc comment), or the native event
  /// channel itself failed or closed unexpectedly.
  noResponse,
}

/// Thrown (as a [Stream] error) by
/// [BleOnboardingTransport.sendWifiCredentials] when the device fails to
/// connect to the given network. Never carries the SSID/password that were
/// attempted.
class WifiProvisioningException implements Exception {
  const WifiProvisioningException(this.reason);
  final WifiProvisioningFailureReason reason;

  @override
  String toString() => 'WifiProvisioningException($reason)';
}

/// Raw BLE transport operations for onboarding, per
/// `docs/communication-protocol.md` §7 (ESP-IDF Unified Provisioning /
/// Wi-Fi Provisioning Manager over BLE, Protocomm Security 1).
///
/// This is the lowest layer in the onboarding stack:
///
/// ```text
/// AddInterBridgePage -> OnboardingCoordinator -> BleOnboardingTransport -> real BLE
/// ```
///
/// `OnboardingCoordinator` orchestrates the whole onboarding flow (BLE +
/// backend claim); this interface only exists to keep the eventual
/// BLE/ESP-IDF implementation swappable and testable without a real radio.
/// Android uses a small platform bridge backed by Espressif's official
/// provisioning SDK. Other platforms and Android builds without a locally
/// supplied DEV PoP remain explicitly unavailable.
abstract class BleOnboardingTransport {
  /// `null` when scanning/connecting can proceed.
  Future<BleAvailabilityIssue?> checkAvailability();

  /// Discovers nearby InterBridges currently advertising provisioning mode.
  /// Callers stop listening (and should call [stopScan]) once they have
  /// what they need — this does not complete on its own.
  Stream<DiscoveredInterBridge> scanForProvisioningDevices();

  Future<void> stopScan();

  Future<void> connect(String transportId);

  /// Prepares the Protocomm Security 1 secure session with the
  /// already-[connect]ed device — configures whatever the handshake needs
  /// (proof of possession) so [sendWifiCredentials] can run it. Does not
  /// itself guarantee a real SDK session was established: on Android, the
  /// actual Security 1 handshake happens as part of [sendWifiCredentials]'s
  /// own single continuous transaction with the device, so a
  /// `sessionFailed` can still surface there instead of here — callers must
  /// treat it as a normal, retryable outcome of [sendWifiCredentials], not
  /// something this call rules out in advance.
  Future<void> establishSecureSession();

  /// Asks the connected device to blink its status LED so the user can
  /// visually confirm it's the right physical unit. Reserved for future LED
  /// feedback (`docs/communication-protocol.md` §8) — implementations may
  /// no-op until that firmware behavior exists.
  Future<void> requestIdentifyBlink();

  /// Sends [ssid]/[password] to the already-[establishSecureSession]ed
  /// device via the official Espressif SDK's `prov-config` provisioning
  /// call, and reports its progress until the device confirms it joined
  /// the network.
  ///
  /// [password] may be empty for an open network; [ssid] must not be —
  /// callers must validate that before calling this. Emits
  /// [WifiProvisioningProgress] as the device reports sending/applying the
  /// config, then completes normally once Wi-Fi is connected — this never
  /// emits a value for the final "connected" outcome, only for the
  /// intermediate steps. Emits a [WifiProvisioningException] as a stream
  /// error on any failure, including one reported by the device itself
  /// (wrong password, network not found). Implementations must never log,
  /// persist, or otherwise retain [ssid]/[password] beyond this call.
  Stream<WifiProvisioningProgress> sendWifiCredentials(
    String ssid,
    String password,
  );

  Future<void> sendFleetProvisioningMaterial(Map<String, dynamic> material);

  Future<void> disconnect();
}
