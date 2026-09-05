import CoreBluetooth
import ESPProvision
import Flutter
import Foundation

/// Thin native boundary around Espressif's official iOS SDK (`ESPProvision`,
/// github.com/espressif/esp-idf-provisioning-ios). No CoreBluetooth/GATT,
/// protobuf, or Security 0/session logic of our own — every BLE/Protocomm
/// operation goes through `ESPDevice`/`ESPProvisionManager`.
///
/// Mirrors `EspressifBleProvisioningBridge.kt` (Android) at the Dart
/// method/event-channel contract level — same channel names, same discovery
/// and Wi-Fi event shapes — so `OnboardingCoordinator` and the rest of the
/// Dart onboarding stack stay unaware two platforms exist. The two official
/// SDKs are different enough in shape that this implementation is not
/// shared with Android's; see `ios_ble_onboarding_transport.dart`'s doc
/// comment for the two differences this class exists to bridge:
///
/// 1. `ESPDevice.connect(delegate:completionHandler:)` performs the real BLE
///    connect *and* the Security 1 handshake (via
///    `ESPDeviceConnectionDelegate.getProofOfPossesion`) as one operation —
///    so unlike Android, the real BLE connect happens inside this bridge's
///    `establishSecurity1` handler, not `connect` (which only selects the
///    previously-discovered `ESPDevice`, a local operation).
/// 2. `ESPDevice.provision` only exposes one intermediate progress step
///    (`.configApplied`) before the terminal `.success`/`.failure` — there
///    is no separate "device received the config" callback the way
///    Android's SDK has `wifiConfigSent`, so this bridge never emits a
///    `wifiConfigSent` event.
///
/// Physical validation on a real iPhone is still pending as of this class —
/// see `docs/PHASE_3_ROADMAP.md`.
final class EspressifBleProvisioningBridge: NSObject {
    private static let prefix = "InterBridge-"
    private static let methods = "interapp/ble_onboarding"
    private static let discoveryEvents = "interapp/ble_onboarding/discovery"
    private static let wifiEvents = "interapp/ble_onboarding/wifi"

    /// Bound on how long a `sendWifiCredentials` attempt waits for the next
    /// `provision(...)` completion callback before this bridge gives up on
    /// its own — a UX safety net mirroring the Android bridge's own
    /// watchdog (see `WIFI_RESPONSE_TIMEOUT_MS` there), not a diagnosis of
    /// any specific iOS SDK behavior. Not yet exercised against a real
    /// device long enough to know if iOS needs this as much as the Android
    /// bench run that motivated it did — kept for parity and because a
    /// hung Wi-Fi attempt with no way out would be worse than an
    /// occasional, retryable early timeout.
    private static let wifiResponseTimeoutSeconds: TimeInterval = 25

    /// Marks one `sendWifiCredentials` attempt by identity so a late
    /// `provision(...)` callback (or watchdog fire) from an attempt that
    /// already ended — superseded by a new one, or torn down by
    /// `disconnect()` — is never mistaken for the current attempt.
    private final class WifiAttempt {}

    /// Which in-flight attempt (if any) an unexpected BLE disconnect
    /// should resolve.
    enum UnexpectedDisconnectTarget: Equatable {
        case securityAttempt
        case wifiAttempt
        case none
    }

    /// Pure decision backing [handleUnexpectedDisconnect] — testable
    /// without any BLE/`ESPDevice` involvement (see
    /// `SecurityAttemptGate`'s doc for why that matters here). A Security 1
    /// attempt takes priority: in practice the two are never simultaneously
    /// active (`sendWifiCredentials` only starts once `establishSecurity1`
    /// already succeeded), but resolving the earlier stage first is still
    /// the right choice if that invariant is ever violated.
    static func unexpectedDisconnectTarget(
        hasSecurityAttempt: Bool,
        hasWifiAttempt: Bool
    ) -> UnexpectedDisconnectTarget {
        if hasSecurityAttempt { return .securityAttempt }
        if hasWifiAttempt { return .wifiAttempt }
        return .none
    }

    /// Forwards the Wi-Fi event channel's `onListen`/`onCancel` to [bridge]
    /// — a separate `FlutterStreamHandler` because `EspressifBleProvisioningBridge`
    /// itself already is one for the discovery channel, and one object can't
    /// be `FlutterStreamHandler` for two independent channels at once.
    private final class WifiStreamHandler: NSObject, FlutterStreamHandler {
        weak var bridge: EspressifBleProvisioningBridge?
        init(bridge: EspressifBleProvisioningBridge) { self.bridge = bridge }

        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            bridge?.wifiEventSink = events
            return nil
        }

        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            bridge?.wifiEventSink = nil
            return nil
        }
    }

    /// Observes the phone's own Bluetooth radio power/permission state via a
    /// dedicated `CBCentralManager`, purely to answer `checkAvailability` —
    /// never used to scan, connect, or exchange any data.
    /// `ESPProvisionManager`/`ESPBleTransport` own a completely separate
    /// `CBCentralManager` instance for the real BLE work; this is standard
    /// CoreBluetooth radio-state observation (the same category of local OS
    /// check the Android bridge does with `BluetoothManager`/
    /// `ActivityCompat`), not a BLE/GATT protocol implementation of our own.
    private final class BluetoothStateObserver: NSObject, CBCentralManagerDelegate {
        private var manager: CBCentralManager?
        private var pending: ((CBManagerState) -> Void)?

        func currentState(completion: @escaping (CBManagerState) -> Void) {
            let manager = self.manager ?? CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
            self.manager = manager
            if manager.state != .unknown {
                completion(manager.state)
            } else {
                pending = completion
            }
        }

        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            let callback = pending
            pending = nil
            callback?(central.state)
        }
    }

    private let methodChannel: FlutterMethodChannel
    private let discoveryChannel: FlutterEventChannel
    private let wifiChannel: FlutterEventChannel
    private let bluetoothStateObserver = BluetoothStateObserver()

    private var discoveryEventSink: FlutterEventSink?
    private var wifiEventSink: FlutterEventSink?

    /// Devices found by the current (or most recent) scan, keyed by the
    /// opaque handle handed to Dart — never the advertised name or a
    /// Bluetooth identifier directly. Kept across the repeated scan windows
    /// in [runScanLoop] (see its doc) so a `connect` call after the window
    /// that first found a device can still resolve it, and cleared on
    /// [cleanupConnection].
    private var candidatesByHandle: [String: ESPDevice] = [:]
    private var handlesByName: [String: String] = [:]

    /// Selected by `connect`, not yet BLE-connected — becomes
    /// [connectedDevice] once `establishSecurity1` succeeds. See this
    /// class's doc comment, point 1, for why the real connect happens there
    /// and not in `connect`.
    private var pendingDevice: ESPDevice?
    private var connectedDevice: ESPDevice?
    private var proofOfPossession: String?

    private var scanning = false
    /// Bumped on every `startScan`/`stopScan` so a [runScanLoop] callback
    /// from a superseded scan (already stopped, or stopped-then-restarted)
    /// never schedules another round or delivers stale discoveries.
    private var scanGeneration = 0

    /// `true` exactly when the next BLE disconnect is this bridge's own
    /// doing (`cleanupConnection`/`disconnect`) — set right before calling
    /// `ESPDevice.disconnect()` and only cleared again when a fresh
    /// `establishSecurity1` begins caring about the connection again. This
    /// is deliberately *not* reset back to `false` right after calling
    /// `disconnect()`: CoreBluetooth's own disconnect callback
    /// (`peripheralDisconnected`) arrives asynchronously, often after this
    /// method has already returned, so resetting eagerly would race it and
    /// misclassify our own disconnect as an unexpected one.
    private var expectingDisconnect = true

    private var wifiAttempt: WifiAttempt?
    private var wifiWatchdog: DispatchWorkItem?

    /// Tracks the in-flight `establishSecurity1` attempt (if any) and
    /// guarantees exactly-once completion across `ESPDevice.connect`'s own
    /// completion handler, an unexpected BLE disconnect observed through
    /// `ESPBLEDelegate` (see `handleUnexpectedDisconnect`), and an explicit
    /// cleanup/cancel — see `SecurityAttemptGate`'s doc for the physical
    /// bench finding this exists to fix (the ESP32 closing the BLE
    /// connection on a PoP/key mismatch without the SDK's own `connect`
    /// completion handler ever firing, leaving this native call's
    /// `FlutterResult`, and the Dart `establishSecureSession()` future
    /// awaiting it, pending forever).
    private let securityAttemptGate = SecurityAttemptGate()

    init(messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(name: Self.methods, binaryMessenger: messenger)
        discoveryChannel = FlutterEventChannel(name: Self.discoveryEvents, binaryMessenger: messenger)
        wifiChannel = FlutterEventChannel(name: Self.wifiEvents, binaryMessenger: messenger)
        super.init()
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        discoveryChannel.setStreamHandler(self)
        wifiChannel.setStreamHandler(WifiStreamHandler(bridge: self))
    }

    func dispose() {
        cleanupConnection()
        discoveryEventSink = nil
        wifiEventSink = nil
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "checkAvailability":
            checkAvailability(result: result)
        case "startScan":
            startScan(result: result)
        case "stopScan":
            stopScan()
            result(nil)
        case "connect":
            guard let transportId = args?["transportId"] as? String else {
                result(FlutterError(code: "not_found", message: "transportId missing", details: nil))
                return
            }
            connect(transportId: transportId, result: result)
        case "establishSecurity1":
            establishSecurity1(pop: args?["pop"] as? String, result: result)
        case "sendWifiCredentials":
            sendWifiCredentials(
                ssid: args?["ssid"] as? String,
                password: args?["password"] as? String ?? "",
                result: result
            )
        case "disconnect":
            cleanupConnection()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func checkAvailability(result: @escaping FlutterResult) {
        switch CBCentralManager.authorization {
        case .denied, .restricted:
            result("permissionDenied")
            return
        default:
            break
        }
        bluetoothStateObserver.currentState { state in
            switch state {
            case .poweredOn: result("ready")
            case .poweredOff: result("bluetoothDisabled")
            case .unauthorized: result("permissionDenied")
            case .unsupported: result("unsupported")
            default: result("unsupported")
            }
        }
    }

    private func startScan(result: @escaping FlutterResult) {
        guard !scanning, pendingDevice == nil, connectedDevice == nil else {
            result(FlutterError(code: "busy", message: "BLE operation already active", details: nil))
            return
        }
        candidatesByHandle.removeAll()
        handlesByName.removeAll()
        scanning = true
        scanGeneration += 1
        runScanLoop(generation: scanGeneration)
        result(nil)
    }

    /// `ESPProvisionManager.searchESPDevices` is a single batch scan with a
    /// fixed ~5s internal window (hardcoded in the SDK, not configurable) —
    /// unlike Android's `searchBleEspDevices`, which delivers each
    /// advertisement as its own callback for as long as scanning stays
    /// active. There is no continuous per-advertisement primitive on iOS to
    /// call instead. This loop re-issues the batch scan back-to-back while
    /// [scanning] stays true, so the Dart-visible discovery stream still
    /// looks continuous — devices simply surface in ~5s batches instead of
    /// one at a time, a real, deliberately-modeled iOS limitation rather
    /// than a faked continuous scan.
    private func runScanLoop(generation: Int) {
        guard scanning, generation == scanGeneration else { return }
        ESPProvisionManager.shared.searchESPDevices(
            devicePrefix: Self.prefix,
            transport: .ble,
            security: .secure
        ) { [weak self] devices, _ in
            guard let self, self.scanning, generation == self.scanGeneration else { return }
            for device in devices ?? [] where device.name.hasPrefix(Self.prefix) {
                let handle = self.handlesByName[device.name] ?? UUID().uuidString
                self.handlesByName[device.name] = handle
                self.candidatesByHandle[handle] = device
                self.discoveryEventSink?(["transportId": handle, "name": device.name])
            }
            self.runScanLoop(generation: generation)
        }
    }

    private func stopScan() {
        scanning = false
        scanGeneration += 1
        ESPProvisionManager.shared.stopESPDevicesSearch()
    }

    /// Only selects the previously-discovered `ESPDevice` — a local,
    /// synchronous operation. The real BLE connect happens in
    /// [establishSecurity1]; see this class's doc comment, point 1.
    private func connect(transportId: String, result: @escaping FlutterResult) {
        stopScan()
        guard pendingDevice == nil, connectedDevice == nil else {
            result(FlutterError(code: "busy", message: "BLE operation already active", details: nil))
            return
        }
        guard let device = candidatesByHandle[transportId] else {
            result(FlutterError(code: "not_found", message: "Selected BLE device is no longer available", details: nil))
            return
        }
        pendingDevice = device
        result(nil)
    }

    /// Performs the real BLE connect *and* the Protocomm Security 1
    /// handshake — see this class's doc comment, point 1. The PoP is
    /// supplied through `ESPDeviceConnectionDelegate.getProofOfPossesion`
    /// (below), the only supported route: `ESPDevice.proofOfPossession` is
    /// not a public SDK property.
    private func establishSecurity1(pop: String?, result: @escaping FlutterResult) {
        guard let device = pendingDevice else {
            result(FlutterError(code: "not_connected", message: "No BLE connection", details: nil))
            return
        }
        guard let pop, !pop.isEmpty else {
            pendingDevice = nil
            result(FlutterError(code: "pop_missing", message: "Development PoP is not configured", details: nil))
            return
        }
        guard !securityAttemptGate.isActive else {
            result(FlutterError(code: "busy", message: "BLE operation already active", details: nil))
            return
        }
        proofOfPossession = pop
        expectingDisconnect = false
        device.bleDelegate = self
        let token = securityAttemptGate.begin(result: result)
        device.connect(delegate: self) { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .connected:
                    if self.securityAttemptGate.complete(token, with: nil) {
                        self.pendingDevice = nil
                        self.connectedDevice = device
                    }
                case .disconnected, .failedToConnect:
                    let error = FlutterError(code: "connection_failed", message: "Unable to connect to the selected InterBridge", details: nil)
                    if self.securityAttemptGate.complete(token, with: error) {
                        self.pendingDevice = nil
                        self.cleanupConnection()
                    }
                }
            }
        }
    }

    /// ssid/password only ever exist as this method's parameters — never
    /// stored in a field or logged. Calls the official SDK's
    /// `ESPDevice.provision` exactly as documented for manual SSID/password
    /// entry. No GATT, protobuf, or endpoint of our own, no Security 0
    /// fallback. See this class's doc comment, point 2, for why only one
    /// intermediate progress event exists here.
    private func sendWifiCredentials(ssid: String?, password: String, result: @escaping FlutterResult) {
        guard let device = connectedDevice else {
            result(FlutterError(code: "not_connected", message: "No BLE connection", details: nil))
            return
        }
        guard let ssid, !ssid.isEmpty else {
            result(FlutterError(code: "ssid_missing", message: "SSID must not be empty", details: nil))
            return
        }
        let attempt = WifiAttempt()
        wifiAttempt = attempt
        armWifiWatchdog(attempt)
        device.provision(ssid: ssid, passPhrase: password) { [weak self] status in
            DispatchQueue.main.async {
                guard let self, self.wifiAttempt === attempt else { return }
                switch status {
                case .configApplied:
                    self.armWifiWatchdog(attempt)
                    self.wifiEventSink?(["event": "wifiConfigApplied"])
                case .success:
                    self.wifiAttempt = nil
                    self.cancelWifiWatchdog()
                    // Deliberately does not cleanupConnection() here — Dart
                    // explicitly calls disconnect() once it has observed
                    // this event, matching connect()/establishSecurity1()'s
                    // own success paths never self-disconnecting either.
                    self.wifiEventSink?(["event": "wifiConnected"])
                case .failure(let error):
                    self.failWifiAttempt(attempt, reason: Self.wifiFailureReasonCode(for: error))
                }
            }
        }
        result(nil)
    }

    /// Re-arms the Wi-Fi watchdog — see [wifiResponseTimeoutSeconds]'s doc.
    private func armWifiWatchdog(_ attempt: WifiAttempt) {
        cancelWifiWatchdog()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.wifiAttempt === attempt else { return }
            self.failWifiAttempt(attempt, reason: "noResponse")
        }
        wifiWatchdog = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wifiResponseTimeoutSeconds, execute: workItem)
    }

    private func cancelWifiWatchdog() {
        wifiWatchdog?.cancel()
        wifiWatchdog = nil
    }

    private func failWifiAttempt(_ attempt: WifiAttempt, reason: String) {
        guard wifiAttempt === attempt else { return }
        wifiAttempt = nil
        cancelWifiWatchdog()
        cleanupConnection()
        wifiEventSink?(["event": "wifiFailed", "reason": reason])
    }

    /// Mirrors the Android bridge's `wifiFailureReasonCode` mapping, against
    /// `ESPProvisionError` instead of Android SDK's `ProvisionFailureReason`
    /// — see `ios_ble_onboarding_transport.dart` for how each of these
    /// reaches the shared `WifiProvisioningFailureReason` Dart enum.
    /// `.configurationError` covers both "could not send" and "could not
    /// apply" on iOS (the SDK does not distinguish them the way Android
    /// does), and is mapped to `applyFailed` since its own description is
    /// specifically about applying network configuration. The thread-only
    /// cases are unreachable here since `provision` is never called with a
    /// `threadOperationalDataset`. `static` and package-internal (not
    /// `private`) so `RunnerTests` can exercise this pure mapping table
    /// directly via `@testable import Runner`, without needing a real BLE
    /// connection or hardware — see `EspressifBleProvisioningBridgeTests.swift`.
    static func wifiFailureReasonCode(for error: ESPProvisionError) -> String {
        switch error {
        case .sessionError: return "sessionFailed"
        case .configurationError: return "applyFailed"
        case .wifiStatusError: return "deviceDisconnected"
        case .wifiStatusAuthenticationError: return "authFailed"
        case .wifiStatusNetworkNotFound: return "networkNotFound"
        case .wifiStatusDisconnected, .wifiStatusUnknownError, .unknownError: return "unknown"
        default: return "unknown"
        }
    }

    private func cleanupConnection() {
        wifiAttempt = nil
        cancelWifiWatchdog()
        stopScan()
        expectingDisconnect = true
        // A pending establishSecurity1 call must never be left hanging by
        // an external disconnect()/cleanup — a no-op via SecurityAttemptGate
        // if nothing is actually pending.
        securityAttemptGate.endActive(
            with: FlutterError(code: "connection_failed", message: "Unable to connect to the selected InterBridge", details: nil)
        )
        connectedDevice?.disconnect()
        pendingDevice?.disconnect()
        connectedDevice = nil
        pendingDevice = nil
        proofOfPossession = nil
        candidatesByHandle.removeAll()
        handlesByName.removeAll()
    }
}

extension EspressifBleProvisioningBridge: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        discoveryEventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        discoveryEventSink = nil
        stopScan()
        return nil
    }
}

/// Supplies the Security 1 PoP the SDK asks for during
/// `establishSecurity1`'s `connect(delegate:)` call — the only supported way
/// to configure it (`ESPDevice.proofOfPossession` is not a public property).
/// Username is never used: sec2 is not this app's security scheme.
extension EspressifBleProvisioningBridge: ESPDeviceConnectionDelegate {
    func getProofOfPossesion(forDevice: ESPDevice, completionHandler: @escaping (String) -> Void) {
        completionHandler(proofOfPossession ?? "")
    }

    func getUsername(forDevice: ESPDevice, completionHandler: @escaping (String?) -> Void) {
        completionHandler(nil)
    }
}

/// Notified of BLE-level connection loss outside of a `connect(delegate:)`
/// call's own completion handler — e.g. the ESP32 closing the connection on
/// a PoP/key mismatch during Security 1 (see [securityAttemptGate]'s doc), or
/// the device going out of range mid-Wi-Fi-attempt. [expectingDisconnect]
/// filters out this bridge's own intentional disconnects so only a
/// genuinely unexpected loss completes a pending `establishSecurity1` (as
/// `connection_failed`) or fails an in-flight `sendWifiCredentials` attempt
/// (as `deviceDisconnected`) — never both, since the two are never pending
/// at the same time (a Wi-Fi attempt only starts once Security 1 already
/// succeeded).
extension EspressifBleProvisioningBridge: ESPBLEDelegate {
    func peripheralConnected() {}

    func peripheralDisconnected(peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.handleUnexpectedDisconnect()
        }
    }

    func peripheralFailedToConnect(peripheral: CBPeripheral?, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.handleUnexpectedDisconnect()
        }
    }

    private func handleUnexpectedDisconnect() {
        guard !expectingDisconnect else { return }
        switch EspressifBleProvisioningBridge.unexpectedDisconnectTarget(
            hasSecurityAttempt: securityAttemptGate.isActive,
            hasWifiAttempt: wifiAttempt != nil
        ) {
        case .securityAttempt:
            let error = FlutterError(code: "connection_failed", message: "Unable to connect to the selected InterBridge", details: nil)
            if securityAttemptGate.endActive(with: error) {
                pendingDevice = nil
                cleanupConnection()
            }
        case .wifiAttempt:
            if let attempt = wifiAttempt {
                failWifiAttempt(attempt, reason: "deviceDisconnected")
            }
        case .none:
            break
        }
    }
}
