import ESPProvision
import XCTest

@testable import Runner

/// Covers what's testable without a real BLE connection or hardware: the
/// pure `ESPProvisionError` → Dart-facing reason-code mapping used by
/// `EspressifBleProvisioningBridge.sendWifiCredentials`. Everything else in
/// that class talks to `ESPDevice`/`ESPProvisionManager`/CoreBluetooth and
/// needs a real device — see `docs/PHASE_3_ROADMAP.md` for what physical
/// validation remains pending. This does not claim BLE itself was validated
/// here, only that this mapping table is correct and exhaustive.
final class EspressifBleProvisioningBridgeTests: XCTestCase {
  func testSessionErrorMapsToSessionFailed() {
    XCTAssertEqual(
      EspressifBleProvisioningBridge.wifiFailureReasonCode(for: .sessionError),
      "sessionFailed"
    )
  }

  func testConfigurationErrorMapsToApplyFailed() {
    let underlying = NSError(domain: "test", code: 1)
    XCTAssertEqual(
      EspressifBleProvisioningBridge.wifiFailureReasonCode(
        for: .configurationError(underlying)
      ),
      "applyFailed"
    )
  }

  func testWifiStatusErrorMapsToDeviceDisconnected() {
    let underlying = NSError(domain: "test", code: 2)
    XCTAssertEqual(
      EspressifBleProvisioningBridge.wifiFailureReasonCode(
        for: .wifiStatusError(underlying)
      ),
      "deviceDisconnected"
    )
  }

  func testWifiStatusAuthenticationErrorMapsToAuthFailed() {
    XCTAssertEqual(
      EspressifBleProvisioningBridge.wifiFailureReasonCode(
        for: .wifiStatusAuthenticationError
      ),
      "authFailed"
    )
  }

  func testWifiStatusNetworkNotFoundMapsToNetworkNotFound() {
    XCTAssertEqual(
      EspressifBleProvisioningBridge.wifiFailureReasonCode(
        for: .wifiStatusNetworkNotFound
      ),
      "networkNotFound"
    )
  }

  func testUnclassifiedFailuresMapToUnknown() {
    for error: ESPProvisionError in [
      .wifiStatusDisconnected, .wifiStatusUnknownError, .unknownError,
    ] {
      XCTAssertEqual(
        EspressifBleProvisioningBridge.wifiFailureReasonCode(for: error),
        "unknown"
      )
    }
  }

  /// Every reason string this bridge can emit must be one the Dart side
  /// actually recognizes (`_parseWifiFailureReason` in
  /// `ios_ble_onboarding_transport.dart`) — an unrecognized string still
  /// resolves to `WifiProvisioningFailureReason.unknown` there rather than
  /// crashing, but a typo here would silently downgrade a specific,
  /// actionable failure (e.g. wrong password) into a generic one on the
  /// Dart side. This is the fixed vocabulary both sides must agree on.
  func testAllMappedReasonsAreInTheSharedDartVocabulary() {
    let dartRecognizedReasons: Set<String> = [
      "authFailed", "networkNotFound", "deviceDisconnected", "sendFailed",
      "applyFailed", "sessionFailed", "noResponse", "unknown",
    ]
    let allCases: [ESPProvisionError] = [
      .sessionError,
      .configurationError(NSError(domain: "test", code: 1)),
      .wifiStatusError(NSError(domain: "test", code: 2)),
      .wifiStatusDisconnected,
      .wifiStatusAuthenticationError,
      .wifiStatusNetworkNotFound,
      .wifiStatusUnknownError,
      .unknownError,
    ]
    for error in allCases {
      let reason = EspressifBleProvisioningBridge.wifiFailureReasonCode(for: error)
      XCTAssertTrue(
        dartRecognizedReasons.contains(reason),
        "\(reason) (from \(error)) is not in the Dart-recognized vocabulary"
      )
    }
  }
}
