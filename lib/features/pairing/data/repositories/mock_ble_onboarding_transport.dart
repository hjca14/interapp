import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';
import 'package:interapp/features/pairing/domain/repositories/ble_onboarding_transport.dart';

/// Debug-only fake used to exercise/demo the whole onboarding flow before
/// real BLE exists — per PROJECT_CONTEXT.md, "Mock device". Simulates
/// discovering one `InterBridge-A91C`, connecting to it, and accepting any
/// Wi-Fi credentials. Never wired into release builds — see
/// `pairing_providers.dart`, gated by `kDebugMode`.
class MockBleOnboardingTransport implements BleOnboardingTransport {
  // Deliberately not a product device_id: this models only a BLE handle.
  static const fakeDevice = DiscoveredInterBridge(
    transportId: 'mock-ble-handle-a91c',
    friendlyName: 'InterBridge-A91C',
  );

  @override
  Future<BleAvailabilityIssue?> checkAvailability() async => null;

  @override
  Stream<DiscoveredInterBridge> scanForProvisioningDevices() async* {
    await Future<void>.delayed(const Duration(seconds: 1));
    yield fakeDevice;
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String transportId) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<void> establishSecureSession() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<void> requestIdentifyBlink() async {}

  @override
  Future<void> sendWifiCredentials(String ssid, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }

  @override
  Future<void> sendFleetProvisioningMaterial(
    Map<String, dynamic> material,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }

  @override
  Future<void> disconnect() async {}
}
