import 'package:flutter_test/flutter_test.dart';
import 'package:interapp/features/auth/data/repositories/local_auth_repository.dart';
import 'package:interapp/features/auth/domain/entities/auth_session.dart';
import 'package:interapp/features/auth/domain/services/biometric_lock.dart';

void main() {
  group('BiometricUnlockService', () {
    for (final result in [
      BiometricAuthenticationResult.success,
      BiometricAuthenticationResult.canceled,
      BiometricAuthenticationResult.temporarilyLocked,
      BiometricAuthenticationResult.failed,
    ]) {
      test('returns ${result.name} for available biometrics', () async {
        final biometrics = _FakeBiometrics(
          configuredAvailability: BiometricAvailability.available,
          result: result,
        );
        final service = BiometricUnlockService(
          LocalAuthRepository(
            initial: const AuthSession(isSignedIn: true, userId: 'opaque'),
          ),
          biometrics,
        );

        expect(await service.unlock(), result);
        expect(biometrics.authenticateCalls, 1);
      });
    }

    for (final availability in [
      BiometricAvailability.notEnrolled,
      BiometricAvailability.unsupported,
    ]) {
      test('$availability does not open a biometric prompt', () async {
        final biometrics = _FakeBiometrics(
          configuredAvailability: availability,
          result: BiometricAuthenticationResult.success,
        );
        final service = BiometricUnlockService(
          LocalAuthRepository(
            initial: const AuthSession(isSignedIn: true, userId: 'opaque'),
          ),
          biometrics,
        );

        expect(
          await service.unlock(),
          availability == BiometricAvailability.notEnrolled
              ? BiometricAuthenticationResult.notEnrolled
              : BiometricAuthenticationResult.unsupported,
        );
        expect(biometrics.authenticateCalls, 0);
      });
    }

    test(
      'expired session never simulates biometric reauthentication',
      () async {
        final biometrics = _FakeBiometrics(
          configuredAvailability: BiometricAvailability.available,
          result: BiometricAuthenticationResult.success,
        );
        final service = BiometricUnlockService(
          LocalAuthRepository(),
          biometrics,
        );

        expect(await service.unlock(), BiometricAuthenticationResult.failed);
        expect(biometrics.availabilityCalls, 0);
        expect(biometrics.authenticateCalls, 0);
      },
    );
  });

  test('background policy observes enablement and configured timeout', () {
    const settings = BiometricLockSettings(
      enabled: true,
      backgroundTimeout: Duration(minutes: 1),
    );

    expect(
      shouldLockAfterBackground(settings, const Duration(seconds: 59)),
      isFalse,
    );
    expect(
      shouldLockAfterBackground(settings, const Duration(minutes: 1)),
      isTrue,
    );
    expect(
      shouldLockAfterBackground(
        settings.copyWith(enabled: false),
        const Duration(hours: 1),
      ),
      isFalse,
    );
  });
}

class _FakeBiometrics implements BiometricAuthenticator {
  _FakeBiometrics({required this.configuredAvailability, required this.result});

  final BiometricAvailability configuredAvailability;
  final BiometricAuthenticationResult result;
  int availabilityCalls = 0;
  int authenticateCalls = 0;

  @override
  Future<BiometricAuthenticationResult> authenticate() async {
    authenticateCalls++;
    return result;
  }

  @override
  Future<BiometricAvailability> availability() async {
    availabilityCalls++;
    return configuredAvailability;
  }
}
