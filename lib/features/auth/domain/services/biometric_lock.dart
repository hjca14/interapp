import '../entities/auth_session.dart';
import '../repositories/auth_repository.dart';

enum BiometricAvailability { available, notEnrolled, unsupported }

enum BiometricAuthenticationResult {
  success,
  notEnrolled,
  unsupported,
  canceled,
  temporarilyLocked,
  failed,
}

abstract class BiometricAuthenticator {
  Future<BiometricAvailability> availability();

  Future<BiometricAuthenticationResult> authenticate();
}

class BiometricLockSettings {
  const BiometricLockSettings({
    this.enabled = false,
    this.backgroundTimeout = const Duration(minutes: 1),
  });

  final bool enabled;
  final Duration backgroundTimeout;

  BiometricLockSettings copyWith({bool? enabled, Duration? backgroundTimeout}) {
    return BiometricLockSettings(
      enabled: enabled ?? this.enabled,
      backgroundTimeout: backgroundTimeout ?? this.backgroundTimeout,
    );
  }
}

abstract class BiometricLockSettingsRepository {
  Future<BiometricLockSettings> load();

  Future<void> save(BiometricLockSettings settings);
}

/// Decides whether a still-valid Cognito session may be locally unlocked.
/// Biometrics never create or refresh an expired/revoked session.
class BiometricUnlockService {
  const BiometricUnlockService(this._auth, this._biometrics);

  final AuthRepository _auth;
  final BiometricAuthenticator _biometrics;

  Future<BiometricAuthenticationResult> unlock() async {
    final AuthSession session = await _auth.currentSession;
    if (!session.isSignedIn) {
      await _auth.invalidateSession();
      return BiometricAuthenticationResult.failed;
    }
    switch (await _biometrics.availability()) {
      case BiometricAvailability.available:
        return _biometrics.authenticate();
      case BiometricAvailability.notEnrolled:
        return BiometricAuthenticationResult.notEnrolled;
      case BiometricAvailability.unsupported:
        return BiometricAuthenticationResult.unsupported;
    }
  }
}

bool shouldLockAfterBackground(
  BiometricLockSettings settings,
  Duration elapsed,
) {
  return settings.enabled && elapsed >= settings.backgroundTimeout;
}
