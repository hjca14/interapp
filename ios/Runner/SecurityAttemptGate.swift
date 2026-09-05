import Flutter
import Foundation

/// Coordinates exactly-once completion of one `establishSecurity1` attempt
/// across up to three independent triggers —
/// `ESPDevice.connect(delegate:)`'s own completion handler, an unexpected
/// BLE disconnect observed through `ESPBLEDelegate`, and an explicit
/// cleanup/cancel — mirroring the Android bridge's `WifiAttemptDispatcher`
/// (`android/app/src/main/kotlin/com/interbridge/app/WifiAttemptDispatcher.kt`):
/// pure state, testable without any real BLE/`ESPDevice`/hardware
/// involvement (`CBPeripheral`/`ESPDevice` have no public initializer
/// usable from a test, so this logic must not depend on either). See
/// `EspressifBleProvisioningBridge.establishSecurity1`/
/// `handleUnexpectedDisconnect`.
///
/// A bench run with a deliberately mismatched PoP between app and ESP32
/// showed the ESP32 correctly closing the BLE connection
/// (`security1: Key mismatch. Close connection` on its serial log) without
/// the SDK's own `connect` completion handler ever firing — leaving
/// `establishSecurity1`'s `FlutterResult` pending forever. This gate is
/// what lets the unexpected-disconnect path (`ESPBLEDelegate`) complete
/// that same attempt instead, without risking a double completion if the
/// SDK's own completion handler *also* eventually fires (in either order),
/// or if a fresh `establishSecurity1` retry has already started a new
/// attempt by the time a stale callback from the old one arrives.
final class SecurityAttemptGate {
    /// Opaque identity of one attempt — never compared for anything but
    /// reference equality, and never exposed beyond the token `begin()`
    /// hands back.
    private final class Attempt {
        let result: FlutterResult
        init(result: @escaping FlutterResult) { self.result = result }
    }

    private var current: Attempt?

    /// `true` while an attempt is active, regardless of its identity —
    /// lets a caller check "is anything pending" without holding a token.
    var isActive: Bool { current != nil }

    /// Starts tracking a new attempt bound to [result], returning an
    /// opaque token identifying it. Any attempt this gate was previously
    /// tracking is immediately superseded: its token can never complete
    /// anything again, even if a callback for it arrives later.
    @discardableResult
    func begin(result: @escaping FlutterResult) -> AnyObject {
        let attempt = Attempt(result: result)
        current = attempt
        return attempt
    }

    /// Completes the active attempt with [value] and returns `true` — but
    /// only if [token] (from a prior `begin()`) still identifies it. A
    /// stale token — the attempt it names already completed, or was
    /// superseded by a fresh `begin()` — safely does nothing and returns
    /// `false`. At most one call for a given attempt (across this method
    /// and `endActive`) ever returns `true`.
    @discardableResult
    func complete(_ token: AnyObject, with value: Any?) -> Bool {
        guard let current, current === (token as? Attempt) else { return false }
        self.current = nil
        current.result(value)
        return true
    }

    /// Completes whatever attempt is currently active (if any) with
    /// [value], without needing its specific token — for a caller that
    /// only knows "something might be pending" (an explicit
    /// cleanup/disconnect, or an unexpected BLE disconnect that doesn't
    /// carry the original token). Returns `true` iff an attempt was
    /// actually active and just got completed; `false` (a no-op) if the
    /// gate was already empty.
    @discardableResult
    func endActive(with value: Any?) -> Bool {
        guard let current else { return false }
        self.current = nil
        current.result(value)
        return true
    }
}
