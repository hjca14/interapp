/// Raw BLE transport operations for provisioning, per
/// `docs/communication-protocol.md` §7 (ESP-IDF Unified Provisioning /
/// Wi-Fi Provisioning Manager over BLE, Protocomm Security 1).
///
/// This is the lowest layer in the pairing stack:
///
/// ```text
/// PairingController -> ProvisioningRepository -> ProvisioningTransport -> real BLE
/// ```
///
/// [ProvisioningRepository] orchestrates the onboarding flow; this
/// interface only exists to keep the eventual BLE/ESP-IDF implementation
/// swappable and testable without a real radio. There is no implementation
/// yet — see PROJECT_CONTEXT.md: before adding a Flutter BLE/ESP
/// provisioning package, its compatibility with ESP-IDF Unified
/// Provisioning / Protocomm Security 1 must be verified first.
abstract class ProvisioningTransport {
  /// Discovers nearby InterBridges currently in BLE provisioning mode,
  /// yielding each discovered device's `device_id`.
  Stream<String> scanForUnprovisionedDevices();

  Future<void> connect(String deviceId);

  /// Establishes the Protocomm Security 1 secure session using the
  /// device's Proof of Possession.
  Future<void> establishSecureSession(String proofOfPossession);

  Future<void> sendWifiCredentials(String ssid, String password);

  Future<void> sendFleetProvisioningMaterial(Map<String, dynamic> material);

  Future<void> disconnect();
}
