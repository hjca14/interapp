import 'package:interapp/features/pairing/domain/entities/claim_session.dart';
import 'package:interapp/features/pairing/domain/entities/setup_code.dart';
import 'package:interapp/features/pairing/domain/repositories/onboarding_claim_repository.dart';

/// Production default until the application backend's `/devices/claim/*`
/// API exists. Every call honestly throws
/// [OnboardingClaimFailureReason.backendUnavailable] instead of fabricating
/// a session.
class LocalOnboardingClaimRepository implements OnboardingClaimRepository {
  @override
  Future<ClaimSession> start({required String deviceId}) {
    throw const OnboardingClaimException(OnboardingClaimFailureReason.backendUnavailable);
  }

  @override
  Future<ClaimSession> resolveSetupCode(SetupCode setupCode) {
    throw const OnboardingClaimException(OnboardingClaimFailureReason.backendUnavailable);
  }

  @override
  Future<ClaimSession> complete(String claimSessionId) {
    throw const OnboardingClaimException(OnboardingClaimFailureReason.backendUnavailable);
  }

  @override
  Future<void> cancel(String claimSessionId) {
    throw const OnboardingClaimException(OnboardingClaimFailureReason.backendUnavailable);
  }
}
