import 'package:local_auth/local_auth.dart';

import '../../domain/services/biometric_lock.dart';

/// Native `local_auth` adapter for Face ID, Touch ID, and Android biometrics.
class LocalBiometricAuthenticator implements BiometricAuthenticator {
  LocalBiometricAuthenticator([LocalAuthentication? authentication])
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<BiometricAvailability> availability() async {
    try {
      if (!await _authentication.isDeviceSupported()) {
        return BiometricAvailability.unsupported;
      }
      final enrolled = await _authentication.getAvailableBiometrics();
      return enrolled.isEmpty
          ? BiometricAvailability.notEnrolled
          : BiometricAvailability.available;
    } on Object {
      return BiometricAvailability.unsupported;
    }
  }

  @override
  Future<BiometricAuthenticationResult> authenticate() async {
    try {
      final authenticated = await _authentication.authenticate(
        localizedReason: 'Desbloqueie o InterBridge para continuar',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return authenticated
          ? BiometricAuthenticationResult.success
          : BiometricAuthenticationResult.canceled;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.noBiometricsEnrolled =>
          BiometricAuthenticationResult.notEnrolled,
        LocalAuthExceptionCode.noBiometricHardware =>
          BiometricAuthenticationResult.unsupported,
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled =>
          BiometricAuthenticationResult.canceled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          BiometricAuthenticationResult.temporarilyLocked,
        _ => BiometricAuthenticationResult.failed,
      };
    } on Object {
      return BiometricAuthenticationResult.failed;
    }
  }
}
