import XCTest

@testable import Runner

/// Covers the exactly-once completion state machine
/// `EspressifBleProvisioningBridge.establishSecurity1` relies on to fix a
/// real physical bug: a bench run with a deliberately mismatched PoP showed
/// the ESP32 closing the BLE connection correctly, but the SDK's own
/// `ESPDevice.connect` completion handler never firing — leaving
/// `establishSecurity1`'s `FlutterResult` pending forever. These tests are
/// pure (no `CBPeripheral`/`ESPDevice`, which have no public initializer
/// usable from a test) and stand in for that physical scenario at the
/// state-machine level.
final class SecurityAttemptGateTests: XCTestCase {
  func testIsActiveReflectsLifecycle() {
    let gate = SecurityAttemptGate()
    XCTAssertFalse(gate.isActive)

    let token = gate.begin { _ in }
    XCTAssertTrue(gate.isActive)

    XCTAssertTrue(gate.complete(token, with: nil))
    XCTAssertFalse(gate.isActive)
  }

  /// Models the actual bug: an unexpected BLE disconnect (never a normal
  /// `connect` completion) must still complete the attempt with an error,
  /// instead of leaving it pending — requirement 1.
  func testUnexpectedDisconnectCompletesAsConnectionFailedInsteadOfHanging() {
    let gate = SecurityAttemptGate()
    var receivedObject: AnyObject?
    _ = gate.begin { value in receivedObject = value as AnyObject? }

    // Simulates handleUnexpectedDisconnect(): it never has the original
    // token, only "something might be pending" — endActive() is what it
    // calls.
    let error = NSObject()
    let completed = gate.endActive(with: error)

    XCTAssertTrue(completed)
    XCTAssertFalse(gate.isActive)
    XCTAssertTrue(receivedObject === error)
  }

  /// Models a late `ESPDevice.connect` completion callback arriving *after*
  /// the unexpected-disconnect path already completed the attempt (or after
  /// a fresh retry started a new one) — it must never fire a second
  /// completion, and never resolve a newer attempt with a stale result —
  /// requirement 2.
  func testLateCallbackAfterUnexpectedDisconnectNeverDoubleCompletes() {
    let gate = SecurityAttemptGate()
    var completions = 0
    let staleToken = gate.begin { _ in completions += 1 }

    XCTAssertTrue(gate.endActive(with: nil))
    XCTAssertEqual(completions, 1)

    // The stale token from the already-completed attempt must never
    // complete anything again.
    XCTAssertFalse(gate.complete(staleToken, with: nil))
    XCTAssertEqual(completions, 1)

    // Nor may it resolve a brand new attempt started in the meantime (a
    // fresh establishSecurity1 retry).
    var newAttemptCompletions = 0
    let newToken = gate.begin { _ in newAttemptCompletions += 1 }
    XCTAssertFalse(gate.complete(staleToken, with: nil))
    XCTAssertEqual(newAttemptCompletions, 0)
    XCTAssertTrue(gate.isActive)

    XCTAssertTrue(gate.complete(newToken, with: nil))
    XCTAssertEqual(newAttemptCompletions, 1)
  }

  func testCompleteWithTheCorrectTokenSucceedsExactlyOnce() {
    let gate = SecurityAttemptGate()
    var completions = 0
    let token = gate.begin { _ in completions += 1 }

    XCTAssertTrue(gate.complete(token, with: nil))
    XCTAssertEqual(completions, 1)

    // A second completion attempt for the very same (already-completed)
    // token must be a no-op, not a second call to the stored FlutterResult.
    XCTAssertFalse(gate.complete(token, with: nil))
    XCTAssertEqual(completions, 1)
  }

  /// Requirement 4: cleanup/cancel (endActive) clears a pending attempt.
  func testEndActiveClearsAPendingAttempt() {
    let gate = SecurityAttemptGate()
    var receivedString: String?
    _ = gate.begin { value in receivedString = value as? String }

    XCTAssertTrue(gate.isActive)
    XCTAssertTrue(gate.endActive(with: "cleaned up"))
    XCTAssertFalse(gate.isActive)
    XCTAssertEqual(receivedString, "cleaned up")
  }

  /// Cleanup/cancel is idempotent: calling it again with nothing pending
  /// must never crash or invoke a stale result a second time.
  func testEndActiveOnAnEmptyGateIsANoOp() {
    let gate = SecurityAttemptGate()
    XCTAssertFalse(gate.endActive(with: nil))
    XCTAssertFalse(gate.isActive)
  }

  func testBeginningANewAttemptSupersedesAnyPreviousOneWithoutCompletingIt() {
    let gate = SecurityAttemptGate()
    var firstCompletions = 0
    let firstToken = gate.begin { _ in firstCompletions += 1 }

    var secondCompletions = 0
    let secondToken = gate.begin { _ in secondCompletions += 1 }

    // Starting a second attempt never itself completes the first one — no
    // FlutterResult call happens purely from calling begin() again.
    XCTAssertEqual(firstCompletions, 0)
    // Nor can the first attempt's stale token complete anything now.
    XCTAssertFalse(gate.complete(firstToken, with: nil))
    XCTAssertEqual(firstCompletions, 0)

    XCTAssertTrue(gate.complete(secondToken, with: nil))
    XCTAssertEqual(secondCompletions, 1)
  }
}
