import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';

/// Why BLE scanning/connecting can't proceed right now — surfaced to the
/// coordinator so it can show an actionable message ("turn on Bluetooth")
/// instead of a generic failure.
enum BleAvailabilityIssue { bluetoothDisabled, permissionDenied, unsupported }

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

  /// Establishes the Protocomm Security 1 secure session with the
  /// already-[connect]ed device.
  Future<void> establishSecureSession();

  /// Asks the connected device to blink its status LED so the user can
  /// visually confirm it's the right physical unit. Reserved for future LED
  /// feedback (`docs/communication-protocol.md` §8) — implementations may
  /// no-op until that firmware behavior exists.
  Future<void> requestIdentifyBlink();

  Future<void> sendWifiCredentials(String ssid, String password);

  Future<void> sendFleetProvisioningMaterial(Map<String, dynamic> material);

  Future<void> disconnect();
}
