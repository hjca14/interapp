/// Lifecycle of one onboarding claim attempt, as tracked by the backend.
enum ClaimSessionStatus { active, completed, expired, cancelled, failed }

/// A backend-tracked session correlating one onboarding attempt (BLE
/// discovery, or a resolved [SetupCode]) to a specific device and user,
/// per the conceptual `/devices/claim/*` API.
class ClaimSession {
  const ClaimSession({
    required this.claimSessionId,
    required this.deviceId,
    required this.userId,
    required this.expiresAt,
    required this.status,
  });

  final String claimSessionId;
  final String deviceId;
  final String userId;
  final DateTime expiresAt;
  final ClaimSessionStatus status;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);
}
