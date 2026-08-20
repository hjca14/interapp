import 'package:interapp/core/protocol/protocol_constants.dart';
import 'package:interapp/features/pairing/domain/entities/claim_session.dart';
import 'package:interapp/features/pairing/domain/entities/setup_code.dart';
import 'package:interapp/features/pairing/domain/repositories/onboarding_claim_repository.dart';

/// Debug-only fake used to exercise/demo the whole onboarding flow — always
/// succeeds. Automated tests use their own purpose-built fakes for
/// scenario coverage (rate-limited, already-owned, expired, ...) instead of
/// this one; see `onboarding_coordinator_test.dart`.
class MockOnboardingClaimRepository implements OnboardingClaimRepository {
  @override
  Future<ClaimSession> start({required String deviceId}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return _session(deviceId);
  }

  @override
  Future<ClaimSession> resolveSetupCode(SetupCode setupCode) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return _session('ib-${''.padLeft(28, '0')}a91c');
  }

  @override
  Future<ClaimSession> complete(String claimSessionId) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return ClaimSession(
      claimSessionId: claimSessionId,
      deviceId: 'ib-${''.padLeft(28, '0')}a91c',
      userId: 'dev-user',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      status: ClaimSessionStatus.completed,
    );
  }

  @override
  Future<void> cancel(String claimSessionId) async {}

  ClaimSession _session(String deviceId) {
    return ClaimSession(
      claimSessionId:
          generateEventId(), // reuses the same evt-<hex> id shape; good enough for a fake session id
      deviceId: deviceId,
      userId: 'dev-user',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      status: ClaimSessionStatus.active,
    );
  }
}
