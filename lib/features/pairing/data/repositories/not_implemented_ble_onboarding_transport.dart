import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';

/// Production default until a real BLE/ESP-IDF Unified Provisioning
/// implementation is validated and wired in (see
/// `BleOnboardingTransport`'s doc comment for the prerequisite).
///
/// Honestly reports "unsupported" instead of hanging or pretending to
/// scan. `MockBleOnboardingTransport` is the debug-only stand-in used to
/// exercise/demo the onboarding flow before real BLE exists.
class NotImplementedBleOnboardingTransport implements BleOnboardingTransport {
  @override
  Future<BleAvailabilityIssue?> checkAvailability() async {
    return BleAvailabilityIssue.unsupported;
  }

  @override
  Stream<DiscoveredInterBridge> scanForProvisioningDevices() {
    return Stream.error(
      UnimplementedError(
        'BLE onboarding is not implemented in this build yet.',
      ),
    );
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String transportId) {
    throw UnimplementedError(
      'BLE onboarding is not implemented in this build yet.',
    );
  }

  @override
  Future<void> establishSecureSession() {
    throw UnimplementedError(
      'BLE onboarding is not implemented in this build yet.',
    );
  }

  @override
  Future<void> requestIdentifyBlink() async {}

  @override
  Future<void> sendWifiCredentials(String ssid, String password) {
    throw UnimplementedError(
      'BLE onboarding is not implemented in this build yet.',
    );
  }

  @override
  Future<void> sendFleetProvisioningMaterial(Map<String, dynamic> material) {
    throw UnimplementedError(
      'BLE onboarding is not implemented in this build yet.',
    );
  }

  @override
  Future<void> disconnect() async {}
}
