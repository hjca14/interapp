import 'package:interapp/features/pairing/domain/entities/claim_session.dart';
import 'package:interapp/features/pairing/domain/entities/setup_code.dart';

/// Why a claim-repository call failed. Deliberately coarse — the UI must
/// show one generic message per reason and never reveal *why* a code is
/// invalid (unassigned vs. already used vs. someone else's device), per
/// "Do not expose device-enumeration information" /
/// "Do not say whether the code belongs to another specific user".
enum OnboardingClaimFailureReason {
  backendUnavailable,
  invalidOrExpiredCode,
  alreadyOwned,
  rateLimited,
}

class OnboardingClaimException implements Exception {
  const OnboardingClaimException(this.reason);

  final OnboardingClaimFailureReason reason;

  @override
  String toString() => 'OnboardingClaimException(${reason.name})';
}

/// The application backend's onboarding claim API — conceptually:
///
/// ```text
/// POST /devices/claim/start
/// POST /devices/claim/resolve-code
/// POST /devices/claim/complete
/// POST /devices/claim/cancel
/// ```
///
/// The signed-in user must already be authenticated (`AuthRepository`) —
/// this contract doesn't carry credentials itself, only session/device
/// identifiers. Every method throws [OnboardingClaimException] on failure
/// instead of returning a nullable/sentinel result, so a call site can't
/// accidentally treat a failure as success.
abstract class OnboardingClaimRepository {
  /// Starts a claim session for a device found via BLE discovery.
  Future<ClaimSession> start({required String deviceId});

  /// Resolves a [setupCode] (from QR or manual entry) into a claim session
  /// — used by the two fallback paths instead of a BLE-discovered
  /// `device_id`. The resulting session's `deviceId` is then used to find
  /// the physical device over BLE; resolving a code never completes
  /// onboarding by itself.
  Future<ClaimSession> resolveSetupCode(SetupCode setupCode);

  /// Completes the claim once BLE has delivered the device's provisioning
  /// material and the backend has finished AWS Fleet Provisioning.
  Future<ClaimSession> complete(String claimSessionId);

  Future<void> cancel(String claimSessionId);
}
